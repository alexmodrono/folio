import AppKit
import UniformTypeIdentifiers

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    private var windowController: MainWindowController?
    private var settingsController: SettingsWindowController?
    private var pendingURLs: [URL] = []

    /// True while the app is only hosting unit tests: no windows, no web views, no debug commands.
    static let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        if Self.isHostingTests { return }
        #if DEBUG
        DebugHooks.install()
        #endif
        NSApp.mainMenu = MainMenu.build()
        Findle.shared.refresh()
        let controller = MainWindowController()
        windowController = controller
        controller.showWindow(nil)
        pendingURLs.forEach(controller.open)
        pendingURLs = []
        Updater.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return }
        if let windowController { windowController.open(url) } else { pendingURLs = [url] }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windowController?.showWindow(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc func showSettings(_ sender: Any?) {
        let controller = settingsController ?? SettingsWindowController()
        settingsController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        windowController?.open(url)
    }

    @objc func showMainWindow(_ sender: Any?) {
        windowController?.showWindow(nil)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        Updater.checkNow()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) { return Updater.canCheck }
        return true
    }

    /// Opens a prefilled GitHub issue. Also sent to nil as `reportProblem:` from the chat panel.
    @objc func reportProblem(_ sender: Any?) {
        ProblemReport.open()
    }
}
