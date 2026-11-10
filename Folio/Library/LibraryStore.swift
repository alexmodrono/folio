import AppKit
import Observation

enum LibrarySort: String, CaseIterable, Identifiable {
    case name, modified, added

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: String(localized: "Name", comment: "Sort order")
        case .modified: String(localized: "Date Modified")
        case .added: String(localized: "Date Added")
        }
    }
}

/// A folder or PDF in the library. Nodes are rebuilt on every reload, so compare them by `url`, not identity.
final class LibraryNode: Identifiable {
    let url: URL
    let isFolder: Bool
    let modified: Date
    let added: Date
    /// Findle's files: Folio reads them but never renames, moves or deletes them.
    let isReadOnly: Bool
    /// A File Provider placeholder. Reading it downloads it, so don't open it just to draw a thumbnail.
    let isPlaceholder: Bool
    fileprivate(set) var children: [LibraryNode] = []
    fileprivate(set) weak var parent: LibraryNode?

    var id: String { url.path }

    var name: String {
        isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }

    /// Every PDF below this folder, depth first.
    var allDocuments: [LibraryNode] {
        children.flatMap { $0.isFolder ? $0.allDocuments : [$0] }
    }

    fileprivate init(_ item: ScannedItem, isReadOnly: Bool) {
        url = item.url
        isFolder = item.isFolder
        modified = item.modified
        added = item.added
        isPlaceholder = item.isPlaceholder
        self.isReadOnly = isReadOnly
    }
}

/// What a scan finds on disk. Plain values, so a scan can run off the main actor.
nonisolated struct ScannedItem: Sendable {
    let url: URL
    let isFolder: Bool
    let modified: Date
    let added: Date
    let isPlaceholder: Bool
    var children: [ScannedItem] = []

    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .contentModificationDateKey, .addedToDirectoryDateKey, .creationDateKey,
        .ubiquitousItemDownloadingStatusKey,
    ]

    /// Scans `url` for PDFs and folders. With `pruneEmpty`, folders holding no PDFs at any depth are left out.
    static func scan(_ url: URL, pruneEmpty: Bool) -> ScannedItem {
        var root = item(url, values: try? url.resourceValues(forKeys: keys), isFolder: true)
        root.children = children(of: url, pruneEmpty: pruneEmpty)
        return root
    }

    private static func children(of url: URL, pruneEmpty: Bool) -> [ScannedItem] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []
        var result: [ScannedItem] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: keys)
            if values?.isDirectory == true, values?.isPackage != true {
                var folder = item(entry, values: values, isFolder: true)
                folder.children = children(of: entry, pruneEmpty: pruneEmpty)
                if !pruneEmpty || !folder.children.isEmpty { result.append(folder) }
            } else if entry.pathExtension.lowercased() == "pdf" {
                result.append(item(entry, values: values, isFolder: false))
            }
        }
        return result
    }

    private static func item(_ url: URL, values: URLResourceValues?, isFolder: Bool) -> ScannedItem {
        ScannedItem(
            url: url.standardizedFileURL,
            isFolder: isFolder,
            modified: values?.contentModificationDate ?? .distantPast,
            added: values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast,
            isPlaceholder: !isFolder && values?.ubiquitousItemDownloadingStatus == .notDownloaded
        )
    }
}

/// The library is a plain folder of PDFs and subfolders. This store mirrors it and performs file operations.
/// When Findle is set up, it also mirrors Findle's course folder, read-only, as `moodleRoot`.
@Observable
final class LibraryStore {
    static let shared = LibraryStore()

    private(set) var rootURL: URL
    private(set) var root: LibraryNode
    private(set) var favorites: Set<String>
    /// Findle's course folder. Nil when Findle isn't set up or the Moodle section is hidden.
    private(set) var moodleRoot: LibraryNode?

    var sort: LibrarySort {
        didSet {
            Preferences.sortOrder = sort.rawValue
            reload()
            reloadMoodle()
        }
    }

    @ObservationIgnored private var index: [String: LibraryNode] = [:]
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var moodleURL: URL?
    @ObservationIgnored private var moodleIndex: [String: LibraryNode] = [:]
    @ObservationIgnored private var moodleWatcher: DirectoryWatcher?
    @ObservationIgnored private var moodleScan = 0
    @ObservationIgnored private let files = FileManager.default

