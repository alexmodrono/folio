import AppKit

/// Source-list sidebar: Home, the library tree under "My documents", Findle's courses under "Moodle"
/// (or one row suggesting Findle), and Settings at the bottom.
final class SidebarViewController: NSViewController {
    enum Selection {
        case home
        case findle
        case node(URL, isFolder: Bool)
    }

    var onSelect: ((Selection) -> Void)?

    private final class Marker {}
    private let homeMarker = Marker()
    private let headerMarker = Marker()
    private let moodleMarker = Marker()
    /// The Connect Moodle row, shown under "Moodle" until Findle is set up.
    private let findleMarker = Marker()

    private enum Revealed {
        case home, findle
        case url(URL?)
    }

    private let outline = NSOutlineView()
    private var suppressSelection = false
    private var revealed = Revealed.home
    private var expanded = Set(Preferences.expandedFolders)
    private var store: LibraryStore { .shared }
    private var findle: Findle { .shared }

    private var topItems: [AnyObject] {
        findle.isShown ? [homeMarker, headerMarker, moodleMarker] : [homeMarker, headerMarker]
    }

    /// Findle's courses once it's connected; the Connect Moodle row before that.
    private var moodleItems: [AnyObject] {
        if findle.folderURL != nil { return store.moodleRoot?.children ?? [] }
        return [findleMarker]
    }

