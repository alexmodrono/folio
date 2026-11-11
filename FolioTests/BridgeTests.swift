import Foundation
import Testing
import WebKit
@testable import Folio

/// Lets tests find resources in the test bundle.
final class TestBundleToken {}

/// A WKWebView with the chatgpt.com bridge injected exactly as `ChatGPTSession` does it.
@MainActor final class BridgePage: NSObject, WKNavigationDelegate {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static let world = WKContentWorld.world(name: "Folio")
    let webView: WKWebView
    private var loading: CheckedContinuation<Void, Error>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if let script = Bundle.main.url(forResource: "chatgpt-bridge", withExtension: "js"),
           let source = try? String(contentsOf: script, encoding: .utf8) {
            configuration.userContentController.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world)
            )
        }
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    static func bridgeSource() throws -> String {
        guard let url = Bundle.main.url(forResource: "chatgpt-bridge", withExtension: "js") else {
            throw Failure(description: "chatgpt-bridge.js isn't in the app bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Loads `html` as if it came from chatgpt.com at `path`, and waits for the bridge.
    func load(_ html: String, path: String = "/") async throws {
        _ = try Self.bridgeSource()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loading = continuation
            webView.loadHTMLString(html, baseURL: URL(string: "https://chatgpt.com\(path)"))
        }
        let ready = try await run("return await until(() => !!window.__folio)")
        guard ready as? Bool == true else { throw Failure(description: "window.__folio never appeared") }
        // Let the first refresh pass run.
        _ = try await run("await new Promise(r => setTimeout(r, 150)); return true")
    }

    /// Runs `body` as an async function in the bridge's content world. `until(check, ms)` polls for a condition.
    @discardableResult
    func run(_ body: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        let prelude = """
        const until = async (check, ms = 3000) => {
          const end = Date.now() + ms;
          for (;;) {
            const value = check();
            if (value || Date.now() > end) return value;
            await new Promise((r) => setTimeout(r, 25));
          }
        };
        const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

        """
        return try await webView.callAsyncJavaScript(prelude + body, arguments: arguments, in: nil, contentWorld: Self.world)
    }

    func string(_ body: String, _ arguments: [String: Any] = [:]) async throws -> String? {
        try await run(body, arguments) as? String
    }

    func int(_ body: String, _ arguments: [String: Any] = [:]) async throws -> Int? {
        (try await run(body, arguments) as? NSNumber)?.intValue
    }

    func bool(_ body: String, _ arguments: [String: Any] = [:]) async throws -> Bool? {
        try await run(body, arguments) as? Bool
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading?.resume()
        loading = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loading?.resume(throwing: error)
        loading = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loading?.resume(throwing: error)
        loading = nil
    }
}

/// Synthetic pages that mirror the parts of chatgpt.com the bridge's SELECTORS target.
enum SyntheticChatGPT {
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// A user message as chatgpt.com renders it: the bubble holds a pre-wrap div with one text node.
    static func userMessage(_ text: String, extra: String = "") -> String {
        """
        <div data-message-author-role="user" data-message-id="\(UUID().uuidString)">
          \(extra)
          <div data-user-message-bubble="true" class="user-message-bubble-color"><div class="whitespace-pre-wrap">\(escape(text))</div></div>
        </div>
        """
    }

    static func page(messages: [String] = [], attachments: String = "", composerText: String = "") -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>ChatGPT</title></head>
        <body>
          <main>
            <div id="thread">\(messages.joined(separator: "\n"))</div>
            <form class="w-full" data-type="unified-composer">
              <div class="grid ComposerLayoutBody_abc123 flex-col">
                \(attachments)
                <div style="min-height: 24px; width: 600px">
                  <div contenteditable="true" translate="no" class="ProseMirror" id="prompt-textarea" style="min-height: 24px"><p>\(escape(composerText))</p></div>
                </div>
              </div>
              <button type="submit" aria-label="Send" data-testid="send-button">Send</button>
            </form>
          </main>
        </body></html>
        """
    }

    static func fileChip(_ name: String) -> String {
        """
        <div class="group relative" role="group" aria-label="\(escape(name))">
          <div class="truncate font-semibold">\(escape(name))</div><div>PDF</div>
        </div>
        """
    }
}

@MainActor @Suite(.serialized) struct BridgeSelectionTests {
    func freshPage() async throws -> BridgePage {
        let page = BridgePage()
        try await page.load(SyntheticChatGPT.page())
        return page
    }

    func add(_ page: BridgePage, _ text: String, _ source: String) async throws -> Int? {
        try await page.int("return window.__folio.addSelection(text, source, null)", ["text": text, "source": source])
    }

    func trayLabel(_ page: BridgePage) async throws -> String? {
        try await page.string("""
            const tray = await until(() => document.querySelector('.folio-tray'));
            return tray ? tray.querySelector('.folio-chip').textContent.trim() : null;
            """)
    }

    @Test func bridgeLoads() async throws {
        let page = try await freshPage()
        let probe = try await page.string("return window.__folio.probe()") ?? ""
        #expect(probe.contains(#""composer":"div#prompt-textarea""#), "\(probe)")
        #expect(probe.contains(#""inForm":true"#))
        // The page's own world can't see the bridge.
        let leaked = try await page.webView.evaluateJavaScript("typeof window.__folio") as? String
        #expect(leaked == "undefined")
    }

    @Test func addSelectionMountsTrayFirstInComposerBody() async throws {
        let page = try await freshPage()
        #expect(try await add(page, "Some quoted text", "From doc, page 3") == 1)
        #expect(try await trayLabel(page) == "1 selection")
        let first = try await page.bool("""
            const body = document.querySelector('[class*="ComposerLayoutBody"]');
            return body.firstElementChild.classList.contains('folio-tray')
              && document.querySelectorAll('.folio-tray').length === 1;
            """)
        #expect(first == true)
        #expect(try await page.int("return window.__folio.pendingSelections()") == 1)
    }

    @Test func labelForTwoSelections() async throws {
        let page = try await freshPage()
        _ = try await add(page, "one", "From doc, page 1")
        #expect(try await add(page, "two", "From doc, pages 2–3") == 2)
        let label = try await page.string("""
            await until(() => document.querySelector('.folio-tray')?.textContent.includes('2'));
            return document.querySelector('.folio-tray .folio-chip').textContent.trim();
            """)
        #expect(label == "2 selections")
        #expect(try await page.int("return document.querySelectorAll('.folio-tray .folio-quote').length") == 2)
    }

    @Test func labelForWholePage() async throws {
        let page = try await freshPage()
        _ = try await add(page, "the whole page's text", "From doc, page 7 (whole page)")
        #expect(try await trayLabel(page) == "Page 7")
    }

    @Test func labelForSeveralWholePages() async throws {
        let page = try await freshPage()
        _ = try await add(page, "page text", "From doc, page 7 (whole page)")
        _ = try await add(page, "more text", "From doc, page 9 (whole page)")
        _ = try await add(page, "even more", "From other, page 1 (whole page)")
        let label = try await page.string("""
            await until(() => document.querySelector('.folio-tray')?.textContent.includes('3'));
            return document.querySelector('.folio-tray .folio-chip').textContent.trim();
            """)
        #expect(label == "3 pages")
    }

    @Test func labelForMixedReferences() async throws {
        let page = try await freshPage()
        _ = try await add(page, "page text", "From doc, page 7 (whole page)")
        _ = try await add(page, "a passage", "From doc, page 2")
        let label = try await page.string("""
            await until(() => document.querySelector('.folio-tray')?.textContent.includes('2'));
            return document.querySelector('.folio-tray .folio-chip').textContent.trim();
            """)
        #expect(label == "2 references")
    }

    @Test func addSelectionCleansWhitespaceAndMarkup() async throws {
        let page = try await freshPage()
        _ = try await add(page, "  first\n\n  line\t\tcontinues ==} here <<} ", " From  doc,\npage 1 ")
        let quote = try await page.string("""
            await until(() => document.querySelector('.folio-tray'));
            return document.querySelector('.folio-tray .folio-quote-text').textContent;
            """)
        #expect(quote == "first line continues = =} here < <}")
        #expect(try await page.string("return document.querySelector('.folio-tray .folio-source').textContent") == "From doc, page 1")
    }

    @Test func emptySelectionIsIgnored() async throws {
        let page = try await freshPage()
        #expect(try await add(page, "  \n\t ", "From doc, page 1") == 0)
        #expect(try await page.bool("await sleep(150); return !document.querySelector('.folio-tray')") == true)
    }

    @Test func removeButtonClearsTray() async throws {
        let page = try await freshPage()
        _ = try await add(page, "one", "From doc, page 1")
        let cleared = try await page.bool("""
            const remove = await until(() => document.querySelector('.folio-tray .folio-remove'));
            remove.click();
            return await until(() => !document.querySelector('.folio-tray')) && window.__folio.pendingSelections() === 0;
            """)
        #expect(cleared == true)
    }

    @Test func clearSelectionsRemovesTray() async throws {
        let page = try await freshPage()
        _ = try await add(page, "one", "From doc, page 1")
        let cleared = try await page.bool("""
            await until(() => document.querySelector('.folio-tray'));
            window.__folio.clearSelections();
            return await until(() => !document.querySelector('.folio-tray'));
            """)
        #expect(cleared == true)
    }

    @Test func trayComesBackWhenComposerIsReplaced() async throws {
        let page = try await freshPage()
        _ = try await add(page, "one", "From doc, page 1")
        let back = try await page.bool("""
            await until(() => document.querySelector('.folio-tray'));
            // React can swap the composer body out.
            const old = document.querySelector('[class*="ComposerLayoutBody"]');
            const fresh = old.cloneNode(false);
            fresh.innerHTML = '<div contenteditable="true" class="ProseMirror" style="min-height:24px"><p></p></div>';
            old.replaceWith(fresh);
            return !!(await until(() => fresh.querySelector('.folio-tray')));
            """)
        #expect(back == true)
    }
}

@MainActor @Suite(.serialized) struct BridgeMessageTests {
    /// Waits for the bridge to render, then describes the first user message.
    func describe(_ page: BridgePage, index: Int = 0) async throws -> [String: Any] {
        let json = try await page.string("""
            await until(() => document.querySelector('.folio-message-selections'), 1000);
            await sleep(100);
            const bubble = document.querySelectorAll('[data-user-message-bubble]')[index];
            const text = bubble.querySelector('.whitespace-pre-wrap');
            const views = bubble.querySelectorAll('.folio-message-selections');
            const own = [...text.childNodes].filter((n) => n.nodeType === Node.TEXT_NODE).map((n) => n.nodeValue).join('');
            return JSON.stringify({
              views: views.length,
              label: views[0]?.querySelector('.folio-chip')?.textContent.trim() ?? null,
              quotes: [...bubble.querySelectorAll('.folio-quote-text')].map((q) => q.textContent),
              sources: [...bubble.querySelectorAll('.folio-source')].map((q) => q.textContent),
              text: own,
              removable: !!bubble.querySelector('.folio-remove'),
            });
            """, ["index": index]) ?? "{}"
        return try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
    }

    @Test func rendersOneSelection() async throws {
        let page = BridgePage()
        try await page.load(SyntheticChatGPT.page(messages: [
            SyntheticChatGPT.userMessage("{==the quoted passage==}{>>From X, page 2<<}\n\nquestion"),
        ]), path: "/c/abc")
        let message = try await describe(page)
        #expect(message["views"] as? Int == 1)
        #expect(message["label"] as? String == "1 selection")
        #expect(message["quotes"] as? [String] == ["the quoted passage"])
        #expect(message["sources"] as? [String] == ["From X, page 2"])
        #expect(message["text"] as? String == "question")
        #expect(message["removable"] as? Bool == false)
    }

    @Test func rendersSeveralSelections() async throws {
        let page = BridgePage()
        try await page.load(SyntheticChatGPT.page(messages: [
            SyntheticChatGPT.userMessage(
                "{==first==}{>>From X, page 1<<}\n{==second\nline==}{>>From X, page 4<<}\n{==no source==}\n\nWhat links these?"
            ),
        ]), path: "/c/abc")
        let message = try await describe(page)
        #expect(message["views"] as? Int == 1)
        #expect(message["label"] as? String == "3 selections")
        #expect(message["quotes"] as? [String] == ["first", "second\nline", "no source"])
        #expect(message["sources"] as? [String] == ["From X, page 1", "From X, page 4"])
        #expect(message["text"] as? String == "What links these?")
    }

    @Test func rendersWholePageReference() async throws {
        let page = BridgePage()
        try await page.load(SyntheticChatGPT.page(messages: [
            SyntheticChatGPT.userMessage("{==all of page seven==}{>>From doc, page 7 (whole page)<<}\n\nsummarize"),
        ]), path: "/c/abc")
        let message = try await describe(page)
        #expect(message["label"] as? String == "Page 7")
        #expect(message["text"] as? String == "summarize")
    }

    @Test func leavesPlainMessagesAlone() async throws {
        let page = BridgePage()
        let plain = "Just a question about {braces} and == signs <<}"
        try await page.load(SyntheticChatGPT.page(messages: [SyntheticChatGPT.userMessage(plain)]), path: "/c/abc")
        let message = try await describe(page)
        #expect(message["views"] as? Int == 0)
        #expect(message["text"] as? String == plain)
    }

    @Test func rendersEachMessageSeparately() async throws {
        let page = BridgePage()
        try await page.load(SyntheticChatGPT.page(messages: [
            SyntheticChatGPT.userMessage("{==a==}{>>From X, page 1<<}\n\none"),
            SyntheticChatGPT.userMessage("no markup here"),
            SyntheticChatGPT.userMessage("{==b==}{>>From X, page 2<<}\n{==c==}{>>From Y, page 3<<}\n\nthree"),
        ]), path: "/c/abc")
        let first = try await describe(page, index: 0)
        let second = try await describe(page, index: 1)
        let third = try await describe(page, index: 2)
        #expect(first["views"] as? Int == 1)
        #expect(first["text"] as? String == "one")
        #expect(second["views"] as? Int == 0)
        #expect(second["text"] as? String == "no markup here")
        #expect(third["views"] as? Int == 1)
        #expect(third["label"] as? String == "2 selections")
        #expect(third["text"] as? String == "three")
    }

    @Test func rendersMessagesThatArriveLater() async throws {
        let page = BridgePage()
        try await page.load(SyntheticChatGPT.page(), path: "/c/abc")
        let html = SyntheticChatGPT.userMessage("{==late==}{>>From X, page 5<<}\n\nstreamed in")
        try await page.run("document.getElementById('thread').insertAdjacentHTML('beforeend', html)", ["html": html])
        let message = try await describe(page)
        #expect(message["views"] as? Int == 1)
        #expect(message["text"] as? String == "streamed in")
    }

    @Test func rerenderingDoesntDuplicateChips() async throws {
        let page = BridgePage()
        try await page.load(SyntheticChatGPT.page(messages: [
            SyntheticChatGPT.userMessage("{==a==}{>>From X, page 1<<}\n\none"),
        ]), path: "/c/abc")
        _ = try await describe(page)
        // React rewrites the text node with the original markup (an edit, or a re-render).
        try await page.run("""
            const text = document.querySelector('.whitespace-pre-wrap');
            const node = [...text.childNodes].find((n) => n.nodeType === Node.TEXT_NODE);
            node.nodeValue = '{==a==}{>>From X, page 1<<}\\n\\none';
            await sleep(200);
            """)
        let message = try await describe(page)
        #expect(message["views"] as? Int == 1)
        #expect(message["text"] as? String == "one")
    }

    @Test func revealQuote() async throws {
        let page = BridgePage()
        let quote = "A rather long passage that the person quoted from page two of the document they were reading"
        try await page.load(SyntheticChatGPT.page(messages: [
            SyntheticChatGPT.userMessage("{==\(quote)==}{>>From X, page 2<<}\n\nquestion"),
        ]), path: "/c/abc")
        _ = try await describe(page)
        #expect(try await page.bool("return window.__folio.revealQuote(q)", ["q": quote]) == true)
        #expect(try await page.bool("return document.querySelector('.folio-message-selections').hasAttribute('data-open')") == true)
        // Whitespace differences don't matter.
        #expect(try await page.bool("return window.__folio.revealQuote(q)", ["q": "A rather  long\npassage"]) == true)
        #expect(try await page.bool("return window.__folio.revealQuote(q)", ["q": "Something never quoted"]) == false)
    }

    @Test func revealQuoteSkipsHiddenCopies() async throws {
        let page = BridgePage()
        let quote = "A passage that chatgpt.com also keeps in a hidden copy of the thread"
        let message = SyntheticChatGPT.userMessage("{==\(quote)==}{>>From X, page 2<<}\n\nquestion")
        try await page.load(SyntheticChatGPT.page(messages: [
            #"<div id="hidden-copy" style="display: none">\#(message)</div>"#,
            message,
        ]), path: "/c/abc")
        _ = try await describe(page)
        #expect(try await page.int("return document.querySelectorAll('.folio-message-selections').length") == 2)
        #expect(try await page.bool("return window.__folio.revealQuote(q)", ["q": quote]) == true)
        let opened = try await page.string("""
            return [...document.querySelectorAll('.folio-message-selections')]
              .map((v) => (v.closest('#hidden-copy') ? 'hidden:' : 'shown:') + v.hasAttribute('data-open')).join(',');
            """)
        #expect(opened == "hidden:false,shown:true")
    }

    @Test func revealQuoteBeforeRenderIsFalse() async throws {
        let page = BridgePage()
        try await page.load(SyntheticChatGPT.page(), path: "/c/abc")
        #expect(try await page.bool("return window.__folio.revealQuote('anything')") == false)
    }
}

@MainActor @Suite(.serialized) struct BridgeFileTests {
    func hasFile(_ page: BridgePage, _ name: String) async throws -> String? {
        try await page.string("return await window.__folio.hasFile(name)", ["name": name])
    }

    @Test func findsFileInComposer() async throws {
        let page = BridgePage()
        try await page.load(SyntheticChatGPT.page(attachments: SyntheticChatGPT.fileChip("doc.pdf")))
        #expect(try await hasFile(page, "doc.pdf") == "composer")
        #expect(try await hasFile(page, "other.pdf") == "")
    }

    @Test func findsRenamedRepeatInComposer() async throws {
        let page = BridgePage()
        try await page.load(SyntheticChatGPT.page(attachments: SyntheticChatGPT.fileChip("doc(2).pdf")))
        #expect(try await hasFile(page, "doc.pdf") == "composer")
    }

    @Test func findsFileSentInConversation() async throws {
        let page = BridgePage()
        let sent = #"<div class="file-tile" title="doc.pdf"><span>doc.pdf</span></div>"#
        try await page.load(SyntheticChatGPT.page(messages: [SyntheticChatGPT.userMessage("about this", extra: sent)]), path: "/c/abc123")
        #expect(try await hasFile(page, "doc.pdf") == "conversation")
        #expect(try await hasFile(page, "doc.PDF") == "conversation")
        #expect(try await hasFile(page, "notes.pdf") == "")
    }

    @Test func findsRenamedRepeatInConversation() async throws {
        let page = BridgePage()
        let sent = #"<div class="file-tile" aria-label="doc(2).pdf"><span>doc(2).pdf</span></div>"#
        try await page.load(SyntheticChatGPT.page(messages: [SyntheticChatGPT.userMessage("again", extra: sent)]), path: "/c/abc123")
        #expect(try await hasFile(page, "doc.pdf") == "conversation")
    }

    @Test func similarNamesDontCount() async throws {
        let page = BridgePage()
        let sent = #"<div title="mydoc.pdf">mydoc.pdf</div><div title="doc.pdf.zip">doc.pdf.zip</div>"#
        try await page.load(SyntheticChatGPT.page(messages: [SyntheticChatGPT.userMessage("x", extra: sent)]), path: "/c/abc123")
        #expect(try await hasFile(page, "doc.pdf") == "")
    }

    @Test func sentFilesOnlyCountInsideAConversation() async throws {
        let page = BridgePage()
        let sent = #"<div title="doc.pdf">doc.pdf</div>"#
        try await page.load(SyntheticChatGPT.page(messages: [SyntheticChatGPT.userMessage("x", extra: sent)]), path: "/")
        #expect(try await hasFile(page, "doc.pdf") == "")
    }

    @Test func fileNameTypedInComposerIsNotAnAttachment() async throws {
        let page = BridgePage()
        try await page.load(SyntheticChatGPT.page(composerText: "please read doc.pdf"))
        #expect(try await hasFile(page, "doc.pdf") == "")
        #expect(try await page.string("return window.__folio.composerText()") == "please read doc.pdf")
    }

    /// Whether the new-chat offer to attach the open PDF is showing.
    func offerShows(_ page: BridgePage, _ name: String) async throws -> Bool? {
        try await page.bool("""
            window.__folio.suggestFile(name);
            await sleep(150);
            return !!document.querySelector('.folio-suggestion');
            """, ["name": name])
    }

    @Test func attachOfferShowsInNewChat() async throws {
        let page = BridgePage()
        try await page.load(SyntheticChatGPT.page())
        #expect(try await offerShows(page, "doc.pdf") == true)
    }

    @Test func attachOfferHidesOnceFileIsInComposer() async throws {
        let page = BridgePage()
        try await page.load(SyntheticChatGPT.page(attachments: SyntheticChatGPT.fileChip("doc.pdf")))
        #expect(try await offerShows(page, "doc.pdf") == false)
    }

    @Test func attachOfferHidesOnceAMessageIsSent() async throws {
        // chatgpt.com keeps the "/" address for a moment after the first message goes out.
        let page = BridgePage()
        try await page.load(SyntheticChatGPT.page(messages: [SyntheticChatGPT.userMessage("A question")]))
        #expect(try await offerShows(page, "doc.pdf") == false)
    }
}

@MainActor @Suite(.serialized) struct BridgeHealthTests {
    /// While an attachment finishes uploading after the person sends, chatgpt.com puts a disabled
    /// "File upload pending" button where the send button was. That isn't a missing send button.
    @Test func uploadPendingIsNotAMissingSendButton() async throws {
        let html = SyntheticChatGPT.page(composerText: "Explain this")
            .replacingOccurrences(
                of: #"<button type="submit" aria-label="Send" data-testid="send-button">Send</button>"#,
                with: #"<button type="submit" aria-label="File upload pending" disabled></button>"#
            )
        let page = BridgePage()
        try await page.load(html)
        // The bridge waits 1.5 s for a send button before it decides there isn't one.
        let health = try await page.string("""
            await sleep(1900);
            return JSON.stringify(await window.__folio.checkHealth());
            """)
        #expect(health == #"{"ok":true,"missing":[]}"#)
    }
}

/// The same checks against sanitized chatgpt.com captures in FolioTests/Fixtures.
@MainActor @Suite(.serialized) struct BridgeFixtureTests {
    nonisolated static var fixtures: [URL] {
        let bundle = Bundle(for: TestBundleToken.self)
        let urls = (bundle.urls(forResourcesWithExtension: "html", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "html", subdirectory: "Fixtures") ?? [])
        return Array(Set(urls.map(\.standardizedFileURL))).sorted { $0.path < $1.path }
    }

    func load(_ name: String, path: String) async throws -> BridgePage {
        let url = try #require(Self.fixtures.first { $0.deletingPathExtension().lastPathComponent == name },
                               "Fixture \(name).html isn't in the test bundle")
        let page = BridgePage()
        try await page.load(try String(contentsOf: url, encoding: .utf8), path: path)
        return page
    }

    /// One user turn sent with "example(1).pdf" and a selection, as chatgpt.com shows it.
    @Test func conversationCapture() async throws {
        let page = try await load("chatgpt-conversation", path: "/c/fixture")
        let json = try await page.string("""
            const bubble = document.querySelector('[data-user-message-bubble]');
            const view = await until(() => bubble.querySelector('.folio-message-selections'));
            const text = view?.parentElement;
            return JSON.stringify({
              views: bubble.querySelectorAll('.folio-message-selections').length,
              label: view?.querySelector('.folio-chip')?.textContent.trim() ?? null,
              quotes: [...bubble.querySelectorAll('.folio-quote-text')].map((q) => q.textContent),
              sources: [...bubble.querySelectorAll('.folio-source')].map((q) => q.textContent),
              text: text ? [...text.childNodes].filter((n) => n.nodeType === Node.TEXT_NODE).map((n) => n.nodeValue).join('') : null,
            });
            """) ?? "{}"
        let message = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
        #expect(message["views"] as? Int == 1)
        #expect(message["label"] as? String == "1 selection")
        #expect(message["quotes"] as? [String] == ["Placeholder quote"])
        #expect(message["sources"] as? [String] == ["From example, page 1"])
        #expect(message["text"] as? String == "Placeholder question")

        #expect(try await page.bool("return window.__folio.revealQuote('Placeholder quote')") == true)
        #expect(try await page.string("return await window.__folio.hasFile('example.pdf')") == "conversation")
        #expect(try await page.string("return await window.__folio.hasFile('example(1).pdf')") == "conversation")
        #expect(try await page.string("return await window.__folio.hasFile('other.pdf')") == "")
    }

    /// The new-chat composer with "example(1).pdf" attached and text typed.
    @Test func newChatCapture() async throws {
        let page = try await load("chatgpt-new-chat", path: "/")
        let probe = try await page.string("return window.__folio.probe()") ?? ""
        #expect(probe.contains(#""composer":"div#""#), "\(probe)")
        #expect(probe.contains(#""inForm":true"#), "\(probe)")
        #expect(try await page.string("return window.__folio.composerText()") == "Placeholder text")

        #expect(try await page.string("return await window.__folio.hasFile('example.pdf')") == "composer")
        #expect(try await page.string("return await window.__folio.hasFile('other.pdf')") == "")

        #expect(try await page.int("return window.__folio.addSelection('quoted', 'From doc, page 7 (whole page)', null)") == 1)
        let tray = try await page.string("""
            const tray = await until(() => document.querySelector('[class*="ComposerLayoutBody"] > .folio-tray'));
            if (!tray) return null;
            return (tray.parentElement.firstElementChild === tray ? 'first|' : 'not first|') + tray.querySelector('.folio-chip').textContent.trim();
            """)
        #expect(tray == "first|Page 7")
        // The send button the bridge waits for when it sends selections.
        #expect(try await page.bool("return !!document.querySelector('form button[type=\"submit\"][aria-label=\"Send\"]')") == true)
    }
}
