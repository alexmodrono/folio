import AppKit
import WebKit

/// One chatgpt.com web view per chat card. It edits the composer through `chatgpt-bridge.js`: it attaches
/// files and adds selections the way a person would, and never sends a message on its own.
final class ChatGPTSession: NSObject {
    static let home = URL(string: "https://chatgpt.com/")!
    static let maxCards = 4

    /// One session per chat card, top to bottom. Web views are created only when the chat panel opens.
    private(set) static var all: [ChatGPTSession] = []
    private static weak var focused: ChatGPTSession?

    /// Posted when cards are added, removed or focused.
    static let didChangeCards = Notification.Name("ChatGPTSession.didChangeCards")
    /// Posted (with the session as object) when the bridge finds chatgpt.com missing parts Folio needs, or back.
    static let didChangeHealth = Notification.Name("ChatGPTSession.didChangeHealth")

    static var isLoaded: Bool { !all.isEmpty }

    /// Where the PDF and its selections go: the card last clicked or typed in. Creates the first card if needed.
    static var active: ChatGPTSession {
        if let focused, all.contains(focused) { return focused }
        if let first = all.first { return first }
        return add()
    }

    /// The PDF open in the reader. Every card's new chats get it attached when auto-attach is on.
    static var document: URL? {
        didSet {
            guard document != oldValue else { return }
            for session in all { session.currentDocument = document }
        }
    }

    /// Opens the cards from last time, or one new card.
    static func restoreCards() {
        guard all.isEmpty else { return }
        let paths = Array(Preferences.chatCards.prefix(maxCards))
        for path in paths.isEmpty ? ["/"] : paths {
            all.append(ChatGPTSession(path: path))
        }
        focused = all.first
        saveCards()
        NotificationCenter.default.post(name: didChangeCards, object: nil)
    }

    /// Adds a card below `anchor` (or at the bottom) and makes it active.
    @discardableResult
    static func add(below anchor: ChatGPTSession? = nil) -> ChatGPTSession {
        let session = ChatGPTSession(path: "/")
        if let anchor, let index = all.firstIndex(of: anchor) {
            all.insert(session, at: index + 1)
        } else {
            all.append(session)
        }
        focused = session
        saveCards()
        NotificationCenter.default.post(name: didChangeCards, object: nil)
        return session
    }

    static func remove(_ session: ChatGPTSession) {
        guard let index = all.firstIndex(of: session) else { return }
        all.remove(at: index)
        session.close()
        if focused === session || focused == nil { focused = all.isEmpty ? nil : all[max(0, index - 1)] }
        saveCards()
        NotificationCenter.default.post(name: didChangeCards, object: nil)
    }

    private static func saveCards() {
        Preferences.chatCards = all.map { session in
            let path = session.webView.url?.path ?? session.initialPath
            return path.isEmpty ? "/" : path
        }
    }

    var isActive: Bool { Self.focused.map { $0 === self } ?? (Self.all.first === self) }

    /// Makes this the card that receives the PDF and its selections.
    func focus() {
        guard Self.focused !== self else { return }
        Self.focused = self
        NotificationCenter.default.post(name: Self.didChangeCards, object: nil)
    }