    private static let cellID = NSUserInterfaceItemIdentifier("cell")
    private static let headerID = NSUserInterfaceItemIdentifier("header")
    private static let moodleHeaderID = NSUserInterfaceItemIdentifier("moodleHeader")

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.isEditable = true
        // Keep the column as wide as the visible area, so a classic scroller narrows the rows instead of covering them.
        column.resizingMask = .autoresizingMask
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.floatsGroupRows = false
        outline.allowsEmptySelection = true
        outline.autoresizesOutlineColumn = true
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClicked(_:))
        outline.registerForDraggedTypes([.fileURL])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)

        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let settings = NSButton(
            title: "Settings",
            image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)!,
            target: nil,
            action: #selector(AppDelegate.showSettings(_:))
        )
        settings.isBordered = false
        settings.imagePosition = .imageLeading
        settings.imageHugsTitle = true
        settings.contentTintColor = .labelColor
        settings.font = .systemFont(ofSize: NSFont.systemFontSize)
        settings.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(scroll)
        container.addSubview(settings)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: settings.topAnchor, constant: -8),
            settings.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            settings.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadTree()
        observeStore()
    }

    // MARK: Public

    /// Selects the row for `url` without notifying `onSelect`. The choice is kept and reapplied after reloads.
    func reveal(_ url: URL?, isHome: Bool) {
        revealed = isHome ? .home : .url(url)
        applyReveal()
    }

    func revealFindle() {
        revealed = .findle
        applyReveal()
    }

    private func applyReveal() {
        guard isViewLoaded else { return }
        suppressSelection = true
        defer { suppressSelection = false }
        let marker: Marker? = switch revealed {
        case .home: homeMarker
        case .findle: findleMarker
        case .url: nil
        }
        if let marker {
            let row = outline.row(forItem: marker)
            if row >= 0 { outline.selectRowIndexes([row], byExtendingSelection: false) } else { outline.deselectAll(nil) }
            return
        }
        guard case .url(let url?) = revealed, let node = store.node(at: url) else {
            outline.deselectAll(nil)
            return
        }
        expandAncestors(of: node)
        let row = outline.row(forItem: node)
        if row >= 0 {
            outline.selectRowIndexes([row], byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        } else {
            outline.deselectAll(nil)
        }
    }

    func beginRename(_ url: URL) {
        reveal(url, isHome: false)
        guard let node = store.node(at: url) else { return }
        let row = outline.row(forItem: node)
        if row >= 0 { outline.editColumn(0, row: row, with: nil, select: true) }
    }

    // MARK: Store

    private func observeStore() {
        withObservationTracking {
            _ = store.root
            _ = store.moodleRoot
            _ = findle.status
            _ = findle.isShown
            _ = findle.appURL
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.reloadTree()
                self?.observeStore()
            }
        }
    }

    private func reloadTree() {
        suppressSelection = true
        outline.reloadData()
        outline.expandItem(headerMarker)
        expandSaved(store.root.children)
        if findle.isShown {
            outline.expandItem(moodleMarker)
            expandSaved(store.moodleRoot?.children ?? [])
        }
        suppressSelection = false
        applyReveal()
    }

    private func expandSaved(_ nodes: [LibraryNode]) {
        for node in nodes where node.isFolder && expanded.contains(node.id) {
            outline.expandItem(node)
            expandSaved(node.children)
        }
    }

    private func expandAncestors(of node: LibraryNode) {
        var chain: [LibraryNode] = []
        var current = node.parent
        while let folder = current, folder.parent != nil {
            chain.insert(folder, at: 0)
            current = folder.parent
        }
        chain.forEach { outline.expandItem($0) }
    }

    private func persistExpansion() {
        Preferences.expandedFolders = Array(expanded)
    }

    // MARK: Actions

    @objc private func doubleClicked(_ sender: Any?) {
        guard let node = outline.item(atRow: outline.clickedRow) as? LibraryNode, node.isFolder else { return }
        if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
    }

    private var clickedNode: LibraryNode? {
        outline.clickedRow >= 0 ? outline.item(atRow: outline.clickedRow) as? LibraryNode : nil
    }

    @objc private func openClicked(_ sender: Any?) {
        guard let node = clickedNode else { return }
        onSelect?(.node(node.url, isFolder: node.isFolder))
    }

    @objc private func showClickedInFinder(_ sender: Any?) {
        guard let node = clickedNode else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    @objc private func toggleClickedFavorite(_ sender: Any?) {
        guard let node = clickedNode else { return }
        store.toggleFavorite(node.url)
    }

    @objc private func renameClicked(_ sender: Any?) {
        guard outline.clickedRow >= 0 else { return }
        outline.editColumn(0, row: outline.clickedRow, with: nil, select: true)
    }

    @objc private func newFolderInClicked(_ sender: Any?) {
        guard let node = clickedNode, node.isFolder else { return }
        expanded.insert(node.id)
        persistExpansion()
        if let url = store.createFolder(in: node.url) { beginRename(url) }
    }

    @objc private func trashClicked(_ sender: Any?) {
        guard let node = clickedNode else { return }
        store.trash([node.url])
    }

    @objc private func copyClickedToLibrary(_ sender: Any?) {
        guard let node = clickedNode else { return }
        store.copyToLibrary([node.url], into: nil)
    }

    @objc private func downloadClicked(_ sender: Any?) {
        guard let node = clickedNode else { return }
        store.download(node.isFolder ? node.allDocuments.filter(\.isPlaceholder).map(\.url) : [node.url])
    }

    @objc private func syncMoodle(_ sender: Any?) {
        findle.sync()
    }

    // MARK: Cells

    private func makeCell(symbol: String, title: String, editable: Bool) -> NSTableCellView {
        let cell: NSTableCellView
        if let reused = outline.makeView(withIdentifier: Self.cellID, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = Self.cellID
            let image = NSImageView()
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingTail
            text.cell?.truncatesLastVisibleLine = true
            text.delegate = self
            for view in [image, text] as [NSView] {
                view.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(view)
            }
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 20),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            cell.imageView = image
            cell.textField = text
        }
        cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        cell.textField?.stringValue = title
        cell.textField?.isEditable = editable
        return cell
    }

    private func makeHeader() -> NSTableCellView {
        if let reused = outline.makeView(withIdentifier: Self.headerID, owner: self) as? NSTableCellView {
            return reused
        }
        let newFolder = Self.headerButton(symbol: "folder.badge.plus", help: "New Folder", action: #selector(MainWindowController.newFolder(_:)))
        let add = Self.headerButton(symbol: "plus", help: "Import PDFs", action: #selector(MainWindowController.importDocuments(_:)))
        return makeHeader(id: Self.headerID, title: "My documents", buttons: [newFolder, add])
    }

    /// The Moodle header, with a sync button once Findle is connected.
    private func makeMoodleHeader() -> NSTableCellView {
        let cell: NSTableCellView
        if let reused = outline.makeView(withIdentifier: Self.moodleHeaderID, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            let sync = Self.headerButton(symbol: "arrow.triangle.2.circlepath", help: "Sync with Moodle", action: #selector(syncMoodle(_:)))
            sync.target = self
            cell = makeHeader(id: Self.moodleHeaderID, title: "Moodle", buttons: [sync])
        }
        let canSync = findle.folderURL != nil && findle.appURL != nil
        cell.subviews.compactMap { $0 as? NSStackView }.first?.isHidden = !canSync
        return cell
    }

    private func makeHeader(id: NSUserInterfaceItemIdentifier, title text: String, buttons views: [NSView]) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let title = NSTextField(labelWithString: text)
        cell.textField = title

        let buttons = NSStackView(views: views)
        buttons.spacing = 8

        for view in [title, buttons] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            buttons.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            buttons.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -8),
        ])
        return cell
    }

    private static func headerButton(symbol: String, help: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: help)!, target: nil, action: action)
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = help
        return button
    }
}

