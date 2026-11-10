import Foundation

/// Typed access to UserDefaults. Keys match the `@AppStorage` keys used in SwiftUI views.
enum Preferences {
    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            // Off: chatgpt.com uploads a file as soon as it's in the composer, so opening a PDF shouldn't.
            "autoAttach": false,
            "attachOnAsk": true,
            "showQuestionBubbles": true,
            "displayMode": 1,
            "showMoodle": true,
            "checkForUpdates": true,
        ])
    }

    static var libraryPath: String? {
        get { defaults.string(forKey: "libraryPath") }
        set { defaults.set(newValue, forKey: "libraryPath") }
    }

    /// Shows the Moodle section in the sidebar: Findle's courses, or a row suggesting Findle.
    static var showMoodle: Bool {
        get { defaults.bool(forKey: "showMoodle") }
        set { defaults.set(newValue, forKey: "showMoodle") }
    }

    /// A Findle folder the user picked. Nil uses the first one found.
    static var moodlePath: String? {
        get { defaults.string(forKey: "moodlePath") }
        set { defaults.set(newValue, forKey: "moodlePath") }
    }

    /// Whether asking about a selection or a page also attaches the whole PDF.
    static var attachOnAsk: Bool {
        get { defaults.bool(forKey: "attachOnAsk") }
        set { defaults.set(newValue, forKey: "attachOnAsk") }
    }

    static var autoAttach: Bool {
        get { defaults.bool(forKey: "autoAttach") }
        set { defaults.set(newValue, forKey: "autoAttach") }
    }

    static var favorites: [String] {
        get { defaults.stringArray(forKey: "favorites") ?? [] }
        set { defaults.set(newValue, forKey: "favorites") }
    }

    static var sortOrder: String? {
        get { defaults.string(forKey: "sortOrder") }
        set { defaults.set(newValue, forKey: "sortOrder") }
    }

    static var homeLayout: String? {
        get { defaults.string(forKey: "homeLayout") }
        set { defaults.set(newValue, forKey: "homeLayout") }
    }

    static var expandedFolders: [String] {
        get { defaults.stringArray(forKey: "expandedFolders") ?? [] }
        set { defaults.set(newValue, forKey: "expandedFolders") }
    }

    /// Bubbles on PDF pages where the person asked ChatGPT something.
    static var showQuestionBubbles: Bool {
        get { defaults.bool(forKey: "showQuestionBubbles") }
        set {
            defaults.set(newValue, forKey: "showQuestionBubbles")
            NotificationCenter.default.post(name: QuestionStore.didChange, object: nil)
        }
    }

    /// Looks for a newer release on GitHub at most once a day.
    static var checkForUpdates: Bool {
        get { defaults.bool(forKey: "checkForUpdates") }
        set { defaults.set(newValue, forKey: "checkForUpdates") }
    }

    static var lastUpdateCheck: Date? {
        get { defaults.object(forKey: "lastUpdateCheck") as? Date }
        set { defaults.set(newValue, forKey: "lastUpdateCheck") }
    }

    /// The newest version already offered automatically, so each one is offered once.
    static var lastAnnouncedVersion: String? {
        get { defaults.string(forKey: "lastAnnouncedVersion") }
        set { defaults.set(newValue, forKey: "lastAnnouncedVersion") }
    }

    static var showThumbnails: Bool {
        get { defaults.bool(forKey: "showThumbnails") }
        set { defaults.set(newValue, forKey: "showThumbnails") }
    }

    /// Set when the user chose to sign in to ChatGPT themselves instead of importing a browser's sign-in.
    static var declinedSessionImport: Bool {
        get { defaults.bool(forKey: "declinedSessionImport") }
        set { defaults.set(newValue, forKey: "declinedSessionImport") }
    }

    /// The path of each chat card's conversation, top to bottom ("/" for a new chat).
    static var chatCards: [String] {
        get { defaults.stringArray(forKey: "chatCards") ?? [] }
        set { defaults.set(newValue, forKey: "chatCards") }
    }

    /// Chat cards in columns instead of rows.
    static var chatSideBySide: Bool {
        get { defaults.bool(forKey: "chatSideBySide") }
        set { defaults.set(newValue, forKey: "chatSideBySide") }
    }

    /// The PDFs (file paths) each chatgpt.com conversation already has, keyed by conversation path.
    static var attachedFiles: [String: [String]] {
        get { defaults.dictionary(forKey: "attachedFiles") as? [String: [String]] ?? [:] }
        set { defaults.set(newValue, forKey: "attachedFiles") }
    }

    static var chatVisible: Bool {
        get { defaults.bool(forKey: "chatVisible") }
        set { defaults.set(newValue, forKey: "chatVisible") }
    }

    /// With two pages, shows the first page on its own, like a book's cover.
    static var bookMode: Bool {
        get { defaults.bool(forKey: "bookMode") }
        set { defaults.set(newValue, forKey: "bookMode") }
    }

    /// 0 single page, 1 continuous, 2 two pages.
    static var displayMode: Int {
        get { defaults.integer(forKey: "displayMode") }
        set { defaults.set(newValue, forKey: "displayMode") }
    }

    struct ReadingPosition {
        var page: Int
        var scale: Double
        var autoScales: Bool
    }

    static func readingPosition(for url: URL) -> ReadingPosition? {
        guard let all = defaults.dictionary(forKey: "positions"),
              let entry = all[url.standardizedFileURL.path] as? [String: Any],
              let page = entry["page"] as? Int else { return nil }
        return ReadingPosition(
            page: page,
            scale: entry["scale"] as? Double ?? 1,
            autoScales: entry["auto"] as? Bool ?? true
        )
    }

    static func setReadingPosition(_ position: ReadingPosition, for url: URL) {
        var all = defaults.dictionary(forKey: "positions") ?? [:]
        all[url.standardizedFileURL.path] = ["page": position.page, "scale": position.scale, "auto": position.autoScales]
        // Keep the dictionary from growing without bound.
        if all.count > 500, let stale = all.keys.first(where: { !FileManager.default.fileExists(atPath: $0) }) {
            all.removeValue(forKey: stale)
        }
        defaults.set(all, forKey: "positions")
    }
}
