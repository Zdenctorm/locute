import Cocoa

/// Karty nastavení (hotkey, model, chování) — bez oprávnění.
@MainActor
final class PreferencesPanelBuilder: NSObject {
    private let hotkeyPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let activationPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let activationDetailLabel = AppTheme.label("", font: AppTheme.Font.body, color: AppTheme.Color.body, lines: 0)
    private let modelPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modelDetailLabel = AppTheme.label("", font: AppTheme.Font.body, color: AppTheme.Color.body, lines: 0)
    private let postProcessingSizePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let postProcessingSizeDetailLabel = AppTheme.label("", font: AppTheme.Font.body, color: AppTheme.Color.body, lines: 0)
    private let microphonePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let showInDockCheckbox = NSButton(checkboxWithTitle: "Zobrazit ikonu v Docku", target: nil, action: nil)
    private let reviewBeforePasteCheckbox = NSButton(
        checkboxWithTitle: "Nejdřív zkontrolovat přepis (bez automatického vložení)",
        target: nil,
        action: nil
    )
    private let soundFeedbackCheckbox = NSButton(checkboxWithTitle: "Zvuková zpětná vazba", target: nil, action: nil)
    private let livePreviewCheckbox = NSButton(
        checkboxWithTitle: "Zobrazovat průběžný přepis při držení klávesy",
        target: nil,
        action: nil
    )
    let hotkeyTapHealthLabel = AppTheme.label(
        "",
        font: AppTheme.Font.footnote,
        color: AppTheme.Color.body,
        lines: 0
    )

    var hotkeyHealthProvider: (() -> HotkeyHealth)?

    func buildAllCards() -> [NSView] {
        [
            buildHotkeyCard(),
            buildActivationCard(),
            buildModelCard(),
            buildPostProcessingCard(),
            buildMicrophoneCard(),
            buildBehaviorCard()
        ]
    }

    func refreshMicrophonePicker() {
        microphonePicker.removeAllItems()
        microphonePicker.addItem(withTitle: "Systémový výchozí")
        for device in MicrophonePreference.discoveredDevices() {
            microphonePicker.addItem(withTitle: device.localizedName)
            microphonePicker.lastItem?.representedObject = device.uniqueID
        }
        if let uid = MicrophonePreference.selectedDeviceUID,
           let idx = (0 ..< microphonePicker.numberOfItems).first(where: { i in
               (microphonePicker.item(at: i)?.representedObject as? String) == uid
           }) {
            microphonePicker.selectItem(at: idx)
        } else {
            microphonePicker.selectItem(at: 0)
        }
    }

    func refreshHotkeyTapHealthLabel() {
        if !InputMonitoringSettings.isGranted() {
            hotkeyTapHealthLabel.stringValue =
                "Bez Monitorování vstupu klávesa funguje jen když je \(AppBrand.displayName) v popředí — povol v Průvodci nastavením."
            hotkeyTapHealthLabel.textColor = AppTheme.Color.danger
            return
        }
        guard let health = hotkeyHealthProvider?() else {
            hotkeyTapHealthLabel.stringValue = ""
            return
        }
        switch health {
        case .notTrusted:
            hotkeyTapHealthLabel.stringValue =
                "Klávesu nelze sledovat — nejdřív povol Zpřístupnění pro tuto kopii aplikace."
            hotkeyTapHealthLabel.textColor = AppTheme.Color.danger
        case .tapMissing:
            hotkeyTapHealthLabel.stringValue =
                "Sledování klávesy není aktivní — restartuj \(AppBrand.displayName) po povolení Zpřístupnění."
            hotkeyTapHealthLabel.textColor = AppTheme.Color.warning
        case .receivingEvents:
            hotkeyTapHealthLabel.stringValue =
                "Sledování klávesy je aktivní. Otestuj stiskem diktovací klávesy (funguje i v jiné aplikaci)."
            hotkeyTapHealthLabel.textColor = AppTheme.Color.success
        case .stale(let seconds):
            hotkeyTapHealthLabel.stringValue =
                "Klávesu dlouho nevidím (\(Int(seconds)) s) — stiskni diktovací klávesu jednou pro probuzení."
            hotkeyTapHealthLabel.textColor = AppTheme.Color.warning
        }
    }

