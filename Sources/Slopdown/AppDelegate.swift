// SPDX-License-Identifier: GPL-3.0-or-later

#if canImport(AppKit)
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let appName = "Slopdown"

    private var sourceModeItem: NSMenuItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Autotest.isActive { Autotest.run() }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { !Autotest.isActive }

    // MARK: - Menu

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        let name = Self.appName

        // App
        let app = submenu(main, name)
        app.addItem(withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        app.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File
        let file = submenu(main, "File")
        file.addItem(withTitle: "New", action: Selector(("newDocument:")), keyEquivalent: "n")
        file.addItem(withTitle: "Open…", action: Selector(("openDocument:")), keyEquivalent: "o")
        let recent = NSMenu(title: "Open Recent")
        recent.addItem(withTitle: "Clear Menu", action: Selector(("clearRecentDocuments:")), keyEquivalent: "")
        // Lets NSDocumentController fill this menu (what a nib's "Open Recent" does).
        let setName = NSSelectorFromString("_setMenuName:")
        if recent.responds(to: setName) { recent.perform(setName, with: "NSRecentDocumentsMenu") }
        file.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "").submenu = recent
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: Selector(("performClose:")), keyEquivalent: "w")
        file.addItem(withTitle: "Save…", action: Selector(("saveDocument:")), keyEquivalent: "s")
        file.addItem(withTitle: "Duplicate", action: Selector(("duplicateDocument:")), keyEquivalent: "S")
        file.addItem(withTitle: "Rename…", action: Selector(("renameDocument:")), keyEquivalent: "")
        file.addItem(withTitle: "Move To…", action: Selector(("moveDocument:")), keyEquivalent: "")
        file.addItem(withTitle: "Revert to Saved", action: Selector(("revertDocumentToSaved:")), keyEquivalent: "")

        // Edit
        let edit = submenu(main, "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = NSMenu(title: "Find")
        func findItem(_ title: String, _ key: String, _ action: NSTextFinder.Action, _ mods: NSEvent.ModifierFlags = .command) {
            let item = find.addItem(withTitle: title, action: Selector(("performTextFinderAction:")), keyEquivalent: key)
            item.tag = action.rawValue
            item.keyEquivalentModifierMask = mods
        }
        findItem("Find…", "f", .showFindInterface)
        findItem("Find and Replace…", "f", .showReplaceInterface, [.command, .option])
        findItem("Find Next", "g", .nextMatch)
        findItem("Find Previous", "G", .previousMatch)
        findItem("Use Selection for Find", "e", .setSearchString, [.command, .option])
        edit.addItem(withTitle: "Find", action: nil, keyEquivalent: "").submenu = find

        // View
        let view = submenu(main, "View")
        view.delegate = self
        sourceModeItem = view.addItem(withTitle: "Source Mode",
                                      action: #selector(EditorWindowController.toggleSourceMode(_:)), keyEquivalent: "e")
        view.addItem(.separator())
        view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]

        // Window
        let window = submenu(main, "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        // Help
        let help = submenu(main, "Help")
        NSApp.helpMenu = help

        return main
    }

    private func submenu(_ main: NSMenu, _ title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        main.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = menu
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let editor = NSApp.keyWindow?.windowController as? EditorWindowController
        sourceModeItem?.state = (editor?.styler.sourceMode ?? false) ? .on : .off
    }
}
#endif
