import AppKit
import UniformTypeIdentifiers

/// The single library window. Owns navigation between Home, folders and documents, the toolbar, and menu commands.
extension NSToolbarItem.Identifier {
    /// Replaces the system `.toggleSidebar` item, which disables itself without a sidebar-behavior split item.
    static let sidebar = Self("sidebar")
}

final class MainWindowController: NSWindowController {
    enum Route: Equatable {
        case library(URL?)
        case document(URL)
        /// The page suggesting Findle, from the sidebar's Connect Moodle row.
        case findle
    }

    private let sidebar = SidebarViewController()
    private let split: SplitViewController
    private let homeModel = HomeModel()
    private lazy var home = HomeViewController(model: homeModel)
    private lazy var findlePage = FindleViewController()
    private var reader: ReaderViewController?
    private(set) var route: Route = .library(nil)
    private var header: ContentHeader { split.content.header }
    private var store: LibraryStore { .shared }

    init() {
        split = SplitViewController(sidebar: sidebar)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 760, height: 480)
        window.toolbarStyle = .unified
        // The title and controls live in the content card's header; the toolbar only holds the sidebar button.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentViewController = RootViewController(split: split)
        window.setContentSize(NSSize(width: 1240, height: 820))
        window.center()
        window.setFrameAutosaveName("FolioMainWindow")
        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: "FolioToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        configureHeader()