    private func buildHotkeyCard() -> NSView {
        hotkeyPicker.removeAllItems()
        hotkeyPicker.addItems(withTitles: HotkeyChoice.allCases.map(\.label))
        let currentIndex = HotkeyChoice.allCases.firstIndex(of: HotkeyPreference.current)
            ?? HotkeyChoice.allCases.firstIndex(of: HotkeyPreference.recommendedDefault)
            ?? 0
        hotkeyPicker.selectItem(at: currentIndex)
        hotkeyPicker.target = self
        hotkeyPicker.action = #selector(hotkeyChoiceChanged(_:))

        let title = AppTheme.label("Klávesa pro diktování", font: AppTheme.Font.headline, color: AppTheme.Color.title)
        let detail = AppTheme.label(
            "Doporučeno na českém Macu: pravý Command (⌘). Pravý Option (⌥) je často AltGr (@, #, &) a v jiných aplikacích (Linear, Cursor) nemusí spustit diktování.",
            font: AppTheme.Font.body,
            color: AppTheme.Color.body,
            lines: 0
        )

        let recommendButton = AppTheme.secondaryButton(
            "Použít doporučenou klávesu (\(HotkeyPreference.recommendedDefault.label))",
            target: self,
            action: #selector(useRecommendedHotkey(_:))
        )
        return AppTheme.card([title, detail, hotkeyPicker, recommendButton, hotkeyTapHealthLabel])
    }

