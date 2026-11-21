// SPDX-License-Identifier: GPL-3.0-or-later

#if canImport(AppKit)
import AppKit
import SlopdownCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let appName = "Slopdown"

    private var sourceModeItem: NSMenuItem?
    private var previewPaneItem: NSMenuItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if SLOPDOWN_AUTOTEST
        if Autotest.isActive { Autotest.run() }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        HugoPreview.shared.stopAll()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        #if SLOPDOWN_AUTOTEST
        return !Autotest.isActive
        #else
        return true
        #endif
    }

    // MARK: - Menu

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        let name = Self.appName

        // App
        let app = submenu(main, name)
        app.addItem(withTitle: "About \(name)", action: #selector(showAbout(_:)), keyEquivalent: "")
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
        file.addItem(withTitle: "New Hugo Page…", action: #selector(EditorWindowController.newHugoPage(_:)), keyEquivalent: "")
        let preview = file.addItem(withTitle: "Preview in Browser", action: #selector(EditorWindowController.previewInBrowser(_:)), keyEquivalent: "p")
        preview.keyEquivalentModifierMask = [.command, .option]
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

        // Format
        let format = submenu(main, "Format")
        func fmt(_ title: String, _ action: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) {
            let item = format.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.tag = tag
        }
        fmt("Bold", #selector(EditorWindowController.formatBold(_:)), "b")
        fmt("Italic", #selector(EditorWindowController.formatItalic(_:)), "i")
        fmt("Strikethrough", #selector(EditorWindowController.formatStrikethrough(_:)), "X")
        fmt("Inline Code", #selector(EditorWindowController.formatCode(_:)), "c", [.command, .option])
        format.addItem(.separator())
        fmt("Link", #selector(EditorWindowController.formatLink(_:)), "k")
        fmt("Wiki Link", #selector(EditorWindowController.formatWikiLink(_:)), "K")
        fmt("Embed", #selector(EditorWindowController.formatEmbed(_:)), "E")
        fmt("Link to Note…", #selector(EditorWindowController.linkToPage(_:)), "k", [.command, .option])
        fmt("Insert Image…", #selector(EditorWindowController.insertImage(_:)), "i", [.command, .option])
        format.addItem(.separator())
        fmt("Paragraph", #selector(EditorWindowController.formatHeading(_:)), "0", tag: 0)
        for level in 1...6 {
            fmt("Heading \(level)", #selector(EditorWindowController.formatHeading(_:)),
                level <= 3 ? "\(level)" : "", tag: level)
        }
        format.addItem(.separator())
        fmt("Bulleted List", #selector(EditorWindowController.formatBulletList(_:)))
        fmt("Numbered List", #selector(EditorWindowController.formatNumberedList(_:)))
        fmt("Task List", #selector(EditorWindowController.formatTaskList(_:)))
        fmt("Quote", #selector(EditorWindowController.formatQuote(_:)))

        // View
        let view = submenu(main, "View")
        view.delegate = self
        sourceModeItem = view.addItem(withTitle: "Source Mode",
                                      action: #selector(EditorWindowController.toggleSourceMode(_:)), keyEquivalent: "e")
        previewPaneItem = view.addItem(withTitle: "Preview Pane",
                                       action: #selector(EditorWindowController.togglePreviewPane(_:)), keyEquivalent: "P")
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

    /// About window with the vibe-coded notice in the user's language.
    @objc func showAbout(_ sender: Any?) {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: p,
        ]
        let credits = NSMutableAttributedString(string: "⚠︎ \(Disclaimer.title)\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.systemOrange, .paragraphStyle: p,
        ])
        credits.append(NSAttributedString(string: Disclaimer.text(), attributes: body))
        credits.append(NSAttributedString(string: "\n\ngithub.com/yunusemrecan/slopdown · GPL-3.0", attributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: p,
        ]))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    private func submenu(_ main: NSMenu, _ title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        main.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = menu
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let editor = NSApp.keyWindow?.windowController as? EditorWindowController
        sourceModeItem?.state = (editor?.styler.sourceMode ?? false) ? .on : .off
        previewPaneItem?.state = (editor?.isPreviewVisible ?? false) ? .on : .off
    }
}
#endif
