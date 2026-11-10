import AppKit

/// The bar at the top of the content card: title and status, search, zoom and the chat toggle.
/// It replaces toolbar items so the controls sit inside the card. Empty areas drag the window.
final class ContentHeader: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    let searchField = NSSearchField()
    /// Page display (single, continuous, two pages, book), thumbnails and rotation, in a menu.
    let display = CardHeaderButton(symbol: "rectangle.portrait.on.rectangle.portrait", label: String(localized: "Page Display"))
    let zoomOut = CardHeaderButton(symbol: "minus.magnifyingglass", label: String(localized: "Zoom Out"))
    /// The zoom level; clicking it offers fit options and preset sizes.
    let zoomLevel = CardHeaderButton(title: "100 %", label: String(localized: "Zoom"))
    let zoomIn = CardHeaderButton(symbol: "plus.magnifyingglass", label: String(localized: "Zoom In"))
    /// Mirrors the sidebar button on the window's left: a toggle for the chat column on the right.
    let chat = CardHeaderButton(symbol: "sidebar.right", label: String(localized: "Show Chat"), isToggle: true)

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

        let stack = NSStackView(views: [titles, searchField, display, zoomOut, zoomLevel, zoomIn, chat])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        // 4 pt inside a group (the zoom pair), 12 pt between groups.
        stack.spacing = Theme.Space.xs
        stack.setCustomSpacing(Theme.Space.m, after: titles)
        stack.setCustomSpacing(Theme.Space.m, after: searchField)
        stack.setCustomSpacing(Theme.Space.m, after: display)
        stack.setCustomSpacing(0, after: zoomOut)
        stack.setCustomSpacing(0, after: zoomLevel)
        stack.setCustomSpacing(Theme.Space.m, after: zoomIn)
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
    /// Shows whether the chat column is open, like the sidebar button does for the sidebar.
    func setChatVisible(_ visible: Bool) {
        chat.isOn = visible
        chat.setLabel(visible ? String(localized: "Hide Chat") : String(localized: "Show Chat"))
    }

    /// Shows the zoom level and the current page display's symbol.
    func setZoom(percent: Int, displaySymbol: String) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        zoomLevel.setTitle(formatter.string(from: NSNumber(value: Double(percent) / 100)) ?? "\(percent)%")
        if display.symbolName != displaySymbol {
            display.setSymbol(displaySymbol, label: String(localized: "Page Display"))
        }
    }

    func setReading(_ reading: Bool) {
        display.isHidden = !reading
        zoomLevel.isHidden = !reading
        zoomOut.isHidden = !reading
        zoomIn.isHidden = !reading
        chat.isHidden = !reading
        searchField.placeholderString = reading ? String(localized: "Find in document") : String(localized: "Search documents")
    }
}

/// An icon-only button for card headers. Flat on purpose: Liquid Glass belongs to window chrome (the sidebar
/// button), and these sit inside opaque cards. A 28 pt target with a rounded fill on hover and press, a
/// secondary-colored glyph that darkens on hover, and an "on" state for toggles such as the chat panel.
final class CardHeaderButton: NSButton {
    static let size: CGFloat = 28

    /// Shown as selected: a persistent fill and a full-strength glyph. Also reported to VoiceOver.
    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            setAccessibilityValue(isOn ? 1 : 0)
            needsDisplay = true
        }
    }

    /// A quieter glyph for secondary actions such as closing a card.
    var isSubtle = false {
        didSet { needsDisplay = true }
    }

    private var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }

    private(set) var symbolName: String?
    /// The text of a title button (the zoom level), redrawn in the current tint.
    private var plainTitle: String?

    private func setUp() {
        isBordered = false
        focusRingType = .default
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
    }

    /// A text button with the same look, such as the zoom level. At least 28 pt wide, padded to its title.
    convenience init(title: String, label: String) {
        self.init(frame: .zero)
        setUp()
        imagePosition = .noImage
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
            heightAnchor.constraint(equalToConstant: Self.size),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setLabel(label)
        setTitle(title)
    }

    func setTitle(_ text: String) {
        plainTitle = text
        needsDisplay = true
        applyTitle()
    }

    private func applyTitle() {
        guard let plainTitle else { return }
        let color = contentTintColor ?? .secondaryLabelColor
        // Called from updateLayer; only touch the title when it changes, or setting it would redraw again.
        if attributedTitle.string == plainTitle,
           attributedTitle.length > 0,
           attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == color { return }
        attributedTitle = NSAttributedString(string: plainTitle, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: color,
        ])
    }

    convenience init(symbol: String, label: String, pointSize: CGFloat = 15, isToggle: Bool = false) {
        self.init(frame: .zero)
        setUp()
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size),
        ])
        if isToggle {
            setAccessibilityRole(.checkBox)
            setAccessibilityValue(0)
        }
        setSymbol(symbol, label: label, pointSize: pointSize)
    }

    /// Changes the glyph and its name (tooltip and VoiceOver label) together.
    func setSymbol(_ symbol: String, label: String, pointSize: CGFloat = 15) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular, scale: .medium)
            .applying(.preferringHierarchical())
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(configuration)
        symbolName = symbol
        setLabel(label)
    }

    func setLabel(_ label: String) {
        toolTip = label
        setAccessibilityLabel(label)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        // A tint of the label color: light on dark cards, dark on light ones.
        let opacity: CGFloat = if !isEnabled {
            0
        } else if isHighlighted {
            0.16
        } else if isOn {
            0.12
        } else if isHovered {
            0.08
        } else {
            0
        }
        let fill: NSColor? = opacity > 0 ? NSColor.labelColor.withAlphaComponent(opacity) : nil
        // Resolve the dynamic color in this view's appearance; a bare `cgColor` can pick the light variant.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fill?.cgColor
        }
        contentTintColor = if !isEnabled {
            .tertiaryLabelColor
        } else if isOn || isHovered || isHighlighted {
            .labelColor
        } else {
            isSubtle ? .tertiaryLabelColor : .secondaryLabelColor
        }
        applyTitle()
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isHovered = false
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
