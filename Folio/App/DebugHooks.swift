#if DEBUG
import AppKit
import WebKit

/// Debug-only commands for driving the app from a shell, without screen-recording permission.
///
///     osascript -l JavaScript -e 'ObjC.import("Foundation");
///       $.NSDistributedNotificationCenter.defaultCenter
///         .postNotificationNameObjectUserInfoDeliverImmediately("app.folio.debug", "snapshot:/tmp/a.png", $(), true)'
///
/// Commands: `snapshot:<png path>` (window), `websnap:<png path>` (chat web view), `probe` (prints bridge state),
/// `ask:<text>` (selects the first match of text in the open PDF and runs Ask About Selection), `signout`,
/// `sessions` (lists browsers signed in to ChatGPT, without touching the keychain), `signedin`,
/// `authcheck` (lists ChatGPT cookie names and asks chatgpt.com whether the session works),
/// `js:<function body>` (runs in the active card's bridge world and prints the return value),
/// `cards`, `addcard`, `focus:<index>`, `menu[:<index>]` (the active card's "Ask in" items), `layout:columns|rows`,
/// `askpage:<index>`, `bubbles`, `bubbleclick:<index>`, `pagepng:<page>:<path>`, `reveal:<quote text>`,
/// `view:single|continuous|two|book|fit|fitpage|rotate|<percent>`.
enum DebugHooks {
    private nonisolated(unsafe) static var observer: NSObjectProtocol?

