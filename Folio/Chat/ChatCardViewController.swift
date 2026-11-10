import AppKit
import SwiftUI

/// One chat card: a header with the conversation's title and buttons, over its session's web view.
final class ChatCardViewController: NSViewController {
    let session: ChatGPTSession

    private let card = CardView()
    private var body: CardBody { card.body }
    private let titleLabel = NSTextField(labelWithString: "ChatGPT")
    private let addButton = CardHeaderButton(symbol: "plus", label: "Add Chat")
    private let closeButton = CardHeaderButton(symbol: "xmark", label: "Hide Chat")
    private var titleObservation: NSKeyValueObservation?
    private var importView: NSView?

    init(session: ChatGPTSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let root = NSView()
        view = root
        card.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(card)

        let header = makeHeader()
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        let webView = session.webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(webView)
        body.addSubview(header)
        body.addSubview(separator)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: root.topAnchor),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            header.topAnchor.constraint(equalTo: body.topAnchor),
            header.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Theme.panelHeaderHeight),

            separator.topAnchor.constraint(equalTo: header.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: body.trailingAnchor),

            webView.topAnchor.constraint(equalTo: body.topAnchor, constant: Theme.panelHeaderHeight + 1),
            webView.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: body.trailingAnchor),
        ])

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.update() }
        }
        update()
    }

    /// Refreshes the title, the active border and the buttons that depend on how many cards there are.
    func update() {
        let cards = ChatGPTSession.all.count
        titleLabel.stringValue = session.title ?? "ChatGPT"
        body.isHighlighted = cards > 1 && session.isActive
        addButton.isEnabled = cards < ChatGPTSession.maxCards
        let closeLabel = cards > 1 ? "Close Chat" : "Hide Chat"
        closeButton.toolTip = closeLabel
        closeButton.setAccessibilityLabel(closeLabel)
    }

    // MARK: Header

    private func makeHeader() -> NSView {
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addButton.target = self
        addButton.action = #selector(addCard(_:))
        let newChat = CardHeaderButton(symbol: "square.and.pencil", label: "New Chat")
        newChat.target = self
        newChat.action = #selector(newChat(_:))
        let more = CardHeaderButton(symbol: "ellipsis", label: "More")
        more.target = self
        more.action = #selector(showMore(_:))
        closeButton.target = self
        closeButton.action = #selector(close(_:))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let stack = NSStackView(views: [titleLabel, spacer, addButton, newChat, more, closeButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Theme.Space.xs
        stack.edgeInsets = NSEdgeInsets(top: 0, left: Theme.Space.m, bottom: 0, right: Theme.Space.s)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Clicking the header picks this card for the PDF's selections, like clicking into the page does.
        let click = NSClickGestureRecognizer(target: self, action: #selector(focusCard(_:)))
        click.delaysPrimaryMouseButtonEvents = false
        stack.addGestureRecognizer(click)
        return stack
    }

    @objc private func focusCard(_ sender: Any?) {
        session.focus()
    }

    @objc private func addCard(_ sender: Any?) {
        let added = ChatGPTSession.add(below: session)
        added.focusComposer()
    }

    @objc private func newChat(_ sender: Any?) {
        session.focus()
        session.newChat()
    }

    @objc private func close(_ sender: Any?) {
        if ChatGPTSession.all.count > 1 {
            ChatGPTSession.remove(session)
        } else {
            NSApp.sendAction(#selector(MainWindowController.toggleChat(_:)), to: nil, from: self)
        }
    }

    @objc private func showMore(_ sender: NSButton) {
        session.focus()
        let menu = NSMenu()
        menu.addItem(withTitle: "Attach PDF", action: #selector(MainWindowController.attachDocument(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        if let panel = parent as? ChatPanelViewController {
            let layout = menu.addItem(withTitle: "Show Chats Side by Side", action: #selector(toggleSideBySide(_:)), keyEquivalent: "")
            layout.target = self
            layout.state = panel.isSideBySide ? .on : .off
        }
        let reload = menu.addItem(withTitle: "Reload", action: #selector(reloadChat(_:)), keyEquivalent: "")
        reload.target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + Theme.Space.xs), in: sender)
    }

    @objc private func toggleSideBySide(_ sender: Any?) {
        guard let panel = parent as? ChatPanelViewController else { return }
        panel.setSideBySide(!panel.isSideBySide)
    }

    @objc private func reloadChat(_ sender: Any?) {
        session.reload()
    }

    // MARK: Session import

    /// Covers the page with the offer to copy a browser's ChatGPT sign-in.
    func showSessionImport(_ sessions: [BrowserSession]) {
        _ = view
        guard importView == nil else { return }
        let content = SessionImportView(model: SessionImportModel(sessions: sessions), style: .panel) { [weak self] imported in
            if !imported { Preferences.declinedSessionImport = true }
            self?.importView?.removeFromSuperview()
            self?.importView = nil
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        let host = NSHostingView(rootView: content)
        // Without this the SwiftUI content's size feeds back into the window and grows it.
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false

        // Blurs chatgpt.com behind the offer; the page shows through but can't be read or clicked.
        let backdrop = NSVisualEffectView()
        backdrop.material = .popover
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(host)
        body.addSubview(backdrop, positioned: .above, relativeTo: session.webView)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: body.topAnchor, constant: Theme.panelHeaderHeight + 1),
            backdrop.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            host.topAnchor.constraint(equalTo: backdrop.topAnchor),
            host.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
        ])
        importView = backdrop
    }
}
