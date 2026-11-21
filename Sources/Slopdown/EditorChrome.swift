// SPDX-License-Identifier: GPL-3.0-or-later
//
// Toolbar (formatting buttons), status bar (path, position, counts) and the
// formatting commands they and the Format menu call.

#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
import SlopdownCore

// MARK: - Status bar

final class StatusBarView: NSView {
    static let height: CGFloat = 24

    let pathButton = NSButton(title: "", target: nil, action: nil)
    /// "Hugo · relref ▾": link convention and site actions; hidden outside a Hugo site.
    let siteButton = NSPopUpButton(frame: .zero, pullsDown: true)
    let infoLabel = NSTextField(labelWithString: "")
    var fileURL: URL?

    override init(frame: NSRect) {
        super.init(frame: frame)

        let separator = NSBox(frame: NSRect(x: 0, y: frame.height - 1, width: frame.width, height: 1))
        separator.boxType = .separator
        separator.autoresizingMask = [.width, .minYMargin]
        addSubview(separator)

        let font = NSFont.systemFont(ofSize: 11)
        pathButton.isBordered = false
        pathButton.font = font
        pathButton.contentTintColor = .secondaryLabelColor
        pathButton.alignment = .left
        pathButton.lineBreakMode = .byTruncatingMiddle
        pathButton.target = self
        pathButton.action = #selector(revealInFinder(_:))
        pathButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        infoLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.alignment = .right
        infoLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        infoLabel.setContentHuggingPriority(.required, for: .horizontal)

        siteButton.isBordered = false
        siteButton.font = font
        siteButton.controlSize = .small
        (siteButton.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        siteButton.isHidden = true

        let left = NSStackView(views: [siteButton, pathButton])
        left.orientation = .horizontal
        left.spacing = 6
        left.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for v in [left, infoLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            infoLabel.leadingAnchor.constraint(greaterThanOrEqualTo: left.trailingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            infoLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setFile(_ url: URL?) {
        fileURL = url
        if let url {
            pathButton.title = (url.path as NSString).abbreviatingWithTildeInPath
            pathButton.toolTip = LF("Show in Finder — %@", url.path)
            pathButton.isEnabled = true
        } else {
            pathButton.title = L("Not saved")
            pathButton.toolTip = nil
            pathButton.isEnabled = false
        }
    }

    func setSite(_ site: HugoSite?, conventions: HugoConventions?) {
        guard let site, let c = conventions else {
            siteButton.isHidden = true
            return
        }
        siteButton.isHidden = false
        let menu = NSMenu()
        menu.addItem(withTitle: LF("Hugo · %@ links", L(c.style.shortName)), action: nil, keyEquivalent: "") // pull-down title
        let header = menu.addItem(withTitle: L("Write links as"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        for style in HugoLinkStyle.allCases {
            let item = menu.addItem(withTitle: L(style.title), action: #selector(EditorWindowController.chooseLinkStyle(_:)), keyEquivalent: "")
            item.representedObject = style.rawValue
            item.state = c.style == style ? .on : .off
            item.indentationLevel = 1
        }
        let auto = menu.addItem(withTitle: LF("Use what the site uses (%@)", L(site.detected.style.shortName)),
                                action: #selector(EditorWindowController.chooseLinkStyle(_:)), keyEquivalent: "")
        auto.indentationLevel = 1
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Preview in Browser"), action: #selector(EditorWindowController.previewInBrowser(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("New Page…"), action: #selector(EditorWindowController.newHugoPage(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Show Site in Finder"), action: #selector(EditorWindowController.revealSite(_:)), keyEquivalent: "")
        siteButton.menu = menu
        siteButton.toolTip = LF("Hugo site: %@", site.root.path)
    }

    @objc private func revealInFinder(_ sender: Any?) {
        guard let fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    static func format(_ n: Int) -> String { number.string(from: NSNumber(value: n)) ?? "\(n)" }

    func show(stats: TextStats, line: Int, column: Int, selection: TextStats?) {
        var parts = [LF("Ln %d, Col %d", line, column)]
        if let selection, selection.characters > 0 {
            parts.append(LF("%@ of %@ words selected", Self.format(selection.words), Self.format(stats.words)))
            parts.append(LF("%@ characters", Self.format(selection.characters)))
        } else {
            parts.append(stats.words == 1 ? LF("%@ word", Self.format(stats.words)) : LF("%@ words", Self.format(stats.words)))
            parts.append(LF("%@ characters", Self.format(stats.characters)))
            parts.append(stats.lines == 1 ? LF("%@ line", Self.format(stats.lines)) : LF("%@ lines", Self.format(stats.lines)))
        }
        infoLabel.stringValue = parts.joined(separator: "   ·   ")
    }
}

// MARK: - Toolbar

extension NSToolbarItem.Identifier {
    static let sdHeading = Self("sd.heading")
    static let sdBold = Self("sd.bold")
    static let sdItalic = Self("sd.italic")
    static let sdStrike = Self("sd.strike")
    static let sdCode = Self("sd.code")
    static let sdLink = Self("sd.link")
    static let sdWiki = Self("sd.wiki")
    static let sdEmbed = Self("sd.embed")
    static let sdBullet = Self("sd.bullet")
    static let sdNumbered = Self("sd.numbered")
    static let sdTask = Self("sd.task")
    static let sdQuote = Self("sd.quote")
    static let sdSource = Self("sd.source")
    static let sdPreview = Self("sd.preview")
    static let sdLists = Self("sd.lists")
    static let sdPane = Self("sd.pane")
}

extension EditorWindowController: NSToolbarDelegate {

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "SlopdownEditor")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sdHeading, .sdBold, .sdItalic, .sdStrike, .sdCode, .space,
         .sdLink, .sdWiki, .sdEmbed, .space, .sdLists, .flexibleSpace, .sdPane, .sdSource]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
            + [.sdBullet, .sdNumbered, .sdTask, .sdQuote, .sdPreview, .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func button(_ label: String, _ symbol: String, _ action: Selector, _ tip: String) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = label
            item.paletteLabel = label
            item.toolTip = tip
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            item.action = action
            item.isBordered = true
            return item
        }
        switch id {
        case .sdHeading:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = L("Heading")
            item.paletteLabel = L("Heading")
            item.toolTip = L("Heading level")
            item.image = NSImage(systemSymbolName: "textformat.size", accessibilityDescription: "Heading")
            item.menu = Self.headingMenu()
            item.showsIndicator = true
            return item
        case .sdBold: return button(L("Bold"), "bold", #selector(formatBold(_:)), L("Bold (⌘B)"))
        case .sdItalic: return button(L("Italic"), "italic", #selector(formatItalic(_:)), L("Italic (⌘I)"))
        case .sdStrike: return button(L("Strikethrough"), "strikethrough", #selector(formatStrikethrough(_:)), L("Strikethrough (⇧⌘X)"))
        case .sdCode: return button(L("Code"), "chevron.left.forwardslash.chevron.right", #selector(formatCode(_:)), L("Inline code (⌥⌘C)"))
        case .sdLink: return button(L("Link"), "link", #selector(formatLink(_:)), L("Link (⌘K)"))
        case .sdWiki: return button(L("Wiki Link"), "note.text", #selector(formatWikiLink(_:)), L("Link to a note: [[wiki link]] with completion, or a Hugo link inside a Hugo site (⇧⌘K)"))
        case .sdEmbed: return button(L("Image"), "photo", #selector(formatEmbed(_:)), L("Insert an image or embed a note (⇧⌘E). You can also paste or drop images."))
        case .sdLists:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = L("Lists")
            item.paletteLabel = L("Lists")
            item.toolTip = L("Lists and quotes")
            item.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Lists")
            let menu = NSMenu(title: L("Lists"))
            menu.addItem(withTitle: L("Bulleted List"), action: #selector(formatBulletList(_:)), keyEquivalent: "")
            menu.addItem(withTitle: L("Numbered List"), action: #selector(formatNumberedList(_:)), keyEquivalent: "")
            menu.addItem(withTitle: L("Task List"), action: #selector(formatTaskList(_:)), keyEquivalent: "")
            menu.addItem(withTitle: L("Quote"), action: #selector(formatQuote(_:)), keyEquivalent: "")
            item.menu = menu
            item.showsIndicator = true
            return item
        case .sdBullet: return button(L("Bullets"), "list.bullet", #selector(formatBulletList(_:)), L("Bulleted list"))
        case .sdNumbered: return button(L("Numbers"), "list.number", #selector(formatNumberedList(_:)), L("Numbered list"))
        case .sdTask: return button(L("Tasks"), "checklist", #selector(formatTaskList(_:)), L("Task list"))
        case .sdQuote: return button(L("Quote"), "text.quote", #selector(formatQuote(_:)), L("Quote"))
        case .sdPane: return button(L("Preview Pane"), "sidebar.right", #selector(togglePreviewPane(_:)), L("Preview pane: the page as the Hugo site renders it (⇧⌘P)"))
        case .sdPreview: return button(L("Preview"), "globe", #selector(previewInBrowser(_:)), L("Preview in browser with hugo server (⌥⌘P)"))
        case .sdSource: return button(L("Source"), "doc.plaintext", #selector(toggleSourceMode(_:)), L("Source mode (⌘E)"))
        default: return nil
        }
    }

    /// Paragraph / Heading 1–6; each item's tag is the level (0 = paragraph).
    static func headingMenu() -> NSMenu {
        let menu = NSMenu(title: L("Heading"))
        menu.addItem(withTitle: L("Paragraph"), action: #selector(formatHeading(_:)), keyEquivalent: "").tag = 0
        for level in 1...6 {
            menu.addItem(withTitle: LF("Heading %d", level), action: #selector(formatHeading(_:)), keyEquivalent: "").tag = level
        }
        return menu
    }

    // MARK: - Formatting commands

    func applyFormatting(_ name: String, _ make: (String, NSRange) -> TextEdit) {
        guard let tv = textView, let ts = tv.textStorage else { return }
        let edit = make(tv.string, tv.selectedRange())
        guard NSMaxRange(edit.range) <= ts.length else { return }
        if tv.shouldChangeText(in: edit.range, replacementString: edit.replacement) {
            ts.replaceCharacters(in: edit.range, with: edit.replacement)
            tv.didChangeText()
            tv.setSelectedRange(edit.selection)
            tv.undoManager?.setActionName(name)
        }
        window?.makeFirstResponder(tv)
    }

    @objc func formatBold(_ sender: Any?) { applyFormatting(L("Bold")) { Formatting.toggleInline($0, $1, marker: "**") } }
    @objc func formatItalic(_ sender: Any?) { applyFormatting(L("Italic")) { Formatting.toggleInline($0, $1, marker: "*") } }
    @objc func formatStrikethrough(_ sender: Any?) { applyFormatting(L("Strikethrough")) { Formatting.toggleInline($0, $1, marker: "~~") } }
    @objc func formatCode(_ sender: Any?) { applyFormatting(L("Code")) { Formatting.toggleInline($0, $1, marker: "`") } }
    @objc func formatLink(_ sender: Any?) {
        guard site != nil else { applyFormatting(L("Link"), Formatting.link); return }
        let context = linkContext
        applyFormatting(L("Link")) { text, sel in
            let ns = text as NSString
            let selected = ns.substring(with: sel)
            if LinkResolver.isExternal(selected.trimmingCharacters(in: .whitespaces)) { return Formatting.link(text, sel) }
            let (s, caret) = context.emptyLink(text: selected)
            return TextEdit(range: sel, replacement: s, selection: NSRange(location: sel.location + caret, length: 0))
        }
    }

    /// `[[…]]` (the completion list opens as you type); in a Hugo site, a link in the
    /// site's convention instead, since Hugo can't build wiki links.
    @objc func formatWikiLink(_ sender: Any?) {
        if site != nil { formatLink(sender) } else { applyFormatting(L("Wiki Link"), Formatting.wikiLink) }
    }

    /// `![[…]]` with completion of images and notes; in a Hugo site, choose an image file.
    @objc func formatEmbed(_ sender: Any?) {
        if site != nil { insertImage(sender) } else { applyFormatting(L("Embed"), Formatting.embed) }
    }

    // MARK: - Hugo site actions

    @objc func chooseLinkStyle(_ sender: Any?) {
        let raw = (sender as? NSMenuItem)?.representedObject as? String
        setLinkStyle(raw.flatMap(HugoLinkStyle.init(rawValue:)))
    }

    @objc func previewInBrowser(_ sender: Any?) {
        guard let site, let page = markdownDocument?.fileURL else {
            let alert = NSAlert()
            alert.messageText = L("Not part of a Hugo site")
            alert.informativeText = L("Preview runs “hugo server” for the site this note belongs to. Open a note from a Hugo site’s content folder.")
            if let window { alert.beginSheetModal(for: window) }
            return
        }
        guard Self.isTrusted(site) else {
            askToTrust(site) { [weak self] in self?.previewInBrowser(sender) }
            return
        }
        markdownDocument?.autosave(withImplicitCancellability: false) { _ in }
        HugoPreview.shared.preview(page, in: site, window: window)
    }

    @objc func newHugoPage(_ sender: Any?) {
        guard let window, let site, let doc = markdownDocument?.fileURL else { NSSound.beep(); return }
        let panel = NSSavePanel()
        panel.directoryURL = doc.deletingLastPathComponent()
        panel.nameFieldStringValue = "new-page.md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.message = LF("New page in “%@”", site.root.lastPathComponent)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.createAndOpen(url, contents: HugoSite.frontMatter(for: url, toml: self.conventions?.tomlFrontMatter ?? true))
        }
    }

    @objc func revealSite(_ sender: Any?) {
        guard let site else { return }
        NSWorkspace.shared.activateFileViewerSelecting([site.root])
    }
    @objc func formatBulletList(_ sender: Any?) { applyFormatting(L("Bulleted List")) { Formatting.setLineFormat($0, $1, .bullet) } }
    @objc func formatNumberedList(_ sender: Any?) { applyFormatting(L("Numbered List")) { Formatting.setLineFormat($0, $1, .numbered) } }
    @objc func formatTaskList(_ sender: Any?) { applyFormatting(L("Task List")) { Formatting.setLineFormat($0, $1, .task) } }
    @objc func formatQuote(_ sender: Any?) { applyFormatting(L("Quote")) { Formatting.setLineFormat($0, $1, .quote) } }

    @objc func formatHeading(_ sender: Any?) {
        let level = (sender as? NSMenuItem)?.tag ?? 1
        applyFormatting(level == 0 ? L("Paragraph") : LF("Heading %d", level)) {
            Formatting.setLineFormat($0, $1, level == 0 ? .paragraph : .heading(level))
        }
    }
}
#endif