    static var defaultRootURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Folio", isDirectory: true)
    }

    private init() {
        let url = Preferences.libraryPath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.defaultRootURL
        rootURL = url.standardizedFileURL
        root = LibraryNode(
            ScannedItem(url: url, isFolder: true, modified: .distantPast, added: .distantPast, isPlaceholder: false),
            isReadOnly: false
        )
        favorites = Set(Preferences.favorites)
        sort = LibrarySort(rawValue: Preferences.sortOrder ?? "") ?? .name
        try? files.createDirectory(at: rootURL, withIntermediateDirectories: true)
        reload()
        watch()
    }

    // MARK: Reading

    func reload() {
        var newIndex: [String: LibraryNode] = [:]
        root = build(ScannedItem.scan(rootURL, pruneEmpty: false), parent: nil, isReadOnly: false, into: &newIndex)
        index = newIndex
    }

    /// Rescans Findle's folder in the background. Listing a File Provider folder can wait on Findle.
    func reloadMoodle() {
        moodleScan += 1
        let scan = moodleScan
        guard let url = moodleURL else {
            moodleRoot = nil
            moodleIndex = [:]
            return
        }
        Task {
            let item = await Task.detached(priority: .userInitiated) { ScannedItem.scan(url, pruneEmpty: true) }.value
            guard scan == self.moodleScan else { return }
            var newIndex: [String: LibraryNode] = [:]
            self.moodleRoot = self.build(item, parent: nil, isReadOnly: true, into: &newIndex)
            self.moodleIndex = newIndex
        }
    }

    func setMoodleRoot(_ url: URL?) {
        let url = url?.standardizedFileURL
        guard url != moodleURL else { return }
        moodleURL = url
        moodleWatcher?.stop()
        moodleWatcher = url.map { DirectoryWatcher(url: $0) { [weak self] in self?.reloadMoodle() } }
        reloadMoodle()
    }

    func node(at url: URL) -> LibraryNode? {
        let path = url.standardizedFileURL.path
        return index[path] ?? moodleIndex[path]
    }

    /// Whether `url` is inside the user's own library folder.
    func contains(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(rootURL.path + "/")
    }

    /// Whether `url` is in Findle's folder, which Folio must not change.
    func isReadOnly(_ url: URL) -> Bool {
        guard let moodleURL else { return false }
        let path = url.standardizedFileURL.path
        return path == moodleURL.path || path.hasPrefix(moodleURL.path + "/")
    }

    func isFavorite(_ url: URL) -> Bool {
        favorites.contains(favoriteKey(url))
    }

    var favoriteDocuments: [LibraryNode] {
        (root.allDocuments + (moodleRoot?.allDocuments ?? [])).filter { favorites.contains(favoriteKey($0.url)) }
    }

    // MARK: Writing

    func toggleFavorite(_ url: URL) {
        let key = favoriteKey(url)
        if favorites.contains(key) { favorites.remove(key) } else { favorites.insert(key) }
        Preferences.favorites = Array(favorites)
    }

    /// Copies PDFs into `folder` (the root when nil). Files already in that folder are skipped.
    @discardableResult
    func importFiles(_ urls: [URL], into folder: URL?) -> [URL] {
        let destination = folder ?? rootURL
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        // Findle's files may be placeholders and carry its locked flags, so they take the copy path below.
        copyToLibrary(pdfs.filter(isReadOnly), into: folder)
        var imported: [URL] = []
        for url in pdfs where !isReadOnly(url) {
            if url.deletingLastPathComponent().standardizedFileURL.path == destination.standardizedFileURL.path { continue }
            let target = uniqueURL(for: url.lastPathComponent, in: destination)
            do {
                try files.copyItem(at: url, to: target)
                imported.append(target)
            } catch {
                NSLog("Folio: import failed for \(url.path): \(error.localizedDescription)")
            }
        }
        reload()
        return imported
    }

    /// Copies Findle's files into the library, downloading them first. Runs in the background because a
    /// download can take a while; the library reloads when it's done.
    func copyToLibrary(_ urls: [URL], into folder: URL?) {
        guard !urls.isEmpty else { return }
        var used = Set<String>()
        let pairs = urls.map { url in
            let target = uniqueURL(for: url.lastPathComponent, in: folder ?? rootURL, excluding: used)
            used.insert(target.path)
            return (url, target)
        }
        Task {
            await Task.detached(priority: .userInitiated) {
                for (source, target) in pairs {
                    do {
                        // Write the bytes rather than copying the file, so the copy doesn't keep Findle's
                        // read-only permissions and immutable flag.
                        let data = try LibraryStore.coordinatedRead(source)
                        try data.write(to: target, options: .withoutOverwriting)
                    } catch {
                        NSLog("Folio: copy failed for \(source.path): \(error.localizedDescription)")
                    }
                }
            }.value
            self.reload()
        }
    }

    /// Downloads placeholders without opening them. The folder watcher then picks up the new thumbnails.
    func download(_ urls: [URL]) {
        Task.detached(priority: .utility) {
            for url in urls { _ = try? LibraryStore.coordinatedRead(url, readsData: false) }
        }
    }

    /// Reads `url` through a file coordinator, which makes a File Provider download it first.
    nonisolated static func coordinatedRead(_ url: URL, readsData: Bool = true) throws -> Data {
        var coordinatorError: NSError?
        var result: Result<Data, Error> = .success(Data())
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            if readsData { result = Result { try Data(contentsOf: readURL) } }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }

    func createFolder(in folder: URL?) -> URL? {
        if let folder, isReadOnly(folder) { return nil }
        let url = uniqueURL(for: String(localized: "New Folder"), in: folder ?? rootURL)
        do {
            try files.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            NSLog("Folio: could not create folder: \(error.localizedDescription)")
            return nil
        }
        reload()
        return url
    }

    @discardableResult
    func rename(_ url: URL, to newName: String) throws -> URL {
        guard !isReadOnly(url) else { return url }
        let isFolder = node(at: url)?.isFolder ?? url.hasDirectoryPath
        let clean = newName.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return url }
        let fileName = isFolder ? clean : clean + "." + url.pathExtension
        let target = url.deletingLastPathComponent().appendingPathComponent(fileName, isDirectory: isFolder)
        guard target.path != url.path else { return url }
        try files.moveItem(at: url, to: target)
        moveFavorites(from: url, to: target)
        QuestionStore.shared.moveDocuments(from: url, to: target)
        reload()
        return target
    }

    func trash(_ urls: [URL]) {
        for url in urls where !isReadOnly(url) {
            do {
                try files.trashItem(at: url, resultingItemURL: nil)
                QuestionStore.shared.removeDocuments(under: url)
                let key = relativePath(url)
                favorites = favorites.filter { $0 != key && !$0.hasPrefix(key + "/") }
            } catch {
                NSLog("Folio: could not move \(url.path) to the Trash: \(error.localizedDescription)")
            }
        }
        Preferences.favorites = Array(favorites)
        reload()
    }

    func move(_ urls: [URL], to folder: URL) {
        let destination = folder.standardizedFileURL
        if isReadOnly(destination) { return }
        copyToLibrary(urls.filter(isReadOnly), into: destination)
        for url in urls where !isReadOnly(url) {
            let source = url.standardizedFileURL
            // A folder can't move into itself or its own subfolder, and moving in place is a no-op.
            if destination.path == source.path || destination.path.hasPrefix(source.path + "/") { continue }
            if source.deletingLastPathComponent().path == destination.path { continue }
            let target = uniqueURL(for: source.lastPathComponent, in: destination)
            do {
                try files.moveItem(at: source, to: target)
                moveFavorites(from: source, to: target)
                QuestionStore.shared.moveDocuments(from: source, to: target)
            } catch {
                NSLog("Folio: move failed for \(source.path): \(error.localizedDescription)")
            }
        }
        reload()
    }

    func setRoot(_ url: URL) {
        rootURL = url.standardizedFileURL
        Preferences.libraryPath = rootURL.path
        try? files.createDirectory(at: rootURL, withIntermediateDirectories: true)
        reload()
        watch()
    }

    // MARK: Private

    private func build(_ item: ScannedItem, parent: LibraryNode?, isReadOnly: Bool, into index: inout [String: LibraryNode]) -> LibraryNode {
        let node = LibraryNode(item, isReadOnly: isReadOnly)
        node.parent = parent
        index[node.id] = node
        node.children = sorted(item.children.map { build($0, parent: node, isReadOnly: isReadOnly, into: &index) })
        return node
    }

    private func sorted(_ nodes: [LibraryNode]) -> [LibraryNode] {
        nodes.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            switch sort {
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .modified: return a.modified > b.modified
            case .added: return a.added > b.added
            }
        }
    }

    private func relativePath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let prefix = rootURL.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    /// Library favorites are keyed by path in the library; Findle's by path in its folder, with a prefix,
    /// so they survive switching between Findle and Findle Nightly.
    private func favoriteKey(_ url: URL) -> String {
        if let moodleURL, isReadOnly(url) {
            return "moodle:" + String(url.standardizedFileURL.path.dropFirst(moodleURL.path.count + 1))
        }
        return relativePath(url)
    }

    private func moveFavorites(from old: URL, to new: URL) {
        let oldKey = relativePath(old)
        let newKey = relativePath(new)
        favorites = Set(favorites.map { key in
            if key == oldKey { return newKey }
            if key.hasPrefix(oldKey + "/") { return newKey + key.dropFirst(oldKey.count) }
            return key
        })
        Preferences.favorites = Array(favorites)
    }

    private func uniqueURL(for name: String, in folder: URL, excluding taken: Set<String> = []) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var counter = 2
        while files.fileExists(atPath: candidate.path) || taken.contains(candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    private func watch() {
        watcher?.stop()
        watcher = DirectoryWatcher(url: rootURL) { [weak self] in self?.reload() }
    }
}