    @objc private func hotkeyChoiceChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < HotkeyChoice.allCases.count else { return }
        HotkeyPreference.current = HotkeyChoice.allCases[idx]
        DiagnosticsLogger.log("Hotkey preference changed to \(HotkeyChoice.allCases[idx].rawValue)")
    }

    @objc private func useRecommendedHotkey(_ sender: NSButton) {
        HotkeyPreference.current = HotkeyPreference.recommendedDefault
        let idx = HotkeyChoice.allCases.firstIndex(of: HotkeyPreference.current) ?? 0
        hotkeyPicker.selectItem(at: idx)
    }

    private func buildModelCard() -> NSView {
        modelPicker.removeAllItems()
        modelPicker.addItems(withTitles: TranscriptionModelPreference.allCases.map(\.label))
        let currentIndex = TranscriptionModelPreference.allCases.firstIndex(of: TranscriptionModelPreference.current) ?? 0
        modelPicker.selectItem(at: currentIndex)
        modelPicker.target = self
        modelPicker.action = #selector(modelPreferenceChanged(_:))

        let title = AppTheme.label("Model přepisu (Whisper)", font: AppTheme.Font.headline, color: AppTheme.Color.title)
        let speedNote = AppTheme.label(
            "Turbo = rychlejší přepis po puštění klávesy. Přesnost = lepší pro technické termíny, pomalejší.",
            font: AppTheme.Font.footnote,
            color: AppTheme.Color.body,
            lines: 0
        )
        modelDetailLabel.stringValue = TranscriptionModelPreference.current.detail

        return AppTheme.card([title, speedNote, modelDetailLabel, modelPicker])
    }

    private func buildActivationCard() -> NSView {
        activationPicker.removeAllItems()
        activationPicker.addItems(withTitles: DictationActivationMode.allCases.map(\.label))
        let idx = DictationActivationMode.allCases.firstIndex(of: DictationActivationPreference.current) ?? 0
        activationPicker.selectItem(at: idx)
        activationPicker.target = self
        activationPicker.action = #selector(activationModeChanged(_:))
        activationDetailLabel.stringValue = DictationActivationPreference.current.detail
        let title = AppTheme.label("Způsob aktivace", font: AppTheme.Font.headline, color: AppTheme.Color.title)
        return AppTheme.card([title, activationDetailLabel, activationPicker])
    }

    @objc private func activationModeChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < DictationActivationMode.allCases.count else { return }
        DictationActivationPreference.current = DictationActivationMode.allCases[idx]
        activationDetailLabel.stringValue = DictationActivationPreference.current.detail
    }

    private func buildPostProcessingCard() -> NSView {
        postProcessingSizePicker.removeAllItems()
        postProcessingSizePicker.addItems(withTitles: PostProcessingModelSize.allCases.map(\.label))
        let idx = PostProcessingModelSize.allCases.firstIndex(of: PostProcessingPreference.modelSize) ?? 0
        postProcessingSizePicker.selectItem(at: idx)
        postProcessingSizePicker.target = self
        postProcessingSizePicker.action = #selector(postProcessingSizeChanged(_:))
        postProcessingSizeDetailLabel.stringValue = PostProcessingPreference.modelSize.detail
        let title = AppTheme.label("AI oprava přepisu (lokální LLM)", font: AppTheme.Font.headline, color: AppTheme.Color.title)
        let detail = AppTheme.label(
            "Zapni/vypni v menu baru. Velikost modelu ovlivní kvalitu a rychlost offline úprav textu.",
            font: AppTheme.Font.body,
            color: AppTheme.Color.body,
            lines: 0
        )
        return AppTheme.card([title, detail, postProcessingSizeDetailLabel, postProcessingSizePicker])
    }

    @objc private func postProcessingSizeChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < PostProcessingModelSize.allCases.count else { return }
        PostProcessingPreference.modelSize = PostProcessingModelSize.allCases[idx]
        postProcessingSizeDetailLabel.stringValue = PostProcessingPreference.modelSize.detail
    }

    private func buildMicrophoneCard() -> NSView {
        refreshMicrophonePicker()
        microphonePicker.target = self
        microphonePicker.action = #selector(microphoneChanged(_:))
        let title = AppTheme.label("Mikrofon", font: AppTheme.Font.headline, color: AppTheme.Color.title)
        let detail = AppTheme.label(
            "Výchozí systémový vstup nebo konkrétní zařízení. Platí pro další nahrávání.",
            font: AppTheme.Font.body,
            color: AppTheme.Color.body,
            lines: 0
        )
        return AppTheme.card([title, detail, microphonePicker])
    }

    @objc private func microphoneChanged(_ sender: NSPopUpButton) {
        if sender.indexOfSelectedItem <= 0 {
            MicrophonePreference.selectedDeviceUID = nil
        } else {
            MicrophonePreference.selectedDeviceUID = sender.selectedItem?.representedObject as? String
        }
    }

    private func buildBehaviorCard() -> NSView {
        showInDockCheckbox.state = AppAppearancePreference.showInDock ? .on : .off
        showInDockCheckbox.target = self
        showInDockCheckbox.action = #selector(showInDockChanged(_:))
        reviewBeforePasteCheckbox.state = DictationReviewPreference.isEnabled ? .on : .off
        reviewBeforePasteCheckbox.target = self
        reviewBeforePasteCheckbox.action = #selector(reviewBeforePasteChanged(_:))
        soundFeedbackCheckbox.state = SoundFeedbackService.isEnabled ? .on : .off
        soundFeedbackCheckbox.target = self
        soundFeedbackCheckbox.action = #selector(soundFeedbackChanged(_:))
        livePreviewCheckbox.state = DictationPreviewPreference.isEnabled ? .on : .off
        livePreviewCheckbox.target = self
        livePreviewCheckbox.action = #selector(livePreviewChanged(_:))
        let title = AppTheme.label("Chování aplikace", font: AppTheme.Font.headline, color: AppTheme.Color.title)
        return AppTheme.card([title, showInDockCheckbox, reviewBeforePasteCheckbox, livePreviewCheckbox, soundFeedbackCheckbox])
    }

    @objc private func showInDockChanged(_ sender: NSButton) {
        AppAppearancePreference.showInDock = sender.state == .on
    }

    @objc private func reviewBeforePasteChanged(_ sender: NSButton) {
        DictationReviewPreference.isEnabled = sender.state == .on
    }

    @objc private func soundFeedbackChanged(_ sender: NSButton) {
        SoundFeedbackService.isEnabled = sender.state == .on
    }

    @objc private func livePreviewChanged(_ sender: NSButton) {
        DictationPreviewPreference.isEnabled = sender.state == .on
    }

    @objc private func modelPreferenceChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < TranscriptionModelPreference.allCases.count else { return }
        TranscriptionModelPreference.current = TranscriptionModelPreference.allCases[idx]
        DiagnosticsLogger.log("Model preference changed to \(TranscriptionModelPreference.allCases[idx].rawValue)")
        modelDetailLabel.stringValue = TranscriptionModelPreference.current.detail
    }
}