// MARK: - Data source

extension SidebarViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item else { return topItems.count }
        if (item as AnyObject) === headerMarker { return store.root.children.count }
        if (item as AnyObject) === moodleMarker { return moodleItems.count }
        return (item as? LibraryNode)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item else { return topItems[index] }
        if (item as AnyObject) === headerMarker { return store.root.children[index] }
        if (item as AnyObject) === moodleMarker { return moodleItems[index] }
        return (item as! LibraryNode).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if (item as AnyObject) === headerMarker || (item as AnyObject) === moodleMarker { return true }
        guard let node = item as? LibraryNode else { return false }
        return node.isFolder && !node.children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        (item as? LibraryNode)?.url as NSURL?
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard let (target, _) = dropTarget(for: item) else { return [] }
        outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
        let urls = droppedURLs(info)
        let isLocal = (info.draggingSource as? NSOutlineView) === outline
        // Findle's files are copied out, never moved.
        if isLocal { return urls.contains(where: store.isReadOnly) ? .copy : .move }
        return urls.contains { $0.pathExtension.lowercased() == "pdf" } ? .copy : []
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let (_, folder) = dropTarget(for: item) else { return false }
        let urls = droppedURLs(info)
        if (info.draggingSource as? NSOutlineView) === outline {
            store.move(urls, to: folder)
        } else {
            store.importFiles(urls, into: folder == store.rootURL ? nil : folder)
        }
        return true
    }

    /// The outline item to highlight and the folder that receives a drop on `item`. Findle's rows take no drops.
    private func dropTarget(for item: Any?) -> (Any, URL)? {
        if (item as AnyObject) === moodleMarker || (item as AnyObject) === findleMarker { return nil }
        if let node = item as? LibraryNode, node.isReadOnly { return nil }
        if item == nil || (item as AnyObject) === headerMarker || (item as AnyObject) === homeMarker {
            return (headerMarker, store.rootURL)
        }
        guard let node = item as? LibraryNode else { return nil }
        if node.isFolder { return (node, node.url) }
        if let parent = node.parent, parent.parent != nil { return (parent, parent.url) }
        return (headerMarker, store.rootURL)
    }

    private func droppedURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}

// MARK: - Delegate

