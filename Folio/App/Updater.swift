import AppKit
@preconcurrency import Sparkle

/// Updates through Sparkle. It reads the appcast named by `SUFeedURL` in Info.plist once a day (when the
/// setting is on), shows what's new, and installs an update only after the person accepts it. Updates must be
/// signed with the EdDSA key whose public half is `SUPublicEDKey`.
///
/// Debug builds and the test host never start the updater, so a development build can't replace itself.
enum Updater {
    private static let controller: SPUStandardUpdaterController = {
        #if DEBUG
        let start = false
        #else
        let start = !AppDelegate.isHostingTests
        #endif
        return SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    /// Starts the updater; it schedules its own checks from here on.
    static func start() {
        _ = controller
    }

    /// The "Check for Updates…" command: always says what it found.
    static func checkNow() {
        controller.checkForUpdates(nil)
    }

    /// False in Debug builds and while a check is already running.
    static var canCheck: Bool {
        controller.updater.canCheckForUpdates
    }

    static var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