    /// The conversation's title, or nil for a new chat.
    var title: String? {
        let title = (webView.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty || title == "ChatGPT" ? nil : title
    }

    /// Text selected in this card outside the composer, as reported by the bridge.
    private(set) var selectedText = ""

    /// The parts of chatgpt.com the bridge couldn't find (composer, composerBody, sendButton). Empty when
    /// everything Folio needs is there, or the page hasn't been checked yet.
    private(set) var missingParts: [String] = [] {
        didSet {
            guard missingParts != oldValue else { return }
            if !missingParts.isEmpty { NSLog("Folio: chatgpt.com is missing \(missingParts.joined(separator: ", "))") }
            NotificationCenter.default.post(name: Self.didChangeHealth, object: self)
        }
    }

    let webView: ChatWebView
    private let initialPath: String

    /// The PDF open in the reader. New chats get it attached when auto-attach is on.
    var currentDocument: URL? {
        didSet {
            guard currentDocument != oldValue else { return }
            scheduleSync()
        }
    }

    private static let world = WKContentWorld.world(name: "Folio")

    /// The SF Symbols the bridge's chips use, as PNG data URLs. The bridge uses them as masks, so only their
    /// shape matters and they take the page's text color.
    private static let iconScript: String = {
        let symbols = ["file": "doc.text", "chat": "text.bubble"]
        var urls: [String: String] = [:]
        for (key, name) in symbols {
            let configuration = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { continue }
            let size = image.size
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) else { continue }
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            if let png = rep.representation(using: .png, properties: [:]) {
                urls[key] = "data:image/png;base64," + png.base64EncodedString()
            }
        }
        let json = (try? JSONSerialization.data(withJSONObject: urls)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "if (/(^|\\.)chatgpt\\.com$/.test(location.hostname)) window.__folioIcons = \(json);"
    }()
    /// The labels the bridge shows on chatgpt.com, in the app's language. The bridge fills in `{n}` (a number),
    /// `{doc}` (a document name) and `{title}` (a chat title), and falls back to English for missing keys.
    private static let stringsScript: String = {
        let strings: [String: String] = [
            "page": String(localized: "Page {n}", comment: "Chip label for one whole page; {n} is the page number"),
            "onePage": String(localized: "1 page", comment: "Chip label for one whole page without a number"),
            "pages": String(localized: "{n} pages", comment: "Chip label; {n} is 2 or more"),
            "oneSelection": String(localized: "1 selection", comment: "Chip label"),
            "selections": String(localized: "{n} selections", comment: "Chip label; {n} is 2 or more"),
            "references": String(localized: "{n} references", comment: "Chip label for selections and pages together; {n} is 2 or more"),
            "removeSelection": String(localized: "Remove selection"),
            "removeSelections": String(localized: "Remove selections"),
            "fromPage": String(localized: "From {doc}, page {n}", comment: "Quote source; {doc} is a document name"),
            "fromPages": String(localized: "From {doc}, pages {n}", comment: "Quote source; {n} is a page range like 4–5"),
            "fromWholePage": String(localized: "From {doc}, page {n} (whole page)", comment: "Quote source for a whole page"),
            "fromChat": String(localized: "From the chat “{title}”", comment: "Quote source; {title} is a chat title"),
            "fromAnotherChat": String(localized: "From another chat", comment: "Quote source"),
        ]
        let json = (try? JSONSerialization.data(withJSONObject: strings)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "if (/(^|\\.)chatgpt\\.com$/.test(location.hostname)) window.__folioStrings = \(json);"
    }()

    /// Larger files skip the JavaScript bridge and go through a native paste.
    private static let maxBridgeBytes = 30_000_000

    private static let authHosts = [
        "auth.openai.com", "auth0.openai.com", "accounts.google.com", "appleid.apple.com",
        "login.microsoftonline.com", "login.live.com",
    ]

    /// What the current chat has, attached to the composer or sent earlier in the conversation: PDF paths,
    /// and "<pdf path>#page=<n>" for page images from Ask About Page.
    private var attached: Set<String> = []
    private var currentPath = "/"
    private var queue: Task<Void, Never>?
    private var urlObservation: NSKeyValueObservation?
    private var popups: [NSWindow] = []

    private init(path: String) {
        initialPath = path
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        configuration.preferences.isElementFullscreenEnabled = true
        // Run before the bridge (scripts run in the order they're added), so its chips can use SF Symbols
        // and the app's language.
        for source in [Self.iconScript, Self.stringsScript] {
            configuration.userContentController.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world)
            )
        }
        if let script = Bundle.main.url(forResource: "chatgpt-bridge", withExtension: "js"),
           let source = try? String(contentsOf: script, encoding: .utf8) {
            configuration.userContentController.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world)
            )
        }
        let messages = BridgeMessages()
        configuration.userContentController.add(messages, contentWorld: Self.world, name: "folio")
        webView = ChatWebView(frame: .zero, configuration: configuration)
        super.init()
        messages.session = self
        webView.session = self
        currentDocument = Self.document

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.underPageBackgroundColor = .textBackgroundColor
        #if DEBUG
        webView.isInspectable = true
        #endif
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.urlDidChange() }
        }
        let url = URL(string: path, relativeTo: Self.home)?.absoluteURL ?? Self.home
        webView.load(URLRequest(url: Self.isAppHost(url) ? url : Self.home))
    }

    private func close() {
        urlObservation = nil
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "folio", contentWorld: Self.world)
        webView.removeFromSuperview()
        for window in popups { window.close() }
        popups = []
    }

    fileprivate func bridgeDidSend(_ body: Any) {
        guard let message = body as? [String: Any] else { return }
        switch message["type"] as? String {
        case "selection":
            selectedText = message["text"] as? String ?? ""
        case "health":
            missingParts = message["missing"] as? [String] ?? []
        case "sent":
            // PDF passages that just went out: pin a bubble for each where it was asked.
            let path = message["path"] as? String ?? "/"
            let question = (message["question"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let items = message["items"] as? [[String: Any]] ?? []
            QuestionStore.shared.add(items.compactMap { item in
                guard let anchor = PDFAnchor(bridgeValue: item["anchor"]) else { return nil }
                return AskedQuestion(anchor: anchor, quote: item["text"] as? String ?? "", question: question, conversation: path)
            })
        default:
            break
        }
    }

    /// Opens the conversation a bubble came from and scrolls to the message, in the card that already shows
    /// it or else the active card.
    static func reveal(_ question: AskedQuestion) {
        let session = all.first { $0.webView.url?.path == question.conversation } ?? active
        session.focus()
        Task { await session.performReveal(question) }
    }

    private func performReveal(_ question: AskedQuestion) async {
        if webView.url?.path != question.conversation,
           let url = URL(string: question.conversation, relativeTo: Self.home)?.absoluteURL, Self.isAppHost(url) {
            webView.load(URLRequest(url: url))
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard await waitForPage() else { return }
        // The conversation's messages render a moment after the page itself.
        for _ in 0..<40 {
            if await call("return window.__folio.revealQuote(quote)", ["quote": question.quote]) as? Bool == true {
                // chatgpt.com scrolls to the newest message once the conversation loads; scroll back after it does.
                try? await Task.sleep(for: .milliseconds(900))
                _ = await call("return window.__folio.revealQuote(quote)", ["quote": question.quote])
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: Public

    /// Attaches the PDF to the composer. Returns false when it couldn't (signed out, page not ready).
    @discardableResult
    func attach(_ document: URL) async -> Bool {
        await serialized { await self.performAttach(document, explicitly: true) }
    }

    /// Adds a PDF selection to the composer as a chip, attaching the PDF first if this chat doesn't have it.
    /// `anchor` lets Folio pin a bubble on the page once the message is sent.
    @discardableResult
    func ask(about text: String, location: String, in document: URL, anchor: PDFAnchor? = nil) async -> Bool {
        await serialized {
            if await self.needsAttach(document.path, name: document.lastPathComponent) {
                _ = await self.performAttach(document)
            }
            let name = document.deletingPathExtension().lastPathComponent
            return await self.performAddSelection(text, source: "From \(name), \(location)", anchor: anchor)
        }
    }

    /// Adds a whole page: an image of it as an attachment, so ChatGPT sees figures and layout, and its text
    /// as a "Page N" chip.
    @discardableResult
    func ask(aboutPage text: String, location: String, in document: URL, anchor: PDFAnchor, image: Data?) async -> Bool {
        await serialized {
            if await self.needsAttach(document.path, name: document.lastPathComponent) {
                _ = await self.performAttach(document)
            }
            let name = document.deletingPathExtension().lastPathComponent
            if let image {
                // One image per page and conversation: asking about the same page again reuses it.
                let key = "\(document.path)#page=\(anchor.page + 1)"
                let imageName = "\(name), \(location).png"
                if await self.needsAttach(key, name: imageName) {
                    await self.performAttachImage(image, name: imageName, key: key)
                }
            }
            let quote = text.isEmpty ? "[\(location)]" : text
            return await self.performAddSelection(quote, source: "From \(name), \(location) (whole page)", anchor: anchor)
        }
    }

    /// Adds text selected in another card to this card's composer as a chip.
    @discardableResult
    func ask(quoting text: String, from source: ChatGPTSession) async -> Bool {
        let label = source.title.map { "From the chat “\($0)”" } ?? "From another chat"
        return await serialized { await self.performAddSelection(text, source: label, anchor: nil) }
    }

    func newChat() {
        Task {
            let clicked = await call("return window.__folio.startNewChat()") as? Bool ?? false
            if !clicked { loadHome() }
        }
    }

    func focusComposer() {
        webView.takeFocus()
        Task { _ = await call("return window.__folio.focusComposer()") }
    }

    func reload() {
        attached = []
        loadHome()
    }

    /// Removes cookies and storage for every site this web view visited, then reloads.
    static func signOut() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        for session in all { session.reload() }
    }

    // MARK: Auto-attach

    private func scheduleSync() {
        guard Preferences.autoAttach, let document = currentDocument, isNewChat(currentPath) else { return }
        Task {
            // Let chatgpt.com finish swapping the composer after a route change.
            try? await Task.sleep(for: .milliseconds(300))
            await serialized { await self.syncNewChat(with: document) }
        }
    }

    private func syncNewChat(with document: URL) async {
        guard document == currentDocument, isNewChat(currentPath),
              await needsAttach(document.path, name: document.lastPathComponent) else { return }
        // Page images of this PDF can stay; anything from another PDF can't.
        if attached.contains(where: { Self.documentPath(of: $0) != document.path }) {
            // Another PDF is waiting unsent in this new chat. Start clean if nothing was typed.
            let typed = await call("return window.__folio.composerText()") as? String ?? ""
            guard typed.isEmpty else { return }
            loadHome()
            attached = []
        }
        _ = await performAttach(document)
    }

    // MARK: Bridge

    /// The bridge shows the selection as a chip and adds it to the message when the person sends.
    private func performAddSelection(_ text: String, source: String, anchor: PDFAnchor?) async -> Bool {
        guard await waitForPage() else { return false }
        let added = await call(
            "return window.__folio.addSelection(text, source, anchor)",
            ["text": text, "source": source, "anchor": anchor?.bridgeValue ?? NSNull()]
        ) as? Int ?? 0
        focusComposer()
        return added > 0
    }

    /// Attaches a page image unless the composer or conversation already shows one by that name.
    @discardableResult
    private func performAttachImage(_ data: Data, name: String, key: String) async -> Bool {
        guard await waitForPage() else { return false }
        let present = await call("return await window.__folio.hasFile(name)", ["name": name]) as? String ?? ""
        if !present.isEmpty {
            NSLog("Folio: \(name) is already in the \(present), not attaching again")
            markAttached(key)
            return true
        }
        let result = await call(
            "return await window.__folio.attachFile(data, name, 'image/png')",
            ["data": data.base64EncodedString(), "name": name]
        ) as? String
        NSLog("Folio: attach \(name) via bridge: \(result ?? "error")")
        let landed = ["input", "paste", "drop"].contains(result ?? "")
        if landed { markAttached(key) }
        return landed
    }

    /// Uploads the PDF unless this chat already has it. Asking and auto-attach skip a PDF that's in the
    /// composer or was sent earlier in the conversation; an explicit Attach PDF only skips the composer.
    private func performAttach(_ document: URL, explicitly: Bool = false) async -> Bool {
        guard await waitForPage() else { return false }
        let name = document.lastPathComponent
        let present = await call("return await window.__folio.hasFile(name)", ["name": name]) as? String ?? ""
        if present == "composer" || (present == "conversation" && !explicitly) {
            NSLog("Folio: \(name) is already in the \(present), not attaching again")
            markAttached(document.path)
            return true
        }
        guard let data = try? Data(contentsOf: document, options: .mappedIfSafe) else { return false }

        if data.count <= Self.maxBridgeBytes {
            let result = await call(
                "return await window.__folio.attachFile(data, name, 'application/pdf')",
                ["data": data.base64EncodedString(), "name": name]
            ) as? String
            NSLog("Folio: attach \(name) via bridge: \(result ?? "error")")
            switch result {
            case "input", "paste", "drop":
                markAttached(document.path)
                return true
            case "no-composer", "signed-out", nil:
                return false
            default:
                break
            }
        }
        let pasted = await nativePasteFile(document)
        NSLog("Folio: attach \(name) via native paste: \(pasted)")
        if pasted { markAttached(document.path) }
        return pasted
    }

    /// A real ⌘V of the file, for when synthetic events are ignored. Succeeds only if an attachment chip appears.
    private func nativePasteFile(_ file: URL) async -> Bool {
        let name = file.lastPathComponent
        func chips() async -> Int {
            let state = await call("return window.__folio.state(name)", ["name": name]) as? String ?? ""
            return Int(state.split(separator: "|").first ?? "") ?? 0
        }
        let before = await chips()
        guard await paste({ $0.writeObjects([file as NSURL]) }) else { return false }
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            _ = await call("return window.__folio.removeText(path)", ["path": file.path])
            if await chips() > before { return true }
        }
        return false
    }

    /// Puts content on the general pasteboard, sends ⌘V to the web view, then restores the user's clipboard.
    private func paste(_ write: (NSPasteboard) -> Void) async -> Bool {
        guard await call("return window.__folio.focusComposer()") as? Bool == true else { return false }
        webView.takeFocus()
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        pasteboard.clearContents()
        write(pasteboard)
        NSApp.sendAction(#selector(NSText.paste(_:)), to: webView, from: nil)
        // WebKit reads the pasteboard asynchronously; give it a moment before restoring.
        try? await Task.sleep(for: .milliseconds(600))
        pasteboard.clearContents()
        if !saved.isEmpty { pasteboard.writeObjects(saved) }
        return true
    }

    /// Waits until the page has loaded and the bridge script is present.
    private func waitForPage() async -> Bool {
        for _ in 0..<200 {
            if !webView.isLoading, await call("return typeof window.__folio === 'object'") as? Bool == true {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func call(_ script: String, _ arguments: [String: Any] = [:]) async -> Any? {
        do {
            return try await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: Self.world)
        } catch {
            NSLog("Folio bridge error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Runs bridge operations one at a time so two attaches can't interleave.
    private func serialized<T: Sendable>(_ operation: @escaping () async -> T) async -> T {
        let previous = queue
        let task = Task { () -> T in
            await previous?.value
            return await operation()
        }
        queue = Task { _ = await task.value }
        return await task.value
    }

    // MARK: Conversation tracking

    private func isNewChat(_ path: String) -> Bool { path == "/" || path.isEmpty }

    /// A conversation's path: "/c/<id>", or "/g/<project>/c/<id>" inside a project.
    private func isConversation(_ path: String) -> Bool { path.contains("/c/") }

    private func markAttached(_ key: String) {
        attached.insert(key)
        if isConversation(currentPath) { Self.remember(attached, in: currentPath) }
    }

    /// The PDF path an `attached` key belongs to.
    private static func documentPath(of key: String) -> String {
        key.components(separatedBy: "#page=").first ?? key
    }

    /// Whether `key` (named `name` in the composer) still has to be attached. In a new chat the person can
    /// remove a tile before sending, so `attached` is checked against the composer there.
    private func needsAttach(_ key: String, name: String) async -> Bool {
        guard attached.contains(key) else { return true }
        guard isNewChat(currentPath) else { return false }
        let present = await call("return await window.__folio.hasFile(name)", ["name": name]) as? String
        // An unreadable page (nil) keeps the old answer rather than uploading again.
        guard present == "" else { return false }
        NSLog("Folio: \(name) was removed from the composer, attaching it again")
        attached.remove(key)
        return true
    }

    /// Which PDFs each conversation has, kept across launches so reopening a chat doesn't upload them again.
    private static func remembered(in conversation: String) -> Set<String> {
        Set(Preferences.attachedFiles[conversation] ?? [])
    }

    private static func remember(_ files: Set<String>, in conversation: String) {
        var all = Preferences.attachedFiles
        all[conversation] = files.sorted()
        // Keeps the list from growing without bound; forgetting an old chat only costs one check of its page.
        if all.count > 500, let stale = all.keys.first(where: { $0 != conversation }) { all[stale] = nil }
        Preferences.attachedFiles = all
    }

    private func urlDidChange() {
        let path = webView.url?.path ?? "/"
        guard path != currentPath else { return }
        // The first URL arrives while the card is still being created; it isn't in `all` yet.
        if Self.all.contains(self) { Self.saveCards() }
        let previous = currentPath
        currentPath = path
        if isNewChat(path) {
            attached = []
            scheduleSync()
        } else if isNewChat(previous), isConversation(path) {
            // The first message turned the new chat into a conversation; its attachments came along.
            Self.remember(attached.union(Self.remembered(in: path)), in: path)
            attached = Self.remembered(in: path)
        } else {
            attached = Self.remembered(in: path)
        }
    }

    private func loadHome() {
        webView.load(URLRequest(url: Self.home))
    }

    private static func host(_ url: URL, isIn hosts: [String]) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func isAppHost(_ url: URL) -> Bool {
        host(url, isIn: ["chatgpt.com", "openai.com"] + authHosts)
    }
}

// MARK: - Navigation

extension ChatGPTSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload { return .download }
        if navigationAction.navigationType == .linkActivated,
           navigationAction.targetFrame?.isMainFrame == true,
           let url = navigationAction.request.url,
           url.scheme?.hasPrefix("http") == true,
           !Self.isAppHost(url) {
            NSWorkspace.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        currentPath = webView.url?.path ?? "/"
        if isNewChat(currentPath) { scheduleSync() }
    }
}

// MARK: - Downloads

extension ChatGPTSession: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var target = folder.appendingPathComponent(suggestedFilename)
        let base = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
            counter += 1
        }
        return target
    }

    func downloadDidFinish(_ download: WKDownload) {
        NSSound(named: "Glass")?.play()
    }
}

// MARK: - UI

extension ChatGPTSession: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let url = navigationAction.request.url
        // Sign-in popups stay in the app so they share the session; other links open in the browser.
        if url == nil || url?.absoluteString == "about:blank" || url.map(Self.isAppHost) == true {
            return makePopup(configuration: configuration)
        }
        if let url { NSWorkspace.shared.open(url) }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let window = popups.first(where: { $0.contentView === webView }) else { return }
        window.close()
        popups.removeAll { $0 === window }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        if let window = webView.window {
            return await panel.beginSheetModal(for: window) == .OK ? panel.urls : nil
        }
        return panel.runModal() == .OK ? panel.urls : nil
    }

    func webView(
        _ webView: WKWebView,
        decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo,
        type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        type == .microphone ? .prompt : .deny
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func makePopup(configuration: WKWebViewConfiguration) -> WKWebView {
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 680), configuration: configuration)
        popup.uiDelegate = self
        let window = NSWindow(
            contentRect: popup.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = popup
        window.title = String(localized: "Sign In")
        window.center()
        window.makeKeyAndOrderFront(nil)
        popups.append(window)
        return popup
    }
}

// MARK: - Web view

/// The card's web view. Clicking or typing in it makes its card active, and its context menu can send
/// a selection to another card.
final class ChatWebView: WKWebView {
    weak var session: ChatGPTSession?
    private var isTakingFocus = false

    /// Gives the web view keyboard focus without making its card active. Only the person's own clicks
    /// and typing pick the active card; Folio's background edits (auto-attach, pastes) must not.
    func takeFocus() {
        isTakingFocus = true
        window?.makeFirstResponder(self)
        isTakingFocus = false
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, !isTakingFocus { session?.focus() }
        return accepted
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        let items = askMenuItems()
        guard !items.isEmpty else { return }
        for (index, item) in (items + [.separator()]).enumerated() { menu.insertItem(item, at: index) }
    }

    /// "Ask in" items for the selected text: one per other card, and one that opens a new card.
    func askMenuItems() -> [NSMenuItem] {
        guard let session, !session.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var items: [NSMenuItem] = []
        for other in ChatGPTSession.all where other !== session {
            let item = NSMenuItem(title: String(localized: "Ask in “\(other.title ?? String(localized: "New Chat"))”", comment: "Chat card title"), action: #selector(askInCard(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = other
            items.append(item)
        }
        if ChatGPTSession.all.count < ChatGPTSession.maxCards {
            let item = NSMenuItem(title: String(localized: "Ask in New Chat Card"), action: #selector(askInCard(_:)), keyEquivalent: "")
            item.target = self
            items.append(item)
        }
        return items
    }

    @objc func askInCard(_ sender: NSMenuItem) {
        guard let session else { return }
        let text = session.selectedText
        let target = sender.representedObject as? ChatGPTSession ?? ChatGPTSession.add(below: session)
        target.focus()
        Task {
            if await !target.ask(quoting: text, from: session) { NSSound.beep() }
        }
    }
}

/// Receives the bridge's messages without the content controller retaining the session.
private final class BridgeMessages: NSObject, WKScriptMessageHandler {
    weak var session: ChatGPTSession?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        session?.bridgeDidSend(message.body)
    }
}
