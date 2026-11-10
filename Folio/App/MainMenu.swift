import AppKit

/// The menu bar, built in code. Window commands go through the responder chain to `MainWindowController`.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        let name = ProcessInfo.processInfo.processName

        let services = NSMenu(title: String(localized: "Services"))
        NSApp.servicesMenu = services
        main.addItem(submenuItem(name, NSMenu.with(name, [
            item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            item("Check for Updates…", #selector(AppDelegate.checkForUpdates(_:))),
            .separator(),
            item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
            .separator(),
            submenuItem(String(localized: "Services"), services),
            .separator(),
            item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"),
        ])))

        main.addItem(submenu("File", [
            item("Open…", #selector(AppDelegate.openDocument(_:)), "o"),
            item("Import PDFs…", #selector(MainWindowController.importDocuments(_:)), "i", [.command, .shift]),
            item("New Folder", #selector(MainWindowController.newFolder(_:)), "n", [.command, .shift]),
            .separator(),
            item("Add to Favorites", #selector(MainWindowController.toggleFavorite(_:)), "d"),
            item("Show in Finder", #selector(MainWindowController.showInFinder(_:)), "r", [.command, .shift]),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            .separator(),
            item("Print…", #selector(MainWindowController.printPDF(_:)), "p"),
        ]))

        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            submenuItem(String(localized: "Find", comment: "Edit menu submenu"), NSMenu.with(String(localized: "Find", comment: "Edit menu submenu"), [
                item("Find…", #selector(MainWindowController.focusSearch(_:)), "f"),
                item("Find Next", #selector(MainWindowController.findNextMatch(_:)), "g"),
                item("Find Previous", #selector(MainWindowController.findPreviousMatch(_:)), "g", [.command, .shift]),
            ])),
        ]))

        main.addItem(submenu("View", [
            item("Hide Sidebar", #selector(MainWindowController.toggleSidebar(_:)), "s", [.command, .control]),
            item("Thumbnails", #selector(MainWindowController.toggleThumbnails(_:)), "2", [.command, .option]),
            item("Question Bubbles", #selector(MainWindowController.toggleQuestionBubbles(_:))),
            .separator(),
            item("Single Page", #selector(MainWindowController.setDisplayMode(_:)), tag: 0),
            item("Continuous Scroll", #selector(MainWindowController.setDisplayMode(_:)), tag: 1),
            item("Two Pages", #selector(MainWindowController.setDisplayMode(_:)), tag: 2),
            item("Book Mode", #selector(MainWindowController.toggleBookMode(_:))),
            .separator(),
            item("Actual Size", #selector(MainWindowController.readerActualSize(_:)), "0"),
            item("Zoom to Fit", #selector(MainWindowController.readerZoomToFit(_:)), "9"),
            item("Fit Whole Page", #selector(MainWindowController.readerFitPage(_:)), "9", [.command, .option]),
            item("Zoom In", #selector(MainWindowController.readerZoomIn(_:)), "+"),
            item("Zoom Out", #selector(MainWindowController.readerZoomOut(_:)), "-"),
            .separator(),
            item("Rotate Left", #selector(MainWindowController.rotateLeft(_:))),
            item("Rotate Right", #selector(MainWindowController.rotateRight(_:))),
            .separator(),
            item("Show Chat", #selector(MainWindowController.toggleChat(_:)), "l", [.command, .shift]),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]))

        main.addItem(submenu("Go", [
            item("Previous Page", #selector(MainWindowController.readerPreviousPage(_:)), arrow(NSUpArrowFunctionKey), [.command, .option]),
            item("Next Page", #selector(MainWindowController.readerNextPage(_:)), arrow(NSDownArrowFunctionKey), [.command, .option]),
            .separator(),
            item("Go to Page…", #selector(MainWindowController.readerGoToPage(_:)), "g", [.command, .option]),
        ]))

        let chat = NSMenu.with(String(localized: "Chat"), [
            item("Ask About Selection", #selector(MainWindowController.askAboutSelection(_:)), "l"),
            item("Ask About Page", #selector(MainWindowController.askAboutPage(_:)), "l", [.command, .option]),
            item("Attach PDF", #selector(MainWindowController.attachDocument(_:)), "a", [.command, .shift]),
            item("New Chat", #selector(MainWindowController.newChat(_:)), "o", [.command, .shift]),
            .separator(),
            QuestionsMenu.shared.item,
        ])
        chat.delegate = QuestionsMenu.shared
        main.addItem(submenuItem(String(localized: "Chat"), chat))

        let window = NSMenu.with(String(localized: "Window"), [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Library", #selector(AppDelegate.showMainWindow(_:)), "0", [.command, .shift]),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.windowsMenu = window
        main.addItem(submenuItem(String(localized: "Window"), window))

        let help = NSMenu.with(String(localized: "Help"), [
            item("Report a Problem…", #selector(AppDelegate.reportProblem(_:))),
        ])
        NSApp.helpMenu = help
        main.addItem(submenuItem(String(localized: "Help"), help))
        return main
    }

    private static func item(
        _ title: String.LocalizationValue,
        _ action: Selector?,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command,
        tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: title), action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.tag = tag
        return item
    }

    private static func submenu(_ title: String.LocalizationValue, _ items: [NSMenuItem]) -> NSMenuItem {
        let title = String(localized: title)
        return submenuItem(title, NSMenu.with(title, items))
    }

    private static func submenuItem(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func arrow(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt32(key))!))
    }
}

/// Chat > Questions on This Page: the questions on the reader's current page, hidden when there are none.
final class QuestionsMenu: NSObject, NSMenuDelegate {
    static let shared = QuestionsMenu()
    let item = ReaderViewController.questionsSubmenuItem([])

    func menuNeedsUpdate(_ menu: NSMenu) {
        let reader = (NSApp.mainWindow?.windowController as? MainWindowController)?.activeReader
        let items = reader.flatMap { reader in reader.currentPageIndex.map(reader.questionItems(onPage:)) } ?? []
        item.submenu?.removeAllItems()
        items.forEach { item.submenu?.addItem($0) }
        item.isHidden = items.isEmpty
        // Hide the separator above it too.
        if let index = menu.items.firstIndex(of: item), index > 0, menu.items[index - 1].isSeparatorItem {
            menu.items[index - 1].isHidden = items.isEmpty
        }
    }
}

private extension NSMenu {
    static func with(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        return menu
    }
}
