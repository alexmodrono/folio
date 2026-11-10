import AppKit
import Observation
import UniformTypeIdentifiers

/// Findle (github.com/alexmodrono/Findle) syncs Moodle courses into a File Provider folder under
/// `~/Library/CloudStorage`. Folio reads that folder as a read-only source. The two apps share no code or data:
/// Folio finds Findle by bundle identifier and folder name, and asks it to sync with a `findle://` link.
@Observable
final class Findle {
    static let shared = Findle()

    enum Status: Equatable {
        case notInstalled
        /// Installed, but no course folder yet: the user hasn't signed in or picked courses.
        case notSetUp
        case connected(URL)
    }

    private(set) var status: Status = .notInstalled
    private(set) var appURL: URL?
    /// Whether the sidebar shows the Moodle section.
    private(set) var isShown = Preferences.showMoodle

    static let pageURL = URL(string: "https://github.com/alexmodrono/Findle")!
    private static let syncURL = URL(string: "findle://sync")!
    private static let bundleIDs = ["com.amodrono.findle", "com.amodrono.findle.nightly"]
    static let cloudStorage = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/CloudStorage", isDirectory: true)

    var folderURL: URL? {
        if case .connected(let url) = status { return url }
        return nil
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            // Installing and setting up Findle happens in other apps, so check again on return.
            MainActor.assumeIsolated { Findle.shared.refresh() }
        }
    }

    func refresh() {
        let workspace = NSWorkspace.shared
        var app = Self.bundleIDs.lazy.compactMap { workspace.urlForApplication(withBundleIdentifier: $0) }.first
        var folder = Self.chosenFolder() ?? Self.foundFolders().first
        #if DEBUG
        // FOLIO_FINDLE=missing or =setup previews the other states without uninstalling Findle.
        switch ProcessInfo.processInfo.environment["FOLIO_FINDLE"] {
        case "missing": (app, folder) = (nil, nil)
        case "setup": folder = nil
        default: break
        }
        #endif
        if app != appURL { appURL = app }

        let newStatus: Status = folder.map { .connected($0) } ?? (app == nil ? .notInstalled : .notSetUp)
        if newStatus != status { status = newStatus }
        LibraryStore.shared.setMoodleRoot(isShown ? folder : nil)
    }

    // MARK: Actions

    func getApp() {
        NSWorkspace.shared.open(Self.pageURL)
    }

    func openApp() {
        guard let appURL else { return getApp() }
        NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
    }

    /// Asks Findle to sync in the background. New files arrive through the folder watcher.
    func sync() {
        guard let appURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open([Self.syncURL], withApplicationAt: appURL, configuration: configuration)
    }

    func setShown(_ shown: Bool) {
        isShown = shown
        Preferences.showMoodle = shown
        refresh()
    }

    func choose(_ url: URL) {
        Preferences.moodlePath = url.standardizedFileURL.path
        refresh()
    }

    // MARK: Folders

    private static func chosenFolder() -> URL? {
        guard let path = Preferences.moodlePath else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    /// Findle's folders, one per Moodle site, release builds before Nightly.
    private static func foundFolders() -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: cloudStorage, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        )) ?? []
        return entries
            .filter { $0.lastPathComponent.hasPrefix("Findle-") || $0.lastPathComponent.hasPrefix("FindleNightly-") }
            .map(\.standardizedFileURL)
            .sorted { a, b in
                let aNightly = a.lastPathComponent.hasPrefix("FindleNightly-")
                let bNightly = b.lastPathComponent.hasPrefix("FindleNightly-")
                if aNightly != bNightly { return !aNightly }
                return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            }
    }

    /// The Findle icon: the installed app's, or the copy bundled with Folio.
    var icon: NSImage {
        if let appURL { return NSWorkspace.shared.icon(forFile: appURL.path) }
        return NSImage(named: "Findle") ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
