// SPDX-License-Identifier: GPL-3.0-or-later
//
// Toolbar (formatting buttons), status bar (path, position, counts) and the
// formatting commands they and the Format menu call.

#if canImport(AppKit)
import AppKit
import SlopdownCore

// MARK: - Status bar

final class StatusBarView: NSView {
    static let height: CGFloat = 24

    let pathButton = NSButton(title: "", target: nil, action: nil)
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

        for v in [pathButton, infoLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            pathButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            pathButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            infoLabel.leadingAnchor.constraint(greaterThanOrEqualTo: pathButton.trailingAnchor, constant: 16),
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
         .sdBullet, .sdNumbered, .sdTask, .sdQuote, .flexibleSpace, .sdSource]
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
        case .sdWiki: return button("Wiki Link", "note.text", #selector(formatWikiLink(_:)), "Wiki link [[…]] (⇧⌘K)")
        case .sdEmbed: return button("Embed", "photo", #selector(formatEmbed(_:)), "Image or note embed ![[…]] (⇧⌘E)")
        case .sdBullet: return button("Bullets", "list.bullet", #selector(formatBulletList(_:)), "Bulleted list")
        case .sdNumbered: return button("Numbers", "list.number", #selector(formatNumberedList(_:)), "Numbered list")
        case .sdTask: return button("Tasks", "checklist", #selector(formatTaskList(_:)), "Task list")
        case .sdQuote: return button("Quote", "text.quote", #selector(formatQuote(_:)), "Quote")
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

    private func applyFormatting(_ name: String, _ make: (String, NSRange) -> TextEdit) {
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
    @objc func formatLink(_ sender: Any?) { applyFormatting("Link", Formatting.link) }
    @objc func formatWikiLink(_ sender: Any?) { applyFormatting("Wiki Link", Formatting.wikiLink) }
    @objc func formatEmbed(_ sender: Any?) { applyFormatting("Embed", Formatting.embed) }
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
