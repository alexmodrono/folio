import AppKit

/// Looks for a newer Folio on the GitHub repository named by `FolioUpdateRepository` in Info.plist.
/// It only tells the person and links to the release page; it never downloads or installs anything.
enum UpdateChecker {
    nonisolated struct Release: Decodable, Sendable {
        let tagName: String
        let htmlURL: URL
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
        }

        var version: String {
            tagName.hasPrefix("v") || tagName.hasPrefix("V") ? String(tagName.dropFirst()) : tagName
        }
    }

    enum Failure: LocalizedError {
        case noRepository
        case status(Int)

        var errorDescription: String? {
            switch self {
            case .noRepository: String(localized: "No update source is set.")
            case .status(404): String(localized: "No release was found.")
            case .status(let code): String(localized: "The server answered with status \(code).", comment: "HTTP status code")
            }
        }
    }

    /// "owner/name", from Info.plist.
    static var repository: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "FolioUpdateRepository") as? String
        let trimmed = value?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    private static var isChecking = false

    /// Checks at most once a day, when the setting is on. Says nothing unless there's a version it hasn't announced.
    static func checkAutomaticallyIfDue() {
        guard Preferences.checkForUpdates, !isChecking else { return }
        if let last = Preferences.lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 60 * 60 { return }
        Task {
            guard let release = try? await fetchLatest() else { return }
            Preferences.lastUpdateCheck = Date()
            guard isNewer(release.version, than: currentVersion),
                  Preferences.lastAnnouncedVersion != release.version else { return }
            Preferences.lastAnnouncedVersion = release.version
            showAvailable(release)
        }
    }

    /// The "Check for Updates…" command: always says what it found.
    static func checkNow() {
        guard !isChecking else { return }
        Task {
            do {
                let release = try await fetchLatest()
                Preferences.lastUpdateCheck = Date()
                if isNewer(release.version, than: currentVersion) {
                    Preferences.lastAnnouncedVersion = release.version
                    showAvailable(release)
                } else {
                    let alert = NSAlert()
                    alert.messageText = String(localized: "You’re up to date.")
                    alert.informativeText = String(localized: "Folio \(currentVersion) is the latest version.")
                    present(alert) { _ in }
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = String(localized: "Couldn’t check for updates.")
                alert.informativeText = error.localizedDescription
                present(alert) { _ in }
            }
        }
    }

    static func fetchLatest() async throws -> Release {
        guard let repository,
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw Failure.noRepository
        }
        isChecking = true
        defer { isChecking = false }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Folio/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.status(status) }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    /// Compares dotted versions number by number, so "1.10" is newer than "1.9". Missing parts count as 0.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The leading number of each dotted part: "1.2.3-beta" is [1, 2, 3].
    nonisolated private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    private static func showAvailable(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Folio \(release.version) is available.")
        alert.informativeText = notes(release.body)
        alert.addButton(withTitle: String(localized: "Download"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        present(alert) { response in
            if response == .alertFirstButtonReturn { NSWorkspace.shared.open(release.htmlURL) }
        }
    }

    /// The start of the release notes, without Markdown heading marks.
    private static func notes(_ body: String?) -> String {
        let lines = (body ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces)) }
            .filter { !$0.isEmpty }
        var text = lines.prefix(8).joined(separator: "\n")
        if text.count > 400 { text = String(text.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines) + "…" }
        else if lines.count > 8 { text += "\n…" }
        return text
    }

    /// As a sheet on the main window when there is one, otherwise as its own window.
    private static func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
           window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            NSApp.activate()
            completion(alert.runModal())
        }
    }
}
