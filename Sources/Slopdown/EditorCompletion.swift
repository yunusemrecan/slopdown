// SPDX-License-Identifier: GPL-3.0-or-later
//
// Link completion popup: typing `[[`, `![[`, or (in a Hugo site) a ref shortcode or a
// markdown link destination lists matching pages; ↑↓ choose, Return/Tab insert, Esc
// closes. What is listed and inserted comes from SlopdownCore.Completion.

#if canImport(AppKit)
import AppKit
import SlopdownCore

/// A borderless list under the caret that never takes keyboard focus from the editor.
final class CompletionPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    private final class Table: NSTableView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private let panel: NSPanel
    private let table = Table()
    private(set) var items: [CompletionItem] = []
    var onAccept: ((Int) -> Void)?
    static let rowHeight: CGFloat = 34

    override init() {
        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let effect = NSVisualEffectView(frame: panel.contentView!.bounds)
        effect.material = .menu
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        panel.contentView = effect

        let scroll = NSScrollView(frame: effect.bounds.insetBy(dx: 0, dy: 4))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item")))
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.style = .inset
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        scroll.documentView = table
        effect.addSubview(scroll)
    }

    var isVisible: Bool { panel.isVisible }
    var selectedIndex: Int { max(0, table.selectedRow) }

    /// Shows the list below `caret` (screen coordinates), or above it near the bottom.
    func show(_ items: [CompletionItem], at caret: NSRect, in window: NSWindow) {
        self.items = items
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.scrollRowToVisible(0)
        let height = CGFloat(min(8, items.count)) * (Self.rowHeight + 2) + 12
        var frame = NSRect(x: caret.minX - 12, y: caret.minY - height - 4, width: 380, height: height)
        if let screen = window.screen?.visibleFrame {
            if frame.minY < screen.minY { frame.origin.y = caret.maxY + 4 }
            frame.origin.x = min(max(screen.minX, frame.minX), screen.maxX - frame.width)
        }
        panel.setFrame(frame, display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        guard panel.isVisible || panel.parent != nil else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        let row = min(max(0, table.selectedRow + delta), items.count - 1)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func clicked() {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        if row >= 0 { onAccept?(row) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let field: NSTextField
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField {
            field = reused
        } else {
            field = NSTextField(labelWithString: "")
            field.identifier = id
            field.lineBreakMode = .byTruncatingMiddle
            field.maximumNumberOfLines = 2
        }
        let item = items[row]
        let s = NSMutableAttributedString(string: item.title + "\n", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)])
        s.append(NSAttributedString(string: item.detail, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        field.attributedStringValue = s
        return field
    }
}

/// Per-window completion state (the controller holds one).
final class CompletionState {
    let popup = CompletionPopup()
    var context: CompletionContext?
    /// Page lists by root folder (+ images flag); cleared when the folder changes.
    var index: [String: [PageEntry]] = [:]
}

extension EditorWindowController {

    var completionVisible: Bool { completion.popup.isVisible }
    var completionItems: [CompletionItem] { completion.popup.isVisible ? completion.popup.items : [] }

    private func pages(includeImages: Bool) -> [PageEntry] {
        guard let doc = markdownDocument?.fileURL else { return [] }
        let root = site?.contentDir ?? doc.deletingLastPathComponent()
        let key = root.path + (includeImages ? "|img" : "")
        if let cached = completion.index[key] { return cached }
        let pages = Completion.index(root: root, includeImages: includeImages, readTitles: site != nil)
        completion.index[key] = pages
        return pages
    }

    /// Shows, updates or hides the list for the text before the caret.
    func updateCompletion() {
        guard let tv = textView, let window, markdownDocument?.fileURL != nil else { hideCompletion(); return }
        let sel = tv.selectedRange()
        let text = storage.mutableString as NSString
        guard sel.length == 0,
              let ctx = Completion.context(in: text, caret: sel.location, hugo: site != nil) else {
            hideCompletion()
            return
        }
        let typed = text.substring(with: ctx.partial)
        let list = Completion.items(for: ctx.kind, typed: typed,
                                    pages: pages(includeImages: ctx.kind == .wiki(embed: true)), context: linkContext)
        guard !list.isEmpty else { hideCompletion(); return }
        completion.context = ctx
        completion.popup.onAccept = { [weak self] in self?.acceptCompletion($0) }
        let caret = tv.firstRect(forCharacterRange: NSRange(location: ctx.partial.location, length: 0), actualRange: nil)
        completion.popup.show(list, at: caret, in: window)
    }

    func hideCompletion() {
        completion.popup.hide()
        completion.context = nil
    }

    func moveCompletion(_ delta: Int) { completion.popup.move(delta) }

    /// Replaces the typed text with the chosen item and closes the link.
    func acceptCompletion(_ index: Int? = nil) {
        let i = index ?? completion.popup.selectedIndex
        guard let ctx = completion.context, i < completion.popup.items.count, let tv = textView else { return }
        let item = completion.popup.items[i]
        let text = storage.mutableString as NSString
        let end = NSMaxRange(ctx.partial)
        let rest = text.substring(with: NSRange(location: end, length: min(3, text.length - end)))
        let insert = item.insert + Completion.closing(for: ctx.kind, after: rest)
        hideCompletion()
        replace(ctx.partial, with: insert, actionName: "Complete Link")
        var caret = ctx.partial.location + (insert as NSString).length
        // Already-closed links: put the caret after the existing closing characters.
        if Completion.closing(for: ctx.kind, after: rest).isEmpty {
            switch ctx.kind {
            case .wiki: caret += 2
            case .markdownLink: caret += 1
            case .hugoRef: break
            }
        }
        tv.setSelectedRange(NSRange(location: min(caret, storage.length), length: 0))
        hideCompletion()
    }
}
#endif
