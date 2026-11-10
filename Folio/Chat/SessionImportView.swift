import SwiftUI
import WebKit

extension ChatGPTSession {
    /// True when Folio's own web data holds a ChatGPT session that hasn't expired.
    static func hasSignIn() async -> Bool {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return cookies.contains { cookie in
            cookie.name.hasPrefix("__Secure-next-auth.session-token")
                && BrowserSessions.isChatGPTHost(cookie.domain)
                && (cookie.expiresDate.map { $0 > .now } ?? true)
        }
    }

    /// Replaces Folio's ChatGPT cookies with the browser's, reloads the panel, and checks with chatgpt.com
    /// that the session still works. A session the browser hasn't used in a while can be past refreshing;
    /// then the import is undone so the panel shows the normal sign-in.
    static func importSignIn(from session: BrowserSession) async throws {
        let cookies = try await Task.detached { try BrowserSessions.cookies(for: session) }.value
        await removeChatGPTCookies()
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in cookies {
            if let httpCookie = cookie.httpCookie { await store.setCookie(httpCookie) }
        }
        NSLog("Folio: imported \(cookies.count) ChatGPT cookies from \(session.browserName)")

        for card in all { card.reload() }
        let valid = await active.isSessionValid()
        NSLog("Folio: imported session valid: \(valid.map(String.init(describing:)) ?? "unknown")")
        if valid == false {
            await removeChatGPTCookies()
            for card in all { card.reload() }
            throw SessionImportError.expired(session.browserName)
        }
    }

    /// Clears ChatGPT and OpenAI sign-in cookies, keeping Cloudflare's bot-check cookies.
    private static func removeChatGPTCookies() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in await store.allCookies()
        where BrowserSessions.isChatGPTHost(cookie.domain) && !BrowserSessions.skippedNames.contains(cookie.name) {
            await store.deleteCookie(cookie)
        }
    }

    /// Asks chatgpt.com for the current session once the page has loaded. Nil if it couldn't tell.
    private func isSessionValid() async -> Bool? {
        let script = """
            const response = await fetch('/api/auth/session', {credentials: 'include'});
            if (!response.ok) return 'unknown';
            const session = await response.json();
            return session.user && !session.error ? 'valid' : 'invalid';
            """
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(500))
            guard !webView.isLoading, webView.url?.host?.hasSuffix("chatgpt.com") == true else { continue }
            let result = try? await webView.callAsyncJavaScript(
                script, arguments: [:], in: nil, contentWorld: .world(name: "Folio")
            ) as? String
            switch result {
            case "valid": return true
            case "invalid": return false
            default: continue
            }
        }
        return nil
    }
}

@Observable
final class SessionImportModel {
    /// Nil while browsers are being checked.
    var sessions: [BrowserSession]?
    var selection: BrowserSession.ID?
    var isImporting = false
    var error: String?

    init(sessions: [BrowserSession]? = nil) {
        self.sessions = sessions
        selection = sessions?.first?.id
    }

    var selected: BrowserSession? { sessions?.first { $0.id == selection } }

    func load() async {
        let found = await Task.detached { BrowserSessions.find() }.value
        sessions = found
        if selected == nil { selection = found.first?.id }
    }

    func importSelected() async -> Bool {
        guard let session = selected else { return false }
        isImporting = true
        error = nil
        defer { isImporting = false }
        do {
            try await ChatGPTSession.importSignIn(from: session)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

/// Offers to copy the ChatGPT sign-in from an installed browser. Shown in the chat panel on first use
/// and from Settings.
struct SessionImportView: View {
    enum Style { case panel, sheet }

    @State private var model: SessionImportModel
    private let style: Style
    private let onFinish: (_ imported: Bool) -> Void

    init(model: SessionImportModel, style: Style, onFinish: @escaping (_ imported: Bool) -> Void) {
        _model = State(initialValue: model)
        self.style = style
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Already signed in to ChatGPT?")
                    .font(.title3.weight(.semibold))
                Text("Folio can copy your ChatGPT sign-in from a browser. Nothing else is copied.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let sessions = model.sessions {
                if sessions.isEmpty {
                    Text("No browser is signed in to ChatGPT.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: Theme.Space.xs) {
                        ForEach(sessions) { row(for: $0) }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }

            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            buttons
        }
        .padding(style == .sheet ? Theme.Space.xl : Theme.Space.l)
        .frame(width: style == .sheet ? 420 : nil)
        .frame(maxWidth: style == .panel ? 360 : nil)
        .task {
            if model.sessions == nil { await model.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Coming back from System Settings may have granted Full Disk Access.
            Task { await model.load() }
        }
    }

    private var note: String? {
        guard let session = model.selected else { return nil }
        if !session.isReadable { return "Folio needs Full Disk Access to read Safari's sign-in." }
        if let item = session.keychainItem {
            return "Your Mac will ask for your password to let Folio use “\(item)”."
        }
        return nil
    }

    @ViewBuilder
    private var buttons: some View {
        let dismissTitle = style == .panel ? "Sign In Manually" : "Cancel"
        switch style {
        case .panel:
            VStack(spacing: Theme.Space.s) {
                primaryButton
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button(dismissTitle) { onFinish(false) }
                    .buttonStyle(.link)
            }
            .frame(maxWidth: .infinity)
        case .sheet:
            HStack {
                Spacer()
                Button(dismissTitle, role: .cancel) { onFinish(false) }
                    .keyboardShortcut(.cancelAction)
                primaryButton
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if let session = model.selected, !session.isReadable {
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            .keyboardShortcut(.defaultAction)
        } else {
            Button {
                Task {
                    if await model.importSelected() { onFinish(true) }
                }
            } label: {
                Text(model.selected.map { "Continue with \($0.browserName)" } ?? "Continue")
                    .frame(maxWidth: style == .panel ? .infinity : nil)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.selected == nil || model.isImporting)
        }
    }

    private func row(for session: BrowserSession) -> some View {
        let isSelected = session.id == model.selection
        let detail = session.isReadable ? Self.detail(for: session) : "Needs Full Disk Access"
        return Button {
            model.selection = session.id
            model.error = nil
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(nsImage: Self.icon(for: session.bundleIdentifier))
                    .resizable()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.browserName)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .padding(Theme.Space.s)
            .contentShape(Rectangle())
            .background(
                isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: Theme.pillRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Profile name and when the browser last used its ChatGPT session, which hints at whether it still works.
    private static func detail(for session: BrowserSession) -> String? {
        let used = session.lastUsed.map { date in
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Used " + formatter.localizedString(for: date, relativeTo: .now)
        }
        let parts = [session.profileName, used].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func icon(for bundleIdentifier: String) -> NSImage {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return NSWorkspace.shared.icon(forFile: app.path)
    }
}
