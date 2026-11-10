import AppKit
import Observation

enum HomeTab {
    case all, favorites
}

enum HomeLayout: String {
    case grid, list
}

/// State for the Home view, owned by the window controller.
@Observable
final class HomeModel {
    /// The folder being shown. Nil means the library root.
    var folderURL: URL?
    var tab: HomeTab = .all
    var query = ""
    var layout: HomeLayout = HomeLayout(rawValue: Preferences.homeLayout ?? "") ?? .grid {
        didSet { Preferences.homeLayout = layout.rawValue }
    }

    @ObservationIgnored var open: (URL) -> Void = { _ in }
    @ObservationIgnored var importDocuments: () -> Void = {}
    @ObservationIgnored var newFolder: () -> Void = {}
}
