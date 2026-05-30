# Locute — implementační plán pro Cursor

## Context

Nativní macOS menu bar appka pro push-to-talk hlasové diktování v češtině. Uživatel přidrží Right Option → nahraje se mikrofon → pustí klávesu → WhisperKit přepíše audio → text se vloží do aktivního okna přes clipboard+Cmd+V. Offline, žádná data ven, postaveno na open source základech.

---

## Projekt

**Xcode projekt:** `Locute`
**Bundle ID:** `com.example.locute`
**Jazyk:** Swift
**Min. macOS:** 14.0 (Sonoma) — požadavek WhisperKit 1.0.0
**Distribuce:** Mimo App Store (sandbox musí být vypnutý)
**SPM závislost:** `https://github.com/argmaxinc/WhisperKit.git` from `"1.0.0"`

---

## Struktura souborů

```
Locute/
├── Locute.xcodeproj/
├── Locute/
│   ├── App/
│   │   └── AppDelegate.swift
│   ├── Core/
│   │   ├── AppState.swift
│   │   ├── HotkeyManager.swift
│   │   ├── AudioRecorder.swift
│   │   ├── TranscriptionEngine.swift
│   │   └── TextInjector.swift
│   ├── UI/
│   │   ├── StatusBarController.swift
│   │   └── PermissionsWindowController.swift
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   │   ├── icon_idle.imageset/
│   │   │   └── icon_recording.imageset/
│   │   ├── Info.plist
│   │   └── Locute.entitlements
```

**Žádný SwiftUI App protokol.** `AppDelegate` je `@main`, žádné scény, žádné hlavní okno.

---

## Info.plist (povinné klíče)

```xml
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key>
<string>Locute needs microphone access to record your voice for transcription.</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
```

## Locute.entitlements

```xml
<key>com.apple.security.device.audio-input</key><true/>
<key>com.apple.security.app-sandbox</key><false/>
```

**KRITICKÉ:** Sandbox musí být `false`. CGEventTap a Accessibility API nejdou v sandboxu.

---

## Xcode Build Configuration

- App Sandbox: **OFF**
- Hardened Runtime: ON, Audio Input: checked
- `MACOSX_DEPLOYMENT_TARGET = 14.0`
- `CODE_SIGN_ENTITLEMENTS = Locute/Locute.entitlements`

---

## State machine — `AppState.swift`

```swift
enum LocuteState: Equatable {
    case launching
    case permissionsNeeded
    case modelDownloading(progress: Double)
    case modelLoading
    case idle
    case recording
    case transcribing
    case injecting
    case error(String)
}

@MainActor
final class AppStateMachine: ObservableObject {
    @Published private(set) var state: LocuteState = .launching

    func transition(to newState: LocuteState) {
        print("[State] \(state) → \(newState)")
        state = newState
    }

    var isRecording: Bool { state == .recording }
    var isReady: Bool { state == .idle }
}
```

Přechody:
```
launching → permissionsNeeded | modelDownloading | modelLoading
permissionsNeeded → modelDownloading  (po udělení oprávnění)
modelDownloading → modelLoading | error
modelLoading → idle | error
idle → recording  (Right Option keyDown)
recording → transcribing | idle  (keyUp; idle pokud příliš krátké)
transcribing → injecting | idle | error
injecting → idle
error → idle  (auto po 3s)
```

---

## AppDelegate.swift

`@main` třída. Vlastní všechny managery (silné reference). Drátuje callback flow.

```swift
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var stateMachine: AppStateMachine!
    private var statusBarController: StatusBarController!
    private var hotkeyManager: HotkeyManager!
    private var audioRecorder: AudioRecorder!
    private var transcriptionEngine: TranscriptionEngine!
    private var textInjector: TextInjector!
    private var permissionsWindowController: PermissionsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        stateMachine = AppStateMachine()
        audioRecorder = AudioRecorder()
        transcriptionEngine = TranscriptionEngine()
        textInjector = TextInjector()
        statusBarController = StatusBarController(stateMachine: stateMachine)
        hotkeyManager = HotkeyManager(stateMachine: stateMachine)

        hotkeyManager.onKeyDown = { [weak self] in self?.handleKeyDown() }
        hotkeyManager.onKeyUp   = { [weak self] in self?.handleKeyUp()   }
        statusBarController.onQuit = { NSApp.terminate(nil) }

        Task { await self.startup() }
    }
```

