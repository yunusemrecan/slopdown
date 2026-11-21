// SPDX-License-Identifier: GPL-3.0-or-later
//
// A search-as-you-type list over the editor window: Quick Open (⌘P) for notes in the
// folder or Hugo site, Go to Heading (⇧⌘O) for the note's headings.

#if canImport(AppKit)
import AppKit
import SlopdownCore

struct PickerItem {
    var title: String
    var detail: String
    var indent: Int = 0
    var action: () -> Void
}

final class QuickPicker: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private let panel: Panel
    private let field = NSSearchField()
    private let table = NSTableView()
    private var all: [PickerItem] = []
    private(set) var shown: [PickerItem] = []
    private weak var parent: NSWindow?

    override init() {
        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
                      styleMask: [.borderless], backing: .buffered, defer: true)
        super.init()
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .floating
        panel.delegate = self

        let effect = NSVisualEffectView(frame: panel.contentView!.bounds)
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        panel.contentView = effect

        field.frame = NSRect(x: 12, y: effect.bounds.height - 40, width: effect.bounds.width - 24, height: 28)
        field.autoresizingMask = [.width, .minYMargin]
        field.font = .systemFont(ofSize: 15)
        field.focusRingType = .none
        field.delegate = self
        effect.addSubview(field)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 6, width: effect.bounds.width, height: effect.bounds.height - 54))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item")))
        table.headerView = nil
        table.rowHeight = 34
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

    func show(_ items: [PickerItem], placeholder: String, over window: NSWindow) {
        all = items
        parent = window
        field.stringValue = ""
        field.placeholderString = placeholder
        filter()
        let f = window.frame
        panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - panel.frame.height - 80))
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    func close() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        parent?.makeKeyAndOrderFront(nil)
    }

    /// Filters and returns the shown items (also used by the self-test).
    @discardableResult
    func filter(_ query: String? = nil) -> [PickerItem] {
        if let query { field.stringValue = query }
        shown = Completion.filter(all, query: field.stringValue) { [$0.title, $0.detail] }
        table.reloadData()
        if !shown.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        return shown
    }

    func accept(_ row: Int? = nil) {
        let r = row ?? table.selectedRow
        guard r >= 0, r < shown.count else { return }
        let item = shown[r]
        close()
        item.action()
    }

    @objc private func clicked() { accept(table.clickedRow) }

    // MARK: - Search field

    func controlTextDidChange(_ obj: Notification) { filter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
            guard !shown.isEmpty else { return true }
            let d = selector == #selector(NSResponder.moveUp(_:)) ? -1 : 1
            let r = min(max(0, table.selectedRow + d), shown.count - 1)
            table.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
            table.scrollRowToVisible(r)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            accept()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { close() }
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let label = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField) ?? {
            let f = NSTextField(labelWithString: "")
            f.identifier = id
            f.lineBreakMode = .byTruncatingMiddle
            f.maximumNumberOfLines = 2
            return f
        }()
        let item = shown[row]
        let indent = String(repeating: "    ", count: item.indent)
        let s = NSMutableAttributedString(string: indent + item.title + "\n",
                                          attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)])
        s.append(NSAttributedString(string: indent + item.detail, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        label.attributedStringValue = s
        return label
    }
}

extension EditorWindowController {

    /// ⌘P: notes in the folder (or the Hugo site's pages), by name or title.
    func quickOpenItems() -> [PickerItem] {
        guard let doc = markdownDocument?.fileURL else { return [] }
        let root = site?.contentRoot(for: doc) ?? doc.deletingLastPathComponent()
        let me = doc.standardizedFileURL
        return completionPages(includeImages: false).filter { $0.url != me }.map { page in
            let name = page.url.deletingPathExtension().lastPathComponent
            let rel = page.url.path.hasPrefix(root.path + "/") ? String(page.url.path.dropFirst(root.path.count + 1)) : page.url.path
            return PickerItem(title: page.title ?? name, detail: rel) { [weak self] in self?.openTarget(page.url) }
        }
    }

    /// ⇧⌘O: this note's headings, indented by level.
    func headingItems() -> [PickerItem] {
        HeadingSync.headings(styler.elements, in: storage.mutableString).map { h in
            PickerItem(title: h.text, detail: String(repeating: "#", count: h.level), indent: h.level - 1) { [weak self] in
                guard let self, let tv = self.textView else { return }
                tv.setSelectedRange(NSRange(location: h.range.location, length: 0))
                tv.scrollRangeToVisible(h.range)
                self.window?.makeFirstResponder(tv)
            }
        }
    }

    @objc func quickOpen(_ sender: Any?) {
        guard let window else { return }
        guard markdownDocument?.fileURL != nil else { NSSound.beep(); return }
        picker.show(quickOpenItems(), placeholder: site == nil ? "Open a note in this folder" : "Open a page of this site",
                    over: window)
    }

    @objc func goToHeading(_ sender: Any?) {
        guard let window else { return }
        let items = headingItems()
        guard !items.isEmpty else { NSSound.beep(); return }
        picker.show(items, placeholder: "Go to heading", over: window)
    }
}
#endif
