import Cocoa

final class AppLogoView: NSView {
    override func awakeFromNib() {
        super.awakeFromNib()
        configureAccessibility()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAccessibility()
    }

    private func configureAccessibility() {
        AccessibilitySupport.configure(self, label: "Logo \(AppBrand.displayName)", role: .image)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 64, height: 64)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds.insetBy(dx: 1, dy: 1)
        let radius = bounds.width * 0.22
        let background = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        AppTheme.Color.accent.setFill()
        background.fill()

        drawQuoteMark(in: bounds)
    }

    /// Český dolní uvozovkový pár „ jako brand mark.
    /// Vyznačuje začátek řeči — vizuální metafora pro push-to-talk diktování.
    private func drawQuoteMark(in rect: NSRect) {
        let pointSize = rect.height * 1.15
        let font = NSFont(name: "Georgia-Bold", size: pointSize)
            ?? NSFont(name: "TimesNewRomanPS-BoldMT", size: pointSize)
            ?? NSFont.systemFont(ofSize: pointSize, weight: .black)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: AppTheme.Color.brandPaper
        ]
        let text = NSAttributedString(string: "„", attributes: attrs)
        let textSize = text.size()

        // „ glyph sedí na baseline s descenders. Posuneme tak, aby viditelné čárky byly
        // opticky vystředěné ve čtverci (baseline trochu nad středem).
        let x = rect.midX - textSize.width / 2
        let y = rect.minY + rect.height * 0.30

        text.draw(at: NSPoint(x: x, y: y))
    }
}
