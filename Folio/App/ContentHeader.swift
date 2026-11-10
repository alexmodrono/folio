import AppKit

/// The bar at the top of the content card: title and status, search, zoom and the chat toggle.
/// It replaces toolbar items so the controls sit inside the card. Empty areas drag the window.
final class ContentHeader: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    let searchField = NSSearchField()
    let zoomOut = CardHeaderButton(symbol: "minus.magnifyingglass", label: String(localized: "Zoom Out"))
    let zoomIn = CardHeaderButton(symbol: "plus.magnifyingglass", label: String(localized: "Zoom In"))
    let chat = CardHeaderButton(symbol: "text.bubble", label: String(localized: "Chat"))

    override init(frame: NSRect) {
        super.init(frame: frame)

        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        for label in [titleLabel, subtitleLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        let titles = NSStackView(views: [titleLabel, subtitleLabel])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 0
        titles.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titles.setHuggingPriority(.defaultHigh, for: .vertical)

        searchField.controlSize = .regular
        searchField.sendsWholeSearchString = true
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let searchMax = searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 320)
        let searchMin = searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140)
        let searchPreferred = searchField.widthAnchor.constraint(equalToConstant: 320)
        searchPreferred.priority = .defaultLow

        let stack = NSStackView(views: [titles, searchField, zoomOut, zoomIn, chat])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Theme.Space.xs
        stack.setCustomSpacing(Theme.Space.m, after: titles)
        stack.setCustomSpacing(Theme.Space.s, after: searchField)
        stack.setCustomSpacing(Theme.Space.s, after: zoomIn)
        stack.setVisibilityPriority(.detachOnlyIfNecessary, for: titles)
        stack.edgeInsets = NSEdgeInsets(top: 0, left: Theme.Space.m, bottom: 0, right: Theme.Space.s)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            searchMax, searchMin, searchPreferred,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { true }

    /// Double-clicking an empty part of the bar zooms or minimizes the window, as a title bar does.
    override func mouseUp(with event: NSEvent) {
        guard event.clickCount == 2 else { return super.mouseUp(with: event) }
        window?.performTitleBarDoubleClickAction()
    }

    /// Hides the reader-only controls on Home and folder pages.
    func setReading(_ reading: Bool) {
        zoomOut.isHidden = !reading
        zoomIn.isHidden = !reading
        chat.isHidden = !reading
        searchField.placeholderString = reading ? String(localized: "Find in document") : String(localized: "Search documents")
    }
}

/// An icon-only button for card headers that shows its bezel on hover, like a toolbar button.
final class CardHeaderButton: NSButton {
    convenience init(symbol: String, label: String) {
        self.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        imagePosition = .imageOnly
        bezelStyle = .accessoryBarAction
        showsBorderOnlyWhileMouseInside = true
        toolTip = label
        setAccessibilityLabel(label)
    }
}

private extension NSWindow {
    func performTitleBarDoubleClickAction() {
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
        switch action {
        case "Minimize": performMiniaturize(nil)
        case "None": break
        default: performZoom(nil)
        }
    }
}