### Startup sequence

```swift
@MainActor
private func startup() async {
    // 1. Mic permission
    let micOK = await checkMicrophonePermission()
    // 2. Accessibility
    let accessOK = AXIsProcessTrustedWithOptions(
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
    )

    if !micOK || !accessOK {
        stateMachine.transition(to: .permissionsNeeded)
        showPermissionsWindow(micGranted: micOK, accessGranted: accessOK)
        return  // PermissionsWindowController zavolá startup() znovu po udělení
    }

    // 3. Load model
    stateMachine.transition(to: .modelDownloading(progress: 0))
    do {
        try await transcriptionEngine.load { [weak self] p in
            Task { @MainActor in
                self?.stateMachine.transition(to: .modelDownloading(progress: p))
            }
        }
        stateMachine.transition(to: .idle)
    } catch {
        stateMachine.transition(to: .error("Model load failed: \(error.localizedDescription)"))
        return
    }

    // 4. Nainstalovat hotkey tap
    if !hotkeyManager.install() {
        stateMachine.transition(to: .permissionsNeeded)
        showPermissionsWindow(micGranted: true, accessGranted: false)
    }
}
```

### handleKeyDown / handleKeyUp

```swift
private func handleKeyDown() {
    guard stateMachine.isReady else { return }
    Task { @MainActor in
        stateMachine.transition(to: .recording)
        audioRecorder.startRecording()
    }
}

private func handleKeyUp() {
    guard stateMachine.isRecording else { return }
    Task {
        let audioURL = await audioRecorder.stopRecording()
        guard let url = audioURL else {
            await MainActor.run { stateMachine.transition(to: .idle) }
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }

        await MainActor.run { stateMachine.transition(to: .transcribing) }

        do {
            let text = try await transcriptionEngine.transcribe(audioURL: url)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await MainActor.run { stateMachine.transition(to: .idle) }
                return
            }
            await MainActor.run { stateMachine.transition(to: .injecting) }
            await textInjector.inject(text: text)
            await MainActor.run { stateMachine.transition(to: .idle) }
        } catch {
            await MainActor.run {
                stateMachine.transition(to: .error("Transcription failed: \(error.localizedDescription)"))
            }
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { stateMachine.transition(to: .idle) }
        }
    }
}
```

---

## HotkeyManager.swift

**KRITICKÉ:** Right Option je modifier key → emituje `flagsChanged`, NE `keyDown`/`keyUp`. Použít `flagsChanged` jako primární mechanismus.

```swift
import Cocoa, CoreGraphics

final class HotkeyManager {
    var onKeyDown: (() -> Void)?
    var onKeyUp:   (() -> Void)?
    var isKeyCurrentlyDown = false

    private weak var stateMachine: AppStateMachine?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(stateMachine: AppStateMachine) { self.stateMachine = stateMachine }

    @discardableResult
    func install() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passRetained(self).toOpaque()
        ) else {
            print("[HotkeyManager] CGEventTap failed — Accessibility not granted?")
            return false
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = manager.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passRetained(event)
    }

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    guard keyCode == 61, type == .flagsChanged else {
        return Unmanaged.passRetained(event)
    }

    // Right Option specificky: maskAlternate + maskNumericPad
    let flags = event.flags
    let rightOptionDown = flags.contains(.maskAlternate) && flags.contains(.maskNumericPad)

    if rightOptionDown && !manager.isKeyCurrentlyDown {
        manager.isKeyCurrentlyDown = true
        manager.onKeyDown?()
        return nil  // Spolknout event
    } else if !rightOptionDown && manager.isKeyCurrentlyDown {
        manager.isKeyCurrentlyDown = false
        manager.onKeyUp?()
        return nil
    }

    return Unmanaged.passRetained(event)
}
```

---

## AudioRecorder.swift

`actor`. Zachytí mikrofon přes `AVAudioEngine`, resamplinguje na 16kHz, zapíše WAV do temp souboru.