extension SidebarViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as AnyObject) === headerMarker || (item as AnyObject) === moodleMarker
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as AnyObject) !== headerMarker && (item as AnyObject) !== moodleMarker
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if (item as AnyObject) === homeMarker { return makeCell(symbol: "house", title: "Home", editable: false) }
        if (item as AnyObject) === headerMarker { return makeHeader() }
        if (item as AnyObject) === moodleMarker { return makeMoodleHeader() }
        if (item as AnyObject) === findleMarker { return makeCell(symbol: "graduationcap", title: "Connect Moodle", editable: false) }
        guard let node = item as? LibraryNode else { return nil }
        return makeCell(symbol: node.isFolder ? "folder" : "doc.text", title: node.name, editable: !node.isReadOnly)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelection, outline.selectedRow >= 0 else { return }
        let item = outline.item(atRow: outline.selectedRow)
        if (item as AnyObject) === homeMarker {
            revealed = .home
            onSelect?(.home)
        } else if (item as AnyObject) === findleMarker {
            revealed = .findle
            onSelect?(.findle)
        } else if let node = item as? LibraryNode {
            revealed = .url(node.url)
            onSelect?(.node(node.url, isFolder: node.isFolder))
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !suppressSelection, let node = notification.userInfo?["NSObject"] as? LibraryNode else { return }
        expanded.insert(node.id)
        persistExpansion()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !suppressSelection, let node = notification.userInfo?["NSObject"] as? LibraryNode else { return }
        expanded.remove(node.id)
        persistExpansion()
    }
}

// MARK: - Rename

extension SidebarViewController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let row = outline.row(for: field)
        guard row >= 0, let node = outline.item(atRow: row) as? LibraryNode else { return }
        let newName = field.stringValue
        guard newName != node.name else { return }
        do {
            let renamed = try store.rename(node.url, to: newName)
            if node.isFolder, expanded.remove(node.id) != nil {
                expanded.insert(renamed.standardizedFileURL.path)
                persistExpansion()
            }
            onSelect?(.node(renamed, isFolder: node.isFolder))
        } catch {
            field.stringValue = node.name
            NSSound.beep()
        }
    }
}

// MARK: - Context menu

extension SidebarViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let node = clickedNode else {
            // Empty space or the "My documents" header: the same two commands as the header's buttons.
            let item = outline.clickedRow >= 0 ? outline.item(atRow: outline.clickedRow) as AnyObject? : nil
            guard item == nil || item === headerMarker else { return }
            menu.addItem(withTitle: "Import PDFs…", action: #selector(MainWindowController.importDocuments(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "New Folder", action: #selector(MainWindowController.newFolder(_:)), keyEquivalent: "")
            return
        }
        menu.addItem(withTitle: "Open", action: #selector(openClicked(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show in Finder", action: #selector(showClickedInFinder(_:)), keyEquivalent: "").target = self
        if node.isReadOnly {
            if !node.isFolder {
                let title = store.isFavorite(node.url) ? "Remove from Favorites" : "Add to Favorites"
                menu.addItem(withTitle: title, action: #selector(toggleClickedFavorite(_:)), keyEquivalent: "").target = self
            }
            menu.addItem(.separator())
            if node.isFolder ? node.allDocuments.contains(where: \.isPlaceholder) : node.isPlaceholder {
                menu.addItem(withTitle: "Download", action: #selector(downloadClicked(_:)), keyEquivalent: "").target = self
            }
            if !node.isFolder {
                menu.addItem(withTitle: "Copy to My Documents", action: #selector(copyClickedToLibrary(_:)), keyEquivalent: "").target = self
            }
            if menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
            return
        }
        if node.isFolder {
            menu.addItem(withTitle: "New Folder", action: #selector(newFolderInClicked(_:)), keyEquivalent: "").target = self
        } else {
            let title = store.isFavorite(node.url) ? "Remove from Favorites" : "Add to Favorites"
            menu.addItem(withTitle: title, action: #selector(toggleClickedFavorite(_:)), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "Rename", action: #selector(renameClicked(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Move to Trash", action: #selector(trashClicked(_:)), keyEquivalent: "").target = self
    }
}
