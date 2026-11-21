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
            pathButton.toolTip = "Show in Finder — \(url.path)"
            pathButton.isEnabled = true
        } else {
            pathButton.title = "Not saved"
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
        menu.addItem(withTitle: "Hugo · \(c.style.shortName) links", action: nil, keyEquivalent: "") // pull-down title
        let header = menu.addItem(withTitle: "Write links as", action: nil, keyEquivalent: "")
        header.isEnabled = false
        for style in HugoLinkStyle.allCases {
            let item = menu.addItem(withTitle: style.title, action: #selector(EditorWindowController.chooseLinkStyle(_:)), keyEquivalent: "")
            item.representedObject = style.rawValue
            item.state = c.style == style ? .on : .off
            item.indentationLevel = 1
        }
        let auto = menu.addItem(withTitle: "Use what the site uses (\(site.detected.style.shortName))",
                                action: #selector(EditorWindowController.chooseLinkStyle(_:)), keyEquivalent: "")
        auto.indentationLevel = 1
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preview in Browser", action: #selector(EditorWindowController.previewInBrowser(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "New Page…", action: #selector(EditorWindowController.newHugoPage(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Show Site in Finder", action: #selector(EditorWindowController.revealSite(_:)), keyEquivalent: "")
        siteButton.menu = menu
        siteButton.toolTip = "Hugo site: \(site.root.path)"
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
        var parts = ["Ln \(line), Col \(column)"]
        if let selection, selection.characters > 0 {
            parts.append("\(Self.format(selection.words)) of \(Self.format(stats.words)) words selected")
            parts.append("\(Self.format(selection.characters)) characters")
        } else {
            parts.append("\(Self.format(stats.words)) \(stats.words == 1 ? "word" : "words")")
            parts.append("\(Self.format(stats.characters)) characters")
            parts.append("\(Self.format(stats.lines)) \(stats.lines == 1 ? "line" : "lines")")
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
         .sdLink, .sdWiki, .sdEmbed, .space,
         .sdBullet, .sdNumbered, .sdTask, .sdQuote, .flexibleSpace, .sdPane, .sdPreview, .sdSource]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.flexibleSpace, .space]
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
            item.label = "Heading"
            item.paletteLabel = "Heading"
            item.toolTip = "Heading level"
            item.image = NSImage(systemSymbolName: "textformat.size", accessibilityDescription: "Heading")
            item.menu = Self.headingMenu()
            item.showsIndicator = true
            return item
        case .sdBold: return button("Bold", "bold", #selector(formatBold(_:)), "Bold (⌘B)")
        case .sdItalic: return button("Italic", "italic", #selector(formatItalic(_:)), "Italic (⌘I)")
        case .sdStrike: return button("Strikethrough", "strikethrough", #selector(formatStrikethrough(_:)), "Strikethrough (⇧⌘X)")
        case .sdCode: return button("Code", "chevron.left.forwardslash.chevron.right", #selector(formatCode(_:)), "Inline code (⌥⌘C)")
        case .sdLink: return button("Link", "link", #selector(formatLink(_:)), "Link (⌘K)")
        case .sdWiki: return button("Wiki Link", "note.text", #selector(formatWikiLink(_:)), "Link to a note — [[wiki link]], or a Hugo link inside a Hugo site (⇧⌘K)")
        case .sdEmbed: return button("Embed", "photo", #selector(formatEmbed(_:)), "Insert image or embed (⇧⌘E)")
        case .sdBullet: return button("Bullets", "list.bullet", #selector(formatBulletList(_:)), "Bulleted list")
        case .sdNumbered: return button("Numbers", "list.number", #selector(formatNumberedList(_:)), "Numbered list")
        case .sdTask: return button("Tasks", "checklist", #selector(formatTaskList(_:)), "Task list")
        case .sdQuote: return button("Quote", "text.quote", #selector(formatQuote(_:)), "Quote")
        case .sdPane: return button("Preview Pane", "sidebar.right", #selector(togglePreviewPane(_:)), "Preview pane: the page as the Hugo site renders it (⇧⌘P)")
        case .sdPreview: return button("Preview", "globe", #selector(previewInBrowser(_:)), "Preview in browser with hugo server (⌥⌘P)")
        case .sdSource: return button("Source", "doc.plaintext", #selector(toggleSourceMode(_:)), "Source mode (⌘E)")
        default: return nil
        }
    }

    /// Paragraph / Heading 1–6; each item's tag is the level (0 = paragraph).
    static func headingMenu() -> NSMenu {
        let menu = NSMenu(title: "Heading")
        menu.addItem(withTitle: "Paragraph", action: #selector(formatHeading(_:)), keyEquivalent: "").tag = 0
        for level in 1...6 {
            menu.addItem(withTitle: "Heading \(level)", action: #selector(formatHeading(_:)), keyEquivalent: "").tag = level
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

    @objc func formatBold(_ sender: Any?) { applyFormatting("Bold") { Formatting.toggleInline($0, $1, marker: "**") } }
    @objc func formatItalic(_ sender: Any?) { applyFormatting("Italic") { Formatting.toggleInline($0, $1, marker: "*") } }
    @objc func formatStrikethrough(_ sender: Any?) { applyFormatting("Strikethrough") { Formatting.toggleInline($0, $1, marker: "~~") } }
    @objc func formatCode(_ sender: Any?) { applyFormatting("Code") { Formatting.toggleInline($0, $1, marker: "`") } }
    @objc func formatLink(_ sender: Any?) {
        guard site != nil else { applyFormatting("Link", Formatting.link); return }
        let context = linkContext
        applyFormatting("Link") { text, sel in
            let ns = text as NSString
            let selected = ns.substring(with: sel)
            if LinkResolver.isExternal(selected.trimmingCharacters(in: .whitespaces)) { return Formatting.link(text, sel) }
            let (s, caret) = context.emptyLink(text: selected)
            return TextEdit(range: sel, replacement: s, selection: NSRange(location: sel.location + caret, length: 0))
        }
    }

    /// Wiki link outside Hugo; inside a Hugo site, pick the page and write a Hugo link.
    @objc func formatWikiLink(_ sender: Any?) {
        if site != nil { linkToPage(sender) } else { applyFormatting("Wiki Link", Formatting.wikiLink) }
    }

    @objc func formatEmbed(_ sender: Any?) {
        if site != nil { insertImage(sender) } else { applyFormatting("Embed", Formatting.embed) }
    }

    /// Choose a note/page and insert a link to it in the right convention.
    @objc func linkToPage(_ sender: Any?) {
        guard let window, let doc = markdownDocument?.fileURL else { NSSound.beep(); return }
        let panel = NSOpenPanel()
        panel.directoryURL = site?.contentDir ?? doc.deletingLastPathComponent()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .plainText]
        panel.message = site == nil ? "Choose a note to link to" : "Choose a page to link to"
        panel.prompt = "Link"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.insertPageLink(to: url)
        }
    }

    func insertPageLink(to url: URL) {
        let context = linkContext
        applyFormatting("Link") { text, sel in
            let selected = (text as NSString).substring(with: sel).trimmingCharacters(in: .whitespacesAndNewlines)
            var title = selected
            if title.isEmpty {
                let pageText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                title = (self.site != nil ? HugoSite.title(ofPageText: pageText) : nil) ?? url.deletingPathExtension().lastPathComponent
            }
            let link = context.pageLink(text: title, to: url) ?? ""
            let end = sel.location + (link as NSString).length
            return TextEdit(range: sel, replacement: link, selection: NSRange(location: end, length: 0))
        }
    }

    @objc func insertImage(_ sender: Any?) {
        guard let window, let doc = markdownDocument?.fileURL else { NSSound.beep(); return }
        let panel = NSOpenPanel()
        panel.directoryURL = doc.deletingLastPathComponent()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image"
        panel.prompt = "Insert"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url,
                  let link = self.linkContext.imageLink(to: url) else { return }
            self.applyFormatting("Insert Image") { _, sel in
                TextEdit(range: sel, replacement: link,
                         selection: NSRange(location: sel.location + (link as NSString).length, length: 0))
            }
        }
    }

    // MARK: - Hugo site actions

    @objc func chooseLinkStyle(_ sender: Any?) {
        let raw = (sender as? NSMenuItem)?.representedObject as? String
        setLinkStyle(raw.flatMap(HugoLinkStyle.init(rawValue:)))
    }

    @objc func previewInBrowser(_ sender: Any?) {
        guard let site, let page = markdownDocument?.fileURL else {
            let alert = NSAlert()
            alert.messageText = "Not part of a Hugo site"
            alert.informativeText = "Preview runs “hugo server” for the site this note belongs to. Open a note from a Hugo site’s content folder."
            if let window { alert.beginSheetModal(for: window) }
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
        panel.message = "New page in “\(site.root.lastPathComponent)”"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.createAndOpen(url, contents: HugoSite.frontMatter(for: url, toml: self.conventions?.tomlFrontMatter ?? true))
        }
    }

    @objc func revealSite(_ sender: Any?) {
        guard let site else { return }
        NSWorkspace.shared.activateFileViewerSelecting([site.root])
    }
    @objc func formatBulletList(_ sender: Any?) { applyFormatting("Bulleted List") { Formatting.setLineFormat($0, $1, .bullet) } }
    @objc func formatNumberedList(_ sender: Any?) { applyFormatting("Numbered List") { Formatting.setLineFormat($0, $1, .numbered) } }
    @objc func formatTaskList(_ sender: Any?) { applyFormatting("Task List") { Formatting.setLineFormat($0, $1, .task) } }
    @objc func formatQuote(_ sender: Any?) { applyFormatting("Quote") { Formatting.setLineFormat($0, $1, .quote) } }

    @objc func formatHeading(_ sender: Any?) {
        let level = (sender as? NSMenuItem)?.tag ?? 1
        applyFormatting(level == 0 ? "Paragraph" : "Heading \(level)") {
            Formatting.setLineFormat($0, $1, level == 0 ? .paragraph : .heading(level))
        }
    }
}
#endif
