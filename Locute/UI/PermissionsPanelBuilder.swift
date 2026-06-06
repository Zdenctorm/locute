import Cocoa

/// Sdílené UI pro řádky oprávnění (průvodce nastavením).
enum PermissionsPanelBuilder {
    static func permissionRow(
        number: String,
        title: String,
        detail: String,
        badge: NSTextField,
        button: NSButton,
        detailView: NSView? = nil,
        extraViews: [NSView] = []
    ) -> NSView {
        let numberLabel = NSTextField(labelWithString: number)
        numberLabel.font = NSFont.systemFont(ofSize: 32, weight: .semibold)
        numberLabel.textColor = AppTheme.Color.accent
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = AppTheme.label(title, font: AppTheme.Font.headline, color: AppTheme.Color.title)
        let detailLabel: NSView = detailView ?? AppTheme.label(
            detail,
            font: AppTheme.Font.body,
            color: AppTheme.Color.body,
            lines: 0
        )

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let titleRow = NSStackView(views: [titleLabel, spacer, badge])
        titleRow.orientation = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = AppTheme.Spacing.row
        badge.setContentHuggingPriority(.required, for: .horizontal)

        var contentChildren: [NSView] = [titleRow]
        if !detail.isEmpty || detailView != nil {
            contentChildren.append(detailLabel)
        }
        contentChildren.append(contentsOf: extraViews)
        contentChildren.append(button)
        let content = NSStackView(views: contentChildren)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = AppTheme.Spacing.tight
        content.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(numberLabel)
        row.addSubview(content)

        NSLayoutConstraint.activate([
            numberLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 4),
            numberLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: -6),
            numberLabel.widthAnchor.constraint(equalToConstant: 36),

            content.leadingAnchor.constraint(equalTo: numberLabel.trailingAnchor, constant: AppTheme.Spacing.row),
            content.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            content.topAnchor.constraint(equalTo: row.topAnchor),
            content.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])

        return row
    }
}
