import AppKit
import OSLog
import WebKit

/// Builds a GitHub "new issue" link with what helps diagnose a problem, for the person to read and send.
/// Nothing is sent by Folio; the browser shows the draft first.
enum ProblemReport {
    private static let maxURLLength = 7000
    nonisolated private static let maxLogLines = 40

    /// "owner/name", from `FolioRepository` in Info.plist.
    static var repository: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "FolioRepository") as? String
        let trimmed = value?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static func open() {
        guard let repository else {
            NSSound.beep()
            return
        }
        Task {
            let probe = await bridgeProbe()
            let logs = await Task.detached(priority: .userInitiated) { recentLogLines() }.value
            guard let url = issueURL(repository: repository, probe: probe, logs: logs) else {
                NSSound.beep()
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Contents

    /// What the bridge sees in the active card, when the chat panel has been opened.
    private static func bridgeProbe() async -> String? {
        guard ChatGPTSession.isLoaded else { return nil }
        let result = try? await ChatGPTSession.active.webView.callAsyncJavaScript(
            "return window.__folio ? window.__folio.probe() : 'no bridge'",
            arguments: [:], in: nil, contentWorld: .world(name: "Folio")
        )
        guard let result else { return "unavailable" }
        if let string = result as? String { return string }
        if JSONSerialization.isValidJSONObject(result),
           let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
            return String(decoding: data, as: UTF8.self)
        }
        return String(describing: result)
    }

    /// The last Folio messages this process logged in the past 30 minutes.
    nonisolated private static func recentLogLines() -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }
        let position = store.position(date: Date().addingTimeInterval(-30 * 60))
        guard let entries = try? store.getEntries(at: position) else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        var lines: [String] = []
        for entry in entries {
            guard let log = entry as? OSLogEntryLog, log.composedMessage.contains("Folio") else { continue }
            lines.append("\(formatter.string(from: log.date)) \(log.composedMessage)")
            if lines.count > maxLogLines { lines.removeFirst() }
        }
        return lines
    }

    private static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static var chatCardCount: Int {
        ChatGPTSession.isLoaded ? ChatGPTSession.all.count : Preferences.chatCards.count
    }

    private static func body(probe: String?, logs: [String]) -> String {
        var text = """
        **What happened?**


        ---
        - Folio \(version) (\(build))
        - macOS \(systemVersion)
        - Chat cards: \(chatCardCount)
        """
        if let probe {
            text += "\n\n**Bridge**\n```\n\(probe)\n```"
        }
        if !logs.isEmpty {
            text += "\n\n**Log**\n```\n\(logs.joined(separator: "\n"))\n```"
        }
        return text
    }

    /// The new-issue link, dropping the oldest log lines (then shortening the probe) until it fits.
    private static func issueURL(repository: String, probe: String?, logs: [String]) -> URL? {
        var logs = logs
        var probe = probe
        while true {
            if let url = makeURL(repository: repository, body: body(probe: probe, logs: logs)),
               url.absoluteString.count <= maxURLLength {
                return url
            }
            if !logs.isEmpty {
                logs.removeFirst()
            } else if let current = probe, current.count > 200 {
                probe = String(current.prefix(current.count / 2)) + "…"
            } else {
                return makeURL(repository: repository, body: body(probe: nil, logs: []))
            }
        }
    }

    private static func makeURL(repository: String, body: String) -> URL? {
        var components = URLComponents(string: "https://github.com/\(repository)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: ""),
            URLQueryItem(name: "body", value: body),
        ]
        // URLComponents leaves "+" alone, which a form decoder would read as a space.
        let query = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = query
        return components?.url
    }
}