```swift
import AVFoundation

actor AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioBuffers: [AVAudioPCMBuffer] = []
    private var isRecording = false
    private let targetSampleRate: Double = 16_000

    func startRecording() {
        guard !isRecording else { return }
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: targetSampleRate,
                                          channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: hwFormat, to: targetFormat)!

        audioBuffers.removeAll()
        isRecording = true

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let ratio = 16_000.0 / hwFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1)
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var err: NSError?
            converter.convert(to: converted, error: &err) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if err == nil { Task { await self.appendBuffer(converted) } }
        }

        do { try engine.start() } catch {
            inputNode.removeTap(onBus: 0)
            isRecording = false
        }
    }

    private func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isRecording, let copy = buffer.copy() as? AVAudioPCMBuffer else { return }
        audioBuffers.append(copy)
    }

    func stopRecording() async -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let buffers = audioBuffers
        audioBuffers.removeAll()

        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        guard Double(totalFrames) / targetSampleRate >= 0.3 else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("locute_\(UUID().uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                    sampleRate: targetSampleRate, channels: 1, interleaved: false)!
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                        commonFormat: .pcmFormatFloat32, interleaved: false)
            for buf in buffers { try file.write(from: buf) }
            return url
        } catch { return nil }
    }
}
```

---

## TranscriptionEngine.swift

`actor`. Wrapper kolem WhisperKit — load model + transcribe.

```swift
import WhisperKit, AVFoundation

actor TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private let modelName = "large-v3"
    private let language  = "cs"

    func load(progressHandler: @escaping (Double) -> Void) async throws {
        progressHandler(0.0)
        // Fake progress animace — WhisperKit 1.0.0 neposkytuje granulární progress
        let progressTask = Task {
            var p = 0.0
            while !Task.isCancelled && p < 0.95 {
                try? await Task.sleep(for: .milliseconds(500))
                p = min(p + 0.02, 0.95)
                progressHandler(p)
            }
        }
        do {
            whisperKit = try await WhisperKit(WhisperKitConfig(
                model: modelName, verbose: false, logLevel: .none,
                prewarm: false, load: true, download: true
            ))
            progressTask.cancel()
            progressHandler(1.0)
        } catch {
            progressTask.cancel()
            throw error
        }
        await warmUp()
    }

    private func warmUp() async {
        guard let kit = whisperKit else { return }
        // 1s tichého audia — prohřeje Neural Engine
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("locute_warmup.wav")
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let silence = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 16_000)!
        silence.frameLength = 16_000
        guard let file = try? AVAudioFile(forWriting: url, settings: fmt.settings,
                                           commonFormat: .pcmFormatFloat32, interleaved: false),
              (try? file.write(from: silence)) != nil else { return }
        _ = try? await kit.transcribe(audioPath: url.path,
                                       decodeOptions: DecodingOptions(language: language, task: .transcribe))
        try? FileManager.default.removeItem(at: url)
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let kit = whisperKit else { throw TranscriptionError.modelNotLoaded }
        let options = DecodingOptions(
            language: language, task: .transcribe,
            temperature: 0.0, temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true, usePrefillCache: true,
            skipSpecialTokens: true, withoutTimestamps: true,
            suppressBlank: true,
            compressionRatioThreshold: 2.4, logProbThreshold: -1.0, noSpeechThreshold: 0.6
        )
        let results = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        return results
            .flatMap { $0.segments }
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    var errorDescription: String? { "WhisperKit model is not loaded." }
}
```

---

## TextInjector.swift

`actor`. Uloží clipboard → vloží text → simuluje Cmd+V → obnoví clipboard.

```swift
import Cocoa, CoreGraphics

actor TextInjector {
    func inject(text: String) async {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        let changeCount = pasteboard.changeCount

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try? await Task.sleep(for: .milliseconds(50))
        simulateCmdV()
        try? await Task.sleep(for: .milliseconds(500))

        // Obnovit clipboard jen pokud ho nikdo jiný nezměnil
        if pasteboard.changeCount == changeCount + 1 {
            pasteboard.clearContents()
            if let prev = previous { pasteboard.setString(prev, forType: .string) }
        }
    }

    private func simulateCmdV() {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        // 0x09 = klávesa V (hardware scan code, layout-independent)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)!
        down.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)!
        up.flags = .maskCommand
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
```

---

## StatusBarController.swift

`@MainActor`. Sleduje stav přes Combine, mění ikonu v menu baru.