    static func install() {
        setvbuf(stdout, nil, _IOLBF, 0)
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("app.folio.debug"), object: nil, queue: .main
        ) { note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { run(command) }
        }
    }

    private static func findPDFView(in view: NSView) -> ReaderPDFView? {
        if let pdfView = view as? ReaderPDFView { return pdfView }
        return view.subviews.lazy.compactMap(findPDFView).first
    }

    private static func run(_ command: String) {
        let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : ""
        switch parts.first {
        case "snapshot":
            guard let frame = NSApp.windows.first(where: { $0.isVisible && $0.toolbar != nil })?.contentView?.superview,
                  let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
            frame.cacheDisplay(in: frame.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: argument))
            print("FOLIO_DEBUG snapshot written")
        case "websnap":
            guard ChatGPTSession.isLoaded else { return print("FOLIO_DEBUG no web view") }
            ChatGPTSession.active.webView.takeSnapshot(with: nil) { image, _ in
                guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: argument))
                print("FOLIO_DEBUG websnap written")
            }
        case "probe":
            guard ChatGPTSession.isLoaded else { return print("FOLIO_DEBUG no web view") }
            ChatGPTSession.active.webView.callAsyncJavaScript(
                "return window.__folio ? window.__folio.probe() : 'no bridge'",
                arguments: [:], in: nil, in: WKContentWorld.world(name: "Folio")
            ) { result in
                print("FOLIO_DEBUG probe", (try? result.get()) as? String ?? "error")
            }
        case "ask":
            guard let pdfView = NSApp.windows.lazy.compactMap({ $0.contentView.flatMap(findPDFView) }).first,
                  let match = pdfView.document?.findString(argument, withOptions: .caseInsensitive).first else {
                return print("FOLIO_DEBUG no match")
            }
            pdfView.setCurrentSelection(match, animate: false)
            let handled = NSApp.sendAction(#selector(MainWindowController.askAboutSelection(_:)), to: nil, from: nil)
            print("FOLIO_DEBUG ask sent", handled ? "handled" : "no responder")
        case "view":
            // `view:single|continuous|two|book|fit|fitpage|rotate|<percent>`, as the View menu does it.
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let action: Selector
            switch argument {
            case "single": item.tag = 0; action = #selector(MainWindowController.setDisplayMode(_:))
            case "continuous": item.tag = 1; action = #selector(MainWindowController.setDisplayMode(_:))
            case "two": item.tag = 2; action = #selector(MainWindowController.setDisplayMode(_:))
            case "book": action = #selector(MainWindowController.toggleBookMode(_:))
            case "fit": action = #selector(MainWindowController.readerZoomToFit(_:))
            case "fitpage": action = #selector(MainWindowController.readerFitPage(_:))
            case "rotate": action = #selector(MainWindowController.rotateRight(_:))
            default: item.tag = Int(argument) ?? 100; action = #selector(MainWindowController.readerSetZoom(_:))
            }
            let handled = NSApp.sendAction(action, to: nil, from: item)
            print("FOLIO_DEBUG view", argument, handled ? "handled" : "no responder")
        case "askpage":
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.representedObject = Int(argument)
            let handled = NSApp.sendAction(#selector(MainWindowController.askAboutPage(_:)), to: nil, from: item)
            print("FOLIO_DEBUG askpage", handled ? "handled" : "no responder")
        case "bubbles", "bubbleclick", "pagepng":
            guard let pdfView = NSApp.windows.lazy.compactMap({ $0.contentView.flatMap(findPDFView) }).first,
                  let document = pdfView.document else { return print("FOLIO_DEBUG no pdf") }
            let bubbles = (0..<document.pageCount).flatMap { index in
                (document.page(at: index)?.annotations ?? []).compactMap { $0 as? QuestionAnnotation }.map { (index, $0) }
            }
            switch parts.first {
            case "bubbles":
                for (index, bubble) in bubbles {
                    print("FOLIO_DEBUG bubble page", index, bubble.bounds.integral, bubble.question?.quote.prefix(40) ?? "-")
                }
                print("FOLIO_DEBUG bubbles \(bubbles.count)")
            case "bubbleclick":
                guard let index = Int(argument), bubbles.indices.contains(index) else { return print("FOLIO_DEBUG no bubble") }
                pdfView.go(to: bubbles[index].1.bounds, on: bubbles[index].1.page!)
                pdfView.onBubbleClick?(bubbles[index].1)
                print("FOLIO_DEBUG bubbleclick", NSApp.windows.contains { $0.className.contains("Popover") && $0.isVisible })
            default:
                // `pagepng:<page>:<path>`: renders a page with its annotations, bubbles included.
                let pieces = argument.split(separator: ":", maxSplits: 1).map(String.init)
                guard pieces.count == 2, let index = Int(pieces[0]), let page = document.page(at: index) else { return }
                // Thumbnails skip custom annotation drawing, so draw the page and then each bubble, as PDFView does.
                let crop = page.bounds(for: .cropBox)
                let scale = 1400 / max(crop.width, crop.height)
                guard let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(crop.width * scale), pixelsHigh: Int(crop.height * scale),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ), let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return }
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -crop.minX, y: -crop.minY)
                page.draw(with: .cropBox, to: context)
                for case let bubble as QuestionAnnotation in page.annotations { bubble.draw(with: .cropBox, in: context) }
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: pieces[1]))
                print("FOLIO_DEBUG pagepng written")
            }
        case "reveal":
            guard let question = QuestionStore.shared.questions.first(where: { $0.quote.contains(argument) }) else {
                return print("FOLIO_DEBUG no question")
            }
            ChatGPTSession.reveal(question)
            print("FOLIO_DEBUG reveal", question.conversation)
        case "signout":
            Task {
                await ChatGPTSession.signOut()
                print("FOLIO_DEBUG signed out")
            }
        case "sessions":
            Task {
                let sessions = await Task.detached { BrowserSessions.find() }.value
                for session in sessions {
                    print("FOLIO_DEBUG session", session.browserName, session.profileName ?? "-",
                          session.isReadable ? "readable" : "blocked", session.lastUsed.map { "\($0)" } ?? "-")
                }
                print("FOLIO_DEBUG sessions \(sessions.count)")
            }
        case "cards":
            for (index, session) in ChatGPTSession.all.enumerated() {
                print("FOLIO_DEBUG card", index, session.isActive ? "active" : "-", session.title ?? "New Chat",
                      session.webView.url?.path ?? "-", "selected=\(session.selectedText.count)")
            }
            print("FOLIO_DEBUG cards \(ChatGPTSession.all.count)")
        case "addcard":
            ChatGPTSession.add(below: ChatGPTSession.active)
            print("FOLIO_DEBUG cards \(ChatGPTSession.all.count)")
        case "panel":
            func findPanel(_ controller: NSViewController) -> ChatPanelViewController? {
                controller as? ChatPanelViewController ?? controller.children.lazy.compactMap(findPanel).first
            }
            let panel = NSApp.windows.lazy.compactMap({ $0.contentViewController.flatMap(findPanel) }).first
            print("FOLIO_DEBUG panel", panel?.layoutReport ?? "none")
        case "layout":
            // `layout:columns` or `layout:rows`.
            func find(_ controller: NSViewController) -> ChatPanelViewController? {
                controller as? ChatPanelViewController ?? controller.children.lazy.compactMap(find).first
            }
            guard let panel = NSApp.windows.lazy.compactMap({ $0.contentViewController.flatMap(find) }).first
            else { return print("FOLIO_DEBUG no panel") }
            panel.setSideBySide(argument == "columns")
            print("FOLIO_DEBUG layout", panel.isSideBySide ? "columns" : "rows")
        case "focus":
            guard let index = Int(argument), ChatGPTSession.all.indices.contains(index) else { return print("FOLIO_DEBUG no card") }
            ChatGPTSession.all[index].focus()
            print("FOLIO_DEBUG focused \(index)")
        case "menu":
            // Lists the active card's "Ask in" items, or picks one by index: `menu:<index>`.
            let items = ChatGPTSession.active.webView.askMenuItems()
            if let index = Int(argument), items.indices.contains(index) {
                ChatGPTSession.active.webView.askInCard(items[index])
                print("FOLIO_DEBUG menu picked", items[index].title)
            } else {
                print("FOLIO_DEBUG menu", items.map(\.title))
            }
        case "signedin":
            Task { print("FOLIO_DEBUG signedin", await ChatGPTSession.hasSignIn()) }
        case "js":
            // Runs an async function body in the bridge's content world and prints what it returns.
            guard ChatGPTSession.isLoaded else { return print("FOLIO_DEBUG no web view") }
            Task {
                do {
                    let result = try await ChatGPTSession.active.webView.callAsyncJavaScript(
                        argument, arguments: [:], in: nil, contentWorld: .world(name: "Folio")
                    )
                    print("FOLIO_DEBUG js", result.map { "\($0)" } ?? "undefined")
                } catch {
                    print("FOLIO_DEBUG js error", error.localizedDescription)
                }
            }
        case "authcheck":
            // Asks chatgpt.com whether it sees a session, and lists the cookie names WebKit holds. No values.
            Task {
                let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
                    .filter { BrowserSessions.isChatGPTHost($0.domain) }
                for cookie in cookies {
                    print("FOLIO_DEBUG cookie", cookie.domain, cookie.name, cookie.value.count, cookie.expiresDate.map { "\($0)" } ?? "session")
                }
                guard ChatGPTSession.isLoaded else { return print("FOLIO_DEBUG no web view") }
                let result = try? await ChatGPTSession.active.webView.callAsyncJavaScript(
                    """
                    const r = await fetch('/api/auth/session', {credentials: 'include'});
                    const t = await r.text();
                    let keys = '';
                    try { const j = JSON.parse(t); keys = Object.keys(j).join(',') + (j.user ? ' user=yes' : ' user=no') + ' error=' + JSON.stringify(j.error) + ' provider=' + j.authProvider + ' expires=' + j.expires; } catch (e) { keys = 'non-json ' + t.slice(0, 80); }
                    return r.status + ' ' + keys + ' url=' + location.href;
                    """,
                    arguments: [:], in: nil, contentWorld: .page
                )
                print("FOLIO_DEBUG auth", result as? String ?? "error")
            }
        default:
            print("FOLIO_DEBUG unknown command \(command)")
        }
    }
}
#endif
