import AppKit

final class AudioLevelMeterView: NSView {
    private static let fullScaleRMS: Float = 0.02

    private let fillView = NSView()
    private var fillWidthConstraint: NSLayoutConstraint?

    override var intrinsicContentSize: NSSize {
        NSSize(width: 120, height: 6)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func setLevel(_ normalized: Float) {
        let clamped = min(max(normalized / Self.fullScaleRMS, 0), 1)
        fillWidthConstraint?.constant = intrinsicContentSize.width * CGFloat(clamped)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    private func configureViews() {
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.masksToBounds = true

        fillView.translatesAutoresizingMaskIntoConstraints = false
        fillView.wantsLayer = true
        fillView.layer?.cornerRadius = 3
        addSubview(fillView)

        NSLayoutConstraint.activate([
            fillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillView.topAnchor.constraint(equalTo: topAnchor),
            fillView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        fillWidthConstraint = fillView.widthAnchor.constraint(equalToConstant: 0)
        fillWidthConstraint?.isActive = true

        setAccessibilityElement(false)
        refreshColors()
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = AppTheme.Color.separator.withAlphaComponent(0.55).cgColor
            fillView.layer?.backgroundColor = AppTheme.Color.recording.cgColor
        }
    }
}
