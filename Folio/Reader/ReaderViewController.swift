import AppKit
import PDFKit
import SwiftUI

/// PDFView with "Ask ChatGPT" items at the top of its context menu (the selection, or the page under the
/// pointer) and clickable question bubbles.
final class ReaderPDFView: PDFView {
    /// Called with a bubble the person clicked.
    var onBubbleClick: ((QuestionAnnotation) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        var items: [NSMenuItem] = []
        if let text = currentSelection?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(NSMenuItem(title: "Ask ChatGPT", action: #selector(MainWindowController.askAboutSelection(_:)), keyEquivalent: ""))
        }
        let point = convert(event.locationInWindow, from: nil)
        if let document, let page = page(for: point, nearest: false) {
            let index = document.index(for: page)
            let item = NSMenuItem(title: "Ask ChatGPT About Page \(index + 1)", action: #selector(MainWindowController.askAboutPage(_:)), keyEquivalent: "")
            item.representedObject = index
            items.append(item)
        }
        guard !items.isEmpty else { return menu }
        for (index, item) in (items + [.separator()]).enumerated() { menu.insertItem(item, at: index) }
        return menu
    }

    override func mouseDown(with event: NSEvent) {
        if let bubble = bubble(at: event) {
            onBubbleClick?(bubble)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if bubble(at: event) != nil { NSCursor.pointingHand.set() }
    }

    private func bubble(at event: NSEvent) -> QuestionAnnotation? {
        let point = convert(event.locationInWindow, from: nil)
        guard let page = page(for: point, nearest: false) else { return nil }
        let pagePoint = convert(point, to: page)
        return page.annotations.last { $0 is QuestionAnnotation && $0.bounds.contains(pagePoint) } as? QuestionAnnotation
    }
}

/// The document view: a PDFView, an optional thumbnail column, and find. Nothing beyond what PDFKit offers.
final class ReaderViewController: NSViewController {
    let url: URL
    let pdfView = ReaderPDFView()

    /// Called when the page, zoom or find state changes, so the window can update its subtitle.
    var onStateChange: (() -> Void)?

    private let thumbnails = PDFThumbnailView()
    private var thumbnailWidth: NSLayoutConstraint!
    private let failureLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private var matches: [PDFSelection] = []
    private var matchIndex = 0
    private var lastQuery = ""
    private var saveWork: DispatchWorkItem?

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let container = NSView()

        pdfView.autoScales = true
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = true
        pdfView.backgroundColor = .underPageBackgroundColor
        applyDisplayMode(Preferences.displayMode)

        thumbnails.pdfView = pdfView
        thumbnails.thumbnailSize = NSSize(width: 96, height: 128)
        thumbnails.backgroundColor = .underPageBackgroundColor
        thumbnails.maximumNumberOfColumns = 1

        let divider = NSBox()
        divider.boxType = .separator
        // A separator box made with a zero frame reports a 1pt intrinsic height. Left at its default
        // hugging priority, that outranks the window's own size and shrinks the window.
        divider.setContentHuggingPriority(.init(1), for: .vertical)
        divider.setContentCompressionResistancePriority(.init(1), for: .vertical)

        failureLabel.textColor = .secondaryLabelColor
        failureLabel.alignment = .center
        failureLabel.isHidden = true
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isDisplayedWhenStopped = false

        for view in [thumbnails, divider, pdfView, failureLabel, spinner] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        let top = container.safeAreaLayoutGuide.topAnchor
        thumbnailWidth = thumbnails.widthAnchor.constraint(equalToConstant: Preferences.showThumbnails ? 148 : 0)
        NSLayoutConstraint.activate([
            thumbnails.topAnchor.constraint(equalTo: top),
            thumbnails.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            thumbnails.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            thumbnailWidth,
            divider.topAnchor.constraint(equalTo: top),
            divider.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: thumbnails.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            pdfView.topAnchor.constraint(equalTo: top),
            pdfView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            failureLabel.centerXAnchor.constraint(equalTo: pdfView.centerXAnchor),
            failureLabel.centerYAnchor.constraint(equalTo: pdfView.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: pdfView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: pdfView.centerYAnchor),
        ])
        thumbnails.isHidden = !Preferences.showThumbnails
        divider.isHidden = !Preferences.showThumbnails
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
        guard status == .notDownloaded else { return loadDocument() }
        // A File Provider placeholder, such as a Findle file: download it off the main thread first,
        // since opening it here would block the window until the download finishes.
        spinner.startAnimation(nil)
        let url = url
        Task {
            let downloaded = await Task.detached(priority: .userInitiated) {
                (try? LibraryStore.coordinatedRead(url, readsData: false)) != nil
            }.value
            spinner.stopAnimation(nil)
            if downloaded {
                loadDocument()
                onStateChange?()
            } else {
                failureLabel.stringValue = "This file couldn’t be downloaded."
                failureLabel.isHidden = false
            }
        }
    }

    private func loadDocument() {
        guard let document = PDFDocument(url: url) else {
            failureLabel.stringValue = "This file can’t be opened."
            failureLabel.isHidden = false
            return
        }
        if document.isLocked, !unlock(document) {
            failureLabel.stringValue = "This PDF is locked."
            failureLabel.isHidden = false
            return
        }
        pdfView.document = document
        restorePosition()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(viewStateChanged(_:)), name: .PDFViewPageChanged, object: pdfView)
        center.addObserver(self, selector: #selector(viewStateChanged(_:)), name: .PDFViewScaleChanged, object: pdfView)
        center.addObserver(self, selector: #selector(questionsChanged(_:)), name: QuestionStore.didChange, object: nil)
        pdfView.onBubbleClick = { [weak self] bubble in self?.showPopover(for: bubble) }
        refreshBubbles()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(pdfView)
    }

    // MARK: State

    var hasDocument: Bool { pdfView.document != nil }

    var showsThumbnails: Bool { !thumbnails.isHidden }

    var displayModeTag: Int {
        switch pdfView.displayMode {
        case .singlePage: 0
        case .twoUp, .twoUpContinuous: 2
        default: 1
        }
    }

    var statusText: String {
        if !lastQuery.isEmpty {
            if matches.isEmpty { return "No matches" }
            return "\(matchIndex + 1) of \(matches.count) matches"
        }
        guard let document = pdfView.document, let page = pdfView.currentPage else { return "" }
        return "Page \(document.index(for: page) + 1) of \(document.pageCount)"
    }

    var hasSelection: Bool {
        !(pdfView.currentSelection?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The selected text, cleaned for quoting, where it is ("page 4", "pages 4–5"), and where its bubble goes.
    func selectionForChat() -> (text: String, location: String, anchor: PDFAnchor)? {
        guard let selection = pdfView.currentSelection,
              let raw = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let document = pdfView.document else { return nil }
        let pages = selection.pages.sorted { document.index(for: $0) < document.index(for: $1) }
        guard let firstPage = pages.first, let lastPage = pages.last else { return nil }
        let first = document.index(for: firstPage) + 1
        let last = document.index(for: lastPage) + 1
        let location = first == last ? "page \(first)" : "pages \(first)–\(last)"
        let anchor = PDFAnchor(document: url, page: first - 1, bounds: selection.bounds(for: firstPage))
        return (Self.clean(raw), location, anchor)
    }

    /// A whole page: its text, an image of it for ChatGPT, and its bubble's anchor. Defaults to the current page.
    func pageForChat(_ index: Int? = nil) -> (text: String, location: String, anchor: PDFAnchor, image: Data?)? {
        guard let document = pdfView.document,
              let page = index.flatMap(document.page(at:)) ?? pdfView.currentPage else { return nil }
        let number = document.index(for: page) + 1
        var text = Self.clean((page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        if text.count > 4000 { text = String(text.prefix(4000)) + "…" }
        return (text, "page \(number)", PDFAnchor(document: url, page: number - 1, bounds: nil), pageImage(page))
    }

    /// A PNG of the page as printed: without Folio's own bubbles.
    private func pageImage(_ page: PDFPage) -> Data? {
        let bubbles = page.annotations.filter { $0 is QuestionAnnotation }
        bubbles.forEach(page.removeAnnotation)
        defer { bubbles.forEach(page.addAnnotation) }
        let image = page.thumbnail(of: NSSize(width: 1600, height: 1600), for: .cropBox)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: Question bubbles

    /// Called when the person picks "Show in Chat" on a bubble.
    var onShowQuestion: ((AskedQuestion) -> Void)?
    private var popover: NSPopover?

    /// Replaces the bubbles on every page with the current questions for this file.
    private func refreshBubbles() {
        guard let document = pdfView.document else { return }
        let questions = Preferences.showQuestionBubbles ? QuestionStore.shared.questions(for: url) : []
        let byPage = Dictionary(grouping: questions) { $0.anchor.page }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let old = page.annotations.filter { $0 is QuestionAnnotation }
            let wanted = byPage[index] ?? []
            if old.isEmpty && wanted.isEmpty { continue }
            old.forEach(page.removeAnnotation)
            QuestionAnnotation.bubbles(for: wanted, on: page).forEach(page.addAnnotation)
        }
    }

    @objc private func questionsChanged(_ notification: Notification) {
        refreshBubbles()
    }

    private func showPopover(for bubble: QuestionAnnotation) {
        guard let page = bubble.page, let question = bubble.question else { return }
        popover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: QuestionPopover(
            question: question,
            onShow: { [weak self] in
                self?.popover?.close()
                self?.onShowQuestion?(question)
            },
            onDelete: { [weak self] in
                self?.popover?.close()
                QuestionStore.shared.remove(question.id)
            }
        ))
        let rect = pdfView.convert(bubble.bounds, from: page)
        popover.show(relativeTo: rect, of: pdfView, preferredEdge: .maxX)
        self.popover = popover
    }

    /// Joins words hyphenated across lines and lines broken inside a paragraph.
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacing(#/(\w)-\n(\w)/#) { "\($0.1)\($0.2)" }
            .replacing(#/([^\n])\n(?!\n)/#) { "\($0.1) " }
    }

    func saveState() {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return }
        Preferences.setReadingPosition(
            .init(page: document.index(for: page), scale: Double(pdfView.scaleFactor), autoScales: pdfView.autoScales),
            for: url
        )
    }

    private func restorePosition() {
        guard let position = Preferences.readingPosition(for: url), let document = pdfView.document else { return }
        if !position.autoScales {
            pdfView.autoScales = false
            pdfView.scaleFactor = CGFloat(position.scale)
        }
        guard position.page > 0, let page = document.page(at: min(position.page, document.pageCount - 1)) else { return }
        // Wait one runloop turn so the view has laid out its pages.
        DispatchQueue.main.async { [weak self] in self?.pdfView.go(to: page) }
    }

    @objc private func viewStateChanged(_ notification: Notification) {
        onStateChange?()
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveState() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func unlock(_ document: PDFDocument) -> Bool {
        let alert = NSAlert()
        alert.messageText = "“\(url.deletingPathExtension().lastPathComponent)” is locked"
        alert.informativeText = "Enter the password to open it."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        while alert.runModal() == .alertFirstButtonReturn {
            if document.unlock(withPassword: field.stringValue) { return true }
            field.stringValue = ""
            alert.informativeText = "That password didn’t work. Try again."
        }
        return false
    }

    // MARK: Commands

    func toggleThumbnails() {
        let show = thumbnails.isHidden
        thumbnails.isHidden = !show
        view.subviews.compactMap { $0 as? NSBox }.forEach { $0.isHidden = !show }
        thumbnailWidth.constant = show ? 148 : 0
        Preferences.showThumbnails = show
    }

    func setDisplayMode(_ tag: Int) {
        applyDisplayMode(tag)
        Preferences.displayMode = tag
    }

    private func applyDisplayMode(_ tag: Int) {
        switch tag {
        case 0: pdfView.displayMode = .singlePage
        case 2: pdfView.displayMode = .twoUpContinuous
        default: pdfView.displayMode = .singlePageContinuous
        }
    }

    func zoomIn() { pdfView.zoomIn(nil) }
    func zoomOut() { pdfView.zoomOut(nil) }

    func actualSize() {
        pdfView.autoScales = false
        pdfView.scaleFactor = 1
    }

    func zoomToFit() { pdfView.autoScales = true }

    func previousPage() { pdfView.goToPreviousPage(nil) }
    func nextPage() { pdfView.goToNextPage(nil) }

    func goToPage() {
        guard let document = pdfView.document, let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Go to Page"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.placeholderString = "1–\(document.pageCount)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self,
                  let number = Int(field.stringValue.trimmingCharacters(in: .whitespaces)),
                  let page = document.page(at: max(0, min(number - 1, document.pageCount - 1))) else { return }
            self.pdfView.go(to: page)
        }
    }

    func printDocument() {
        pdfView.print(with: NSPrintInfo.shared, autoRotate: true)
    }

    // MARK: Find

    func find(_ query: String, backwards: Bool = false) {
        guard let document = pdfView.document else { return }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            clearFind()
            return
        }
        if query != lastQuery {
            lastQuery = query
            matches = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
            matches.forEach { $0.color = NSColor.systemYellow.withAlphaComponent(0.45) }
            // Start from the first match on or after the current page.
            let current = pdfView.currentPage.map { document.index(for: $0) } ?? 0
            matchIndex = matches.firstIndex { match in
                match.pages.first.map { document.index(for: $0) >= current } ?? false
            } ?? 0
        } else if !matches.isEmpty {
            matchIndex = (matchIndex + (backwards ? -1 : 1) + matches.count) % matches.count
        }
        showMatch()
    }

    func clearFind() {
        lastQuery = ""
        matches = []
        matchIndex = 0
        pdfView.highlightedSelections = nil
        onStateChange?()
    }

    private func showMatch() {
        pdfView.highlightedSelections = matches.isEmpty ? nil : matches
        if matches.indices.contains(matchIndex) {
            let match = matches[matchIndex]
            pdfView.setCurrentSelection(match, animate: true)
            pdfView.go(to: match)
        }
        onStateChange?()
    }
}