        sidebar.onSelect = { [weak self] selection in
            switch selection {
            case .home: self?.navigate(.library(nil))
            case .findle: self?.navigate(.findle)
            case .node(let url, let isFolder): self?.navigate(isFolder ? .library(url) : .document(url))
            }
        }
        homeModel.open = { [weak self] url in self?.openFromLibrary(url) }
        homeModel.importDocuments = { [weak self] in self?.importDocuments(nil) }
        homeModel.newFolder = { [weak self] in self?.newFolder(nil) }
        navigate(.library(nil))
        observeFindle()
    }

    /// Leaves the Findle page once Findle is connected or hidden, and leaves a Moodle folder that went away.
    private func observeFindle() {
        withObservationTracking {
            _ = Findle.shared.status
            _ = Findle.shared.isShown
            _ = store.moodleRoot
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                switch self.route {
                case .findle:
                    if Findle.shared.folderURL != nil || !Findle.shared.isShown { self.navigate(.library(nil)) }
                case .library(let url?) where !self.store.contains(url):
                    // Wait out the first scan of Findle's folder; after that, a folder that's gone is gone.
                    let scanning = Findle.shared.folderURL != nil && self.store.moodleRoot == nil
                    if !scanning, self.store.node(at: url) == nil { self.navigate(.library(nil)) }
                default:
                    break
                }
                self.observeFindle()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Navigation

    /// Opens a PDF from anywhere on disk.
    func open(_ url: URL) {
        navigate(.document(url.standardizedFileURL))
        showWindow(nil)
    }

    private func openFromLibrary(_ url: URL) {
        let isFolder = store.node(at: url)?.isFolder ?? false
        navigate(isFolder ? .library(url) : .document(url))
    }

    private func navigate(_ newRoute: Route) {
        if case .document = newRoute, newRoute == route, reader != nil { return }
        reader?.saveState()

        switch newRoute {
        case .findle:
            reader = nil
            split.content.show(findlePage)
            split.setChatVisible(false, animated: false)
            ChatGPTSession.document = nil
            sidebar.revealFindle()
        case .library(let folder):
            reader = nil
            homeModel.folderURL = folder
            homeModel.query = ""
            split.content.show(home)
            split.setChatVisible(false, animated: false)
            ChatGPTSession.document = nil
            sidebar.reveal(folder, isHome: folder == nil)
        case .document(let url):
            let controller = ReaderViewController(url: url)
            controller.onStateChange = { [weak self] in
                self?.updateHeader()
                self?.updateTitle()
            }
            controller.onShowQuestion = { [weak self] question in
                guard let self else { return }
                if !split.isChatVisible {
                    showChat()
                    Preferences.chatVisible = true
                }
                ChatGPTSession.reveal(question)
            }
            reader = controller
            split.content.show(controller)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            sidebar.reveal(store.node(at: url) != nil ? url : nil, isHome: false)
            if Preferences.chatVisible { showChat() }
            ChatGPTSession.document = url
        }
        route = newRoute
        header.searchField.stringValue = ""
        updateHeader()
        updateTitle()
    }

    private var isReading: Bool {
        if case .document = route, reader?.hasDocument == true { return true }
        return false
    }

    /// The reader, while a document is open and loaded.
    var activeReader: ReaderViewController? { isReading ? reader : nil }

    private var currentDocumentURL: URL? {
        if case .document(let url) = route { return url }
        return nil
    }

    /// The folder on screen, or the open document's folder.
    private var currentFolderURL: URL? {
        switch route {
        case .library(let url): return url
        case .document(let url): return store.node(at: url) != nil ? url.deletingLastPathComponent() : nil
        case .findle: return nil
        }
    }

    /// The folder new files go into. Nil means the library root; Findle's folders take nothing.
    private var targetFolderURL: URL? {
        guard let url = currentFolderURL, !store.isReadOnly(url) else { return nil }
        return url
    }

    /// Whether the window shows one of Findle's folders, where New Folder and Import don't apply.
    private var isInMoodleFolder: Bool {
        if case .library(let url?) = route { return store.isReadOnly(url) }
        return false
    }

    private func updateTitle() {
        guard let window else { return }
        switch route {
        case .library(nil):
            window.title = String(localized: "Home")
            window.representedURL = nil
            header.subtitleLabel.stringValue = ""
        case .library(let url?):
            window.title = url.lastPathComponent
            window.representedURL = nil
            header.subtitleLabel.stringValue = ""
        case .document(let url):
            window.title = url.deletingPathExtension().lastPathComponent
            window.representedURL = url
            header.subtitleLabel.stringValue = reader?.statusText ?? ""
        case .findle:
            window.title = "Moodle"
            window.representedURL = nil
            header.subtitleLabel.stringValue = ""
        }
        header.titleLabel.stringValue = window.title
        header.subtitleLabel.isHidden = header.subtitleLabel.stringValue.isEmpty
    }

    private func updateHeader() {
        header.setReading(isReading)
        header.setChatVisible(split.isChatVisible)
        header.searchField.isHidden = route == .findle
    }

    // MARK: Chat

    private func showChat() {
        split.setChatVisible(true, animated: true)
        ChatGPTSession.document = currentDocumentURL
        updateHeader()
    }

    @objc func toggleChat(_ sender: Any?) {
        guard isReading else { return }
        if split.isChatVisible {
            split.setChatVisible(false, animated: true)
            Preferences.chatVisible = false
            window?.makeFirstResponder(reader?.pdfView)
        } else {
            showChat()
            Preferences.chatVisible = true
            ChatGPTSession.active.focusComposer()
        }
        updateHeader()
    }

    @objc func askAboutSelection(_ sender: Any?) {
        guard let reader, let url = currentDocumentURL, let selection = reader.selectionForChat() else {
            NSSound.beep()
            return
        }
        if !split.isChatVisible {
            showChat()
            Preferences.chatVisible = true
        }
        Task {
            let ok = await ChatGPTSession.active.ask(
                about: selection.text, location: selection.location, in: url, anchor: selection.anchor
            )
            if !ok { NSSound.beep() }
        }
    }

    /// Asks about a whole page: the page under the pointer from the context menu, or the current page.
    @objc func askAboutPage(_ sender: Any?) {
        let index = (sender as? NSMenuItem)?.representedObject as? Int
        guard let reader, let url = currentDocumentURL, let page = reader.pageForChat(index) else {
            NSSound.beep()
            return
        }
        if !split.isChatVisible {
            showChat()
            Preferences.chatVisible = true
        }
        Task {
            let ok = await ChatGPTSession.active.ask(
                aboutPage: page.text, location: page.location, in: url, anchor: page.anchor, image: page.image
            )
            if !ok { NSSound.beep() }
        }
    }

    @objc func toggleQuestionBubbles(_ sender: Any?) {
        Preferences.showQuestionBubbles.toggle()
    }

    @objc func attachDocument(_ sender: Any?) {
        guard let url = currentDocumentURL else { return }
        if !split.isChatVisible { showChat() }
        Task {
            let ok = await ChatGPTSession.active.attach(url)
            if !ok { NSSound.beep() }
        }
    }

    @objc func newChat(_ sender: Any?) {
        guard isReading else { return }
        if !split.isChatVisible { showChat() }
        ChatGPTSession.active.newChat()
    }

    // MARK: Library commands

    @objc func importDocuments(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Import", comment: "Import panel button")
        let folder = targetFolderURL
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.store.importFiles(panel.urls, into: folder)
        }
    }

    @objc func newFolder(_ sender: Any?) {
        guard let url = store.createFolder(in: targetFolderURL) else { return }
        sidebar.beginRename(url)
    }

    @objc func toggleFavorite(_ sender: Any?) {
        guard let url = currentDocumentURL, store.node(at: url) != nil else { return }
        store.toggleFavorite(url)
    }

    @objc func showInFinder(_ sender: Any?) {
        guard let url = currentDocumentURL ?? currentFolderURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Reader commands

    @objc func toggleSidebar(_ sender: Any?) { split.toggleSidebar(sender) }
    @objc func toggleThumbnails(_ sender: Any?) { reader?.toggleThumbnails() }
    @objc func setDisplayMode(_ sender: NSMenuItem) { reader?.setDisplayMode(sender.tag) }
    @objc func readerZoomIn(_ sender: Any?) { reader?.zoomIn() }
    @objc func readerZoomOut(_ sender: Any?) { reader?.zoomOut() }
    @objc func readerActualSize(_ sender: Any?) { reader?.actualSize() }
    @objc func readerZoomToFit(_ sender: Any?) { reader?.zoomToFit() }
    @objc func readerPreviousPage(_ sender: Any?) { reader?.previousPage() }
    @objc func readerNextPage(_ sender: Any?) { reader?.nextPage() }
    @objc func readerGoToPage(_ sender: Any?) { reader?.goToPage() }
    @objc func printPDF(_ sender: Any?) { reader?.printDocument() }

    @objc func focusSearch(_ sender: Any?) {
        window?.makeFirstResponder(header.searchField)
    }

    @objc func findNextMatch(_ sender: Any?) {
        guard let query = Optional(header.searchField.stringValue), !query.isEmpty else { return focusSearch(sender) }
        reader?.find(query)
    }

    @objc func findPreviousMatch(_ sender: Any?) {
        guard let query = Optional(header.searchField.stringValue), !query.isEmpty else { return focusSearch(sender) }
        reader?.find(query, backwards: true)
    }

    @objc private func searchFieldAction(_ sender: NSSearchField) {
        guard isReading else { return }
        let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
        reader?.find(sender.stringValue, backwards: backwards)
    }

    private func configureHeader() {
        let field = header.searchField
        field.delegate = self
        field.target = self
        field.action = #selector(searchFieldAction(_:))
        header.zoomOut.target = self
        header.zoomOut.action = #selector(readerZoomOut(_:))
        header.zoomIn.target = self
        header.zoomIn.action = #selector(readerZoomIn(_:))
        header.chat.target = self
        header.chat.action = #selector(toggleChat(_:))
    }
}

// MARK: - Window

extension MainWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        reader?.saveState()
    }

    /// In full screen the toolbar becomes an opaque bar over the top of the content, which hides the card
    /// header. It only holds the sidebar button, so hide it until the pointer reaches the top edge.
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions {
        proposedOptions.union([.autoHideToolbar, .autoHideMenuBar, .fullScreen])
    }
}

