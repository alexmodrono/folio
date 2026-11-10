import AppKit

/// Swaps the content column between Home and the reader. Both sit in a card with `header` on top,
/// floating on the window backdrop.
final class ContentViewController: NSViewController {
    let header = ContentHeader()
    private(set) var current: NSViewController?
    private let card = CardView()
    /// Keeps the header clear of the sidebar button when the sidebar is collapsed and the button sits over the card.
    private var titlebarClearance: NSLayoutConstraint!
    /// The toolbar's sidebar button, set by the window controller.
    weak var sidebarButton: NSView?

    override func loadView() {
        let root = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(card)

        let body = card.body
        let separator = NSBox()
        separator.boxType = .separator
        for subview in [header, separator] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            body.addSubview(subview)
        }

        // The card runs up into the title bar. When the sidebar is collapsed the window controls sit over
        // its leading corner, so the header starts after them.
        let corner = root.layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))
        titlebarClearance = header.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor)
        let headerLeading = header.leadingAnchor.constraint(equalTo: body.leadingAnchor)
        headerLeading.priority = .defaultHigh
        let inset = Theme.Space.s
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: root.topAnchor, constant: inset),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -inset),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: inset),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -inset),

            header.topAnchor.constraint(equalTo: body.topAnchor),
            headerLeading,
            header.leadingAnchor.constraint(greaterThanOrEqualTo: corner.leadingAnchor),
            titlebarClearance,
            header.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Theme.panelHeaderHeight),

            separator.topAnchor.constraint(equalTo: header.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: body.trailingAnchor),
        ])
        view = root
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Runs on every frame of the sidebar animation, so the header follows the button.
        var clearance: CGFloat = 0
        if let button = sidebarButton, button.window === view.window, let superview = button.superview {
            let frame = view.convert(button.frame, from: superview)
            if frame.maxX > 0 { clearance = frame.maxX + Theme.Space.s }
        }
        if titlebarClearance.constant != clearance { titlebarClearance.constant = clearance }
    }

    func show(_ controller: NSViewController) {
        guard controller !== current else { return }
        _ = view
        current?.view.removeFromSuperview()
        current?.removeFromParent()
        addChild(controller)
        let child = controller.view
        let body = card.body
        child.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: body.topAnchor, constant: Theme.panelHeaderHeight + 1),
            child.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: body.trailingAnchor),
        ])
        current = controller
    }
}

/// The window's content: one sidebar-material backdrop with the split view on top. Every column is
/// transparent, so the sidebar and the space around the cards are the same view and can't drift apart.
final class RootViewController: NSViewController {
    let split: SplitViewController

    init(split: SplitViewController) {
        self.split = split
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let backdrop = NSVisualEffectView()
        backdrop.material = .sidebar
        backdrop.blendingMode = .behindWindow
        backdrop.state = .followsWindowActiveState
        view = backdrop

        addChild(split)
        let splitView = split.view
        splitView.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: backdrop.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
        ])
    }
}

/// Draws no divider line: the gaps between cards separate the columns. Dragging still resizes them.
final class CardSplitView: NSSplitView {
    override var dividerColor: NSColor { .clear }
}

/// Sidebar, content and chat columns. They are plain split items: sidebar and inspector items get their own
/// system glass on macOS 26, which never matches a backdrop drawn behind the other columns.
final class SplitViewController: NSSplitViewController {
    let sidebar: SidebarViewController
    let content = ContentViewController()
    let chat = ChatPanelViewController()
    private(set) var sidebarItem: NSSplitViewItem!
    private(set) var chatItem: NSSplitViewItem!

    init(sidebar: SidebarViewController) {
        self.sidebar = sidebar
        super.init(nibName: nil, bundle: nil)
        let splitView = CardSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        self.splitView = splitView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 340
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = .init(260)
        sidebarItem.titlebarSeparatorStyle = .none

        let contentItem = NSSplitViewItem(viewController: content)
        contentItem.minimumThickness = 420
        contentItem.titlebarSeparatorStyle = .none

        chatItem = NSSplitViewItem(viewController: chat)
        chatItem.minimumThickness = 340
        chatItem.maximumThickness = 720
        chatItem.preferredThicknessFraction = 0.34
        chatItem.canCollapse = true
        chatItem.holdingPriority = .init(260)
        chatItem.titlebarSeparatorStyle = .none
        chatItem.isCollapsed = true

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        addSplitViewItem(chatItem)
    }

    /// The system version only acts on sidebar-behavior items, which this controller doesn't use.
    override func toggleSidebar(_ sender: Any?) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            sidebarItem.animator().isCollapsed.toggle()
        }
    }

    var isChatVisible: Bool { !chatItem.isCollapsed }

    /// Widens the chat column toward `width` for side-by-side chat cards, as far as the reader's minimum allows.
    func makeRoomForChat(width: CGFloat) {
        chatItem.maximumThickness = max(chatItem.maximumThickness, width)
        guard !chatItem.isCollapsed, chat.view.frame.width < width,
              let index = splitViewItems.firstIndex(of: chatItem), index > 0 else { return }
        splitView.setPosition(splitView.bounds.width - width - splitView.dividerThickness, ofDividerAt: index - 1)
    }

    func setChatVisible(_ visible: Bool, animated: Bool) {
        guard chatItem.isCollapsed == visible else { return }
        if visible { chat.activate() }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                chatItem.animator().isCollapsed = !visible
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated { if visible { self?.chat.didShow() } }
            }
        } else {
            chatItem.isCollapsed = !visible
            if visible { chat.didShow() }
        }
    }
}
