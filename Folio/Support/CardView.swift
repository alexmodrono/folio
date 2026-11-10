import AppKit

/// A rounded surface with a hairline border and a soft shadow, used for the reader and chat columns.
/// Add content to `body`, which clips it to the rounded shape.
final class CardView: NSView {
    let body = CardBody()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = .black.withAlphaComponent(0.06)
            shadow.shadowBlurRadius = 12
            shadow.shadowOffset = NSSize(width: 0, height: -8)
            return shadow
        }()

        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: topAnchor),
            body.bottomAnchor.constraint(equalTo: bottomAnchor),
            body.leadingAnchor.constraint(equalTo: leadingAnchor),
            body.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(
            roundedRect: bounds, cornerWidth: Theme.panelRadius, cornerHeight: Theme.panelRadius, transform: nil
        )
    }
}

/// The card's clipped surface. Colors are resolved in `updateLayer` so they follow the appearance.
final class CardBody: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Theme.panelRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    /// Draws the border in the accent color, for the chat card that receives the PDF's selections.
    var isHighlighted = false {
        didSet { if isHighlighted != oldValue { needsDisplay = true } }
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.borderColor = (isHighlighted ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }
}
