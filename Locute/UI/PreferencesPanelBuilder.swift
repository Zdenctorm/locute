import Cocoa

/// Karty nastavení (hotkey, model, chování) — bez oprávnění.
@MainActor
final class PreferencesPanelBuilder: NSObject {
    private let hotkeyPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let activationPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let activationDetailLabel = AppTheme.label("", font: AppTheme.Font.body, color: AppTheme.Color.body, lines: 0)
    private let modelPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modelDetailLabel = AppTheme.label("", font: AppTheme.Font.footnote, color: AppTheme.Color.body, lines: 0)
    private let postProcessingSizePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let postProcessingSizeDetailLabel = AppTheme.label("", font: AppTheme.Font.footnote, color: AppTheme.Color.body, lines: 0)
    private let microphonePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let showInDockCheckbox = NSButton(checkboxWithTitle: "Zobrazit ikonu v Docku", target: nil, action: nil)
    private let reviewBeforePasteCheckbox = NSButton(
        checkboxWithTitle: "Zkontrolovat před vložením",
        target: nil,
        action: nil
    )
    private let soundFeedbackCheckbox = NSButton(checkboxWithTitle: "Zvuková zpětná vazba", target: nil, action: nil)
    private let livePreviewCheckbox = NSButton(
        checkboxWithTitle: "Náhled během diktování",
        target: nil,
        action: nil
    )
    private let postProcessingCheckbox = NSButton(
        checkboxWithTitle: "Oprava textu po přepisu",
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
            buildMicrophoneCard(),
            buildBehaviorCard()
        ]
    }

    func buildGroupedSections() -> [NSView] {
        [
            AppTheme.sectionHeader("Diktování"),
            buildHotkeyCard(),
            buildActivationCard(),
            buildMicrophoneCard(),
            buildBehaviorCard(),
            AppTheme.sectionHeader("Přepis"),
            buildModelCard()
        ]
    }

    func buildAdvancedCards() -> [NSView] {
        [buildPostProcessingCard()]
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
            hotkeyTapHealthLabel.stringValue = "Bez Monitorování vstupu funguje klávesa jen v popředí."
            hotkeyTapHealthLabel.textColor = AppTheme.Color.danger
            return
        }
        guard let health = hotkeyHealthProvider?() else {
            hotkeyTapHealthLabel.stringValue = ""
            return
        }
        switch health {
        case .notTrusted:
            hotkeyTapHealthLabel.stringValue = "Chybí Zpřístupnění."
            hotkeyTapHealthLabel.textColor = AppTheme.Color.danger
        case .tapMissing:
            hotkeyTapHealthLabel.stringValue = "Klávesu nelze sledovat — restartuj \(AppBrand.displayName)."
            hotkeyTapHealthLabel.textColor = AppTheme.Color.warning
        case .receivingEvents:
            hotkeyTapHealthLabel.stringValue = "Klávesa funguje."
            hotkeyTapHealthLabel.textColor = AppTheme.Color.success
        case .stale:
            hotkeyTapHealthLabel.stringValue = "Stiskni diktovací klávesu jednou."
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
        let recommendButton = AppTheme.secondaryButton(
            "Doporučená klávesa",
            target: self,
            action: #selector(useRecommendedHotkey(_:))
        )
        return AppTheme.card([title, hotkeyPicker, recommendButton, hotkeyTapHealthLabel])
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

        let title = AppTheme.label("Model přepisu", font: AppTheme.Font.headline, color: AppTheme.Color.title)
        modelDetailLabel.stringValue = TranscriptionModelPreference.current.detail

        postProcessingCheckbox.state = PostProcessingPreference.isEnabled ? .on : .off
        postProcessingCheckbox.target = self
        postProcessingCheckbox.action = #selector(postProcessingChanged(_:))

        return AppTheme.card([title, modelPicker, modelDetailLabel, postProcessingCheckbox])
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
        return AppTheme.card([title, activationPicker, activationDetailLabel])
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
        let title = AppTheme.label("Oprava textu", font: AppTheme.Font.headline, color: AppTheme.Color.title)
        return AppTheme.card([title, postProcessingSizePicker, postProcessingSizeDetailLabel])
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
        return AppTheme.card([title, microphonePicker])
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
        let title = AppTheme.label("Chování", font: AppTheme.Font.headline, color: AppTheme.Color.title)
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

    @objc private func postProcessingChanged(_ sender: NSButton) {
        PostProcessingPreference.isEnabled = sender.state == .on
    }

    @objc private func modelPreferenceChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < TranscriptionModelPreference.allCases.count else { return }
        TranscriptionModelPreference.current = TranscriptionModelPreference.allCases[idx]
        DiagnosticsLogger.log("Model preference changed to \(TranscriptionModelPreference.allCases[idx].rawValue)")
        modelDetailLabel.stringValue = TranscriptionModelPreference.current.detail
    }
}