```swift
import Cocoa, Combine

@MainActor
final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var cancellables = Set<AnyCancellable>()
    var onQuit: (() -> Void)?
    private var pulseTimer: Timer?

    init(stateMachine: AppStateMachine) {
        setupMenu()
        stateMachine.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.update(for: $0) }
            .store(in: &cancellables)
    }

    private func update(for state: LocuteState) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        guard let btn = statusItem.button else { return }

        switch state {
        case .idle:
            btn.image = NSImage(systemSymbolName: "mic", accessibilityDescription: nil)
            btn.image?.isTemplate = true
            btn.toolTip = "Hold Right Option to dictate"

        case .recording:
            // Pulzující červená ikona
            var on = true
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak btn] _ in
                on.toggle()
                let name = on ? "mic.fill" : "mic"
                let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(
                        NSImage.SymbolConfiguration(paletteColors: [.systemRed])
                    )
                btn?.image = img
                btn?.image?.isTemplate = false
            }
            btn.toolTip = "Recording…"

        case .transcribing, .injecting:
            btn.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
            btn.image?.isTemplate = true
            btn.toolTip = "Transcribing…"

        case .modelDownloading(let p):
            btn.toolTip = "Downloading model: \(Int(p * 100))%"
            btn.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            btn.image?.isTemplate = true

        case .permissionsNeeded, .error:
            btn.image = NSImage(systemSymbolName: "mic.slash", accessibilityDescription: nil)
            btn.image?.isTemplate = true

        default:
            btn.image = NSImage(systemSymbolName: "mic", accessibilityDescription: nil)
            btn.image?.isTemplate = true
        }
    }

    private func setupMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Locute", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let hint = NSMenuItem(title: "Hold Right Option to dictate", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Locute", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func quit() { onQuit?() }
}
```

---

## PermissionsWindowController.swift

Zobrazí se při prvním spuštění. Polling každou 1s — jakmile jsou oprávnění, zavře se a zavolá `onPermissionsGranted`.

```swift
import Cocoa, AVFoundation

final class PermissionsWindowController: NSWindowController {
    var onPermissionsGranted: (() -> Void)?
    private var checkTimer: Timer?

    init(micGranted: Bool, accessGranted: Bool) {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Locute — Setup Required"
        win.center()
        win.isReleasedWhenClosed = false
        super.init(window: win)
        buildUI(micGranted: micGranted, accessGranted: accessGranted)
        startPolling()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI(micGranted: Bool, accessGranted: Bool) {
        // NSStackView s dvěma řádky (mikrofon, accessibility)
        // Každý řádek: ✅/❌ + label + detail + [Open Settings] tlačítko pokud není granted
        // Open Settings URL:
        //   Mic:   "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        //   Access:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        // (Cursor: implementuj NSStackView layout dle popisu výše)
    }

    private func startPolling() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            let ax  = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            )
            if mic && ax {
                self?.checkTimer?.invalidate()
                DispatchQueue.main.async {
                    self?.close()
                    self?.onPermissionsGranted?()
                }
            }
        }
    }

    override func close() { checkTimer?.invalidate(); super.close() }
}
```

---

## Verifikace (jak otestovat)

1. **Build** — žádné compile errory
2. **Spuštění** — ikona se objeví v menu baru, žádná ikona v Docku
3. **Permissions flow** — při prvním spuštění se zobrazí okno se statusem oprávnění
4. **Model download** — tooltip na ikoně ukazuje progress stahování (~1.5GB, jen první spuštění)
5. **Dictation** — otevřít TextEdit, přidrž Right Option, říct větu česky, pustit → text se vloží
6. **Recording indicator** — ikona pulzuje červeně při nahrávání
7. **Krátký stisk** (< 0.3s) → žádná akce, návrat do idle
8. **Clipboard** — po vložení textu je clipboard obnoven na původní obsah

---

## Known gotchas pro Cursor

- **Right Option = flagsChanged, ne keyDown.** Modifier keys na macOS neemitují `keyDown`.
- **AVAudioEngine tap format** — vždy použij hardware format pro tap, pak resamplinguj přes `AVAudioConverter`. Přímá instalace na 16kHz formát selhává na většině HW.
- **WhisperKit transcribe returns `[TranscriptionResult]`** — každý má `.segments`, každý segment má `.text`. Při implementaci ověř aktuální API v1.0.0.
- **CGEventTap memory** — `Unmanaged.passRetained` v `install()` vytvoří strong reference na lifetime procesu. Pro menu bar appku OK.
- **AXIsProcessTrustedWithOptions prompt** — volat s `false` při pollingu, s `true` jen jednou při prvním zobrazení permissions window.
