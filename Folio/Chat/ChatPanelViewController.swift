import AppKit

/// The inspector column: chat cards stacked top to bottom, or side by side, one per `ChatGPTSession`, with
/// draggable gaps between them. Web views are created the first time the column opens.
final class ChatPanelViewController: NSViewController, NSSplitViewDelegate {
    private static let minCardHeight: CGFloat = 200
    static let minCardWidth: CGFloat = 320

    private let stack = CardStackView()
    private var cards: [ObjectIdentifier: ChatCardViewController] = [:]
    private var checkedSessionImport = false
    private var needsEqualSizes = false
    private var isFixingLayout = false
    private var lastFixedSize = NSSize.zero

    override func loadView() {
        // The inspector column already has the system's sidebar glass behind it.
        let root = NSView()
        view = root
        stack.isVertical = Preferences.chatSideBySide
        stack.delegate = self
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let inset = Theme.Space.s
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: inset),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -inset),
            // The reader card already leaves a gap on this side.
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -inset),
        ])

        NotificationCenter.default.addObserver(
            forName: ChatGPTSession.didChangeCards, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncCards() }
        }
    }

    /// Opens the cards from last time (creating their web views) and shows them.
    func activate() {
        _ = view
        ChatGPTSession.restoreCards()
        syncCards()
        offerSessionImport()
    }

    /// Called once the column has finished appearing, when it has its real width: widens it for side-by-side
    /// cards and evens out cards that were restored or added while it was hidden.
    func didShow() {
        guard needsEqualSizes || hasSqueezedCard else { return }
        if stack.isVertical { widenForColumns() }
        equalizeSizes()
        lastFixedSize = stack.bounds.size
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard needsEqualSizes || (hasSqueezedCard && stack.bounds.size != lastFixedSize),
              !isFixingLayout, view.window != nil, view.bounds.width > Self.minCardWidth / 2
        else { return }
        // Cards restored while the column was collapsed get their sizes once it has some; doing it on the
        // next turn keeps the split views from resizing in the middle of this layout pass.
        isFixingLayout = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.stack.isVertical { self.widenForColumns() }
            self.equalizeSizes()
            // A window too narrow for every card's minimum would otherwise retry on every layout pass.
            self.lastFixedSize = self.stack.bounds.size
            self.isFixingLayout = false
        }
    }

    // MARK: Cards

    /// Matches the stack to `ChatGPTSession.all`. Cards are only ever inserted or removed, never reordered.
    private func syncCards() {
        guard isViewLoaded else { return }
        let sessions = ChatGPTSession.all
        let ids = Set(sessions.map(ObjectIdentifier.init))
        for (id, card) in cards where !ids.contains(id) {
            stack.removeArrangedSubview(card.view)
            card.view.removeFromSuperview()
            card.removeFromParent()
            cards[id] = nil
            needsEqualSizes = true
        }
        for (index, session) in sessions.enumerated() {
            let id = ObjectIdentifier(session)
            if cards[id] == nil {
                let card = ChatCardViewController(session: session)
                addChild(card)
                cards[id] = card
                stack.insertArrangedSubview(card.view, at: index)
                needsEqualSizes = true
            }
        }
        for card in cards.values { card.update() }
        if needsEqualSizes, stack.isVertical { widenForColumns() }
        if needsEqualSizes { equalizeSizes() }
    }

    var isSideBySide: Bool { stack.isVertical }

    #if DEBUG
    var layoutReport: String {
        let cards = stack.arrangedSubviews.map { "\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))" }
        return "vertical=\(stack.isVertical) stack=\(Int(stack.bounds.width))x\(Int(stack.bounds.height)) panel=\(Int(view.bounds.width)) "
            + "cards=[\(cards.joined(separator: " | "))] subviews=\(stack.subviews.count) needsEqual=\(needsEqualSizes) "
            + "lastFixed=\(Int(lastFixedSize.width))x\(Int(lastFixedSize.height)) "
            + "max=\((parent as? SplitViewController)?.chatItem.maximumThickness ?? -1)"
    }
    #endif

    /// Switches between rows and columns. Columns widen the chat area so each card keeps a usable width.
    func setSideBySide(_ sideBySide: Bool) {
        Preferences.chatSideBySide = sideBySide
        guard isViewLoaded, stack.isVertical != sideBySide else { return }
        stack.isVertical = sideBySide
        if sideBySide { widenForColumns() }
        needsEqualSizes = true
        stack.adjustSubviews()
        equalizeSizes()
    }

    private func widenForColumns() {
        let count = CGFloat(stack.arrangedSubviews.count)
        let wanted = count * Self.minCardWidth + stack.dividerThickness * max(0, count - 1) + Theme.Space.s
        (parent as? SplitViewController)?.makeRoomForChat(width: wanted)
    }

    /// Gives every card the same share of the stack after one is added or removed, or the layout changes.
    private func equalizeSizes() {
        stack.layoutSubtreeIfNeeded()
        let count = stack.arrangedSubviews.count
        let length = stack.isVertical ? stack.bounds.width : stack.bounds.height
        let available = length - stack.dividerThickness * CGFloat(count - 1)
        guard count > 0, available > 0 else { return }
        needsEqualSizes = false
        let size = available / CGFloat(count)
        for index in 0..<(count - 1) {
            stack.setPosition(size * CGFloat(index + 1) + stack.dividerThickness * CGFloat(index), ofDividerAt: index)
        }
    }

    /// A card below its minimum size, which happens when cards are restored or added while the column is
    /// collapsed or too narrow.
    private var hasSqueezedCard: Bool {
        stack.arrangedSubviews.count > 1 && stack.arrangedSubviews.contains { card in
            (stack.isVertical ? card.frame.width : card.frame.height) < minCardLength - 1
        }
    }

    private var minCardLength: CGFloat { stack.isVertical ? Self.minCardWidth : Self.minCardHeight }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let frame = splitView.arrangedSubviews[dividerIndex].frame
        return (splitView.isVertical ? frame.minX : frame.minY) + minCardLength
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let frame = splitView.arrangedSubviews[dividerIndex + 1].frame
        return (splitView.isVertical ? frame.maxX : frame.maxY) - minCardLength - splitView.dividerThickness
    }

    // MARK: Session import

    /// The first time the panel opens without a ChatGPT session, offers to copy one from a browser.
    private func offerSessionImport() {
        guard !checkedSessionImport, !Preferences.declinedSessionImport else { return }
        checkedSessionImport = true
        Task {
            guard await !ChatGPTSession.hasSignIn() else { return }
            let sessions = await Task.detached { BrowserSessions.find() }.value
            guard !sessions.isEmpty, let first = ChatGPTSession.all.first else { return }
            cards[ObjectIdentifier(first)]?.showSessionImport(sessions)
        }
    }
}

/// Stacks chat cards with a plain gap between them that still drags to resize.
private final class CardStackView: NSSplitView {
    override var dividerThickness: CGFloat { Theme.Space.s }
    override var dividerColor: NSColor { .clear }
}