// MARK: - Menu validation

extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleChat(_:)):
            item.title = split.isChatVisible ? String(localized: "Hide Chat") : String(localized: "Show Chat")
            return isReading
        case #selector(askAboutSelection(_:)):
            return isReading && reader?.hasSelection == true
        case #selector(askAboutPage(_:)):
            return isReading
        case #selector(toggleQuestionBubbles(_:)):
            item.state = Preferences.showQuestionBubbles ? .on : .off
            return isReading
        case #selector(toggleThumbnails(_:)):
            item.state = reader?.showsThumbnails == true ? .on : .off
            return isReading
        case #selector(setDisplayMode(_:)):
            item.state = reader?.displayModeTag == item.tag ? .on : .off
            return isReading
        case #selector(toggleFavorite(_:)):
            guard let url = currentDocumentURL, store.node(at: url) != nil else { return false }
            item.title = store.isFavorite(url) ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites")
            return true
        case #selector(attachDocument(_:)), #selector(newChat(_:)),
             #selector(readerZoomIn(_:)), #selector(readerZoomOut(_:)), #selector(readerActualSize(_:)),
             #selector(readerZoomToFit(_:)), #selector(readerPreviousPage(_:)), #selector(readerNextPage(_:)),
             #selector(readerGoToPage(_:)), #selector(printPDF(_:)),
             #selector(findNextMatch(_:)), #selector(findPreviousMatch(_:)):
            return isReading
        case #selector(newFolder(_:)), #selector(importDocuments(_:)):
            return !isInMoodleFolder
        case #selector(toggleSidebar(_:)):
            item.title = split.splitViewItems.first?.isCollapsed == true ? String(localized: "Show Sidebar") : String(localized: "Hide Sidebar")
            return true
        default:
            return true
        }
    }
}

// MARK: - Search field

extension MainWindowController: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField, field === header.searchField else { return }
        if isReading {
            if field.stringValue.isEmpty { reader?.clearFind() }
        } else {
            homeModel.query = field.stringValue
        }
    }
}

// MARK: - Toolbar

extension MainWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebar]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard identifier == .sidebar else { return nil }
        let image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: String(localized: "Sidebar"))!
        let button = NSButton(image: image, target: self, action: #selector(toggleSidebar(_:)))
        button.bezelStyle = .toolbar
        button.toolTip = String(localized: "Sidebar")
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = button
        item.label = String(localized: "Sidebar")
        // The content header measures this button to stay clear of it when the sidebar is collapsed.
        split.content.sidebarButton = button
        return item
    }
}
