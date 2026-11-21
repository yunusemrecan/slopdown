// SPDX-License-Identifier: GPL-3.0-or-later

#if canImport(AppKit)
import AppKit
import SlopdownCore

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSTextStorageDelegate {
    private(set) var textView: EditorTextView!
    private let storage = NSTextStorage()
    private(set) var statusBar: StatusBarView!
    private var stats = TextStats("")
    private let layoutManager = NSLayoutManager()
    private let concealer = GlyphConcealer()
    let styler = MarkdownStyler()

    /// Characters changed but the parser has not run yet (element ranges are stale).
    private var parseIsStale = false
    private static var cascadePoint: NSPoint?

    static func make() -> EditorWindowController {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 880),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        let controller = EditorWindowController(window: window)
        controller.setUp(window)
        return controller
    }

    private func setUp(_ window: NSWindow) {
        window.tabbingMode = .disallowed          // every note gets its own window
        window.minSize = NSSize(width: 360, height: 240)
        window.delegate = self

        storage.addLayoutManager(layoutManager)
        layoutManager.delegate = concealer
        layoutManager.allowsNonContiguousLayout = true
        let container = NSTextContainer(size: NSSize(width: Theme.readableWidth, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layoutManager.addTextContainer(container)

        window.toolbar = makeToolbar()
        window.toolbarStyle = .unifiedCompact

        let content = NSView(frame: window.contentLayoutRect)
        let barHeight = StatusBarView.height
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: content.bounds.width, height: barHeight))
        status.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(status)
        statusBar = status

        let scroll = NSScrollView(frame: NSRect(x: 0, y: barHeight, width: content.bounds.width,
                                                height: content.bounds.height - barHeight))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let tv = EditorTextView(frame: scroll.contentView.bounds, textContainer: container)
        tv.editor = self
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        tv.insertionPointColor = .controlAccentColor
        tv.typingAttributes = Theme.baseAttributes(sourceMode: false)
        tv.delegate = self
        storage.delegate = self

        scroll.documentView = tv
        content.addSubview(scroll)
        window.contentView = content
        textView = tv
        tv.updateTextWidth()

        if let p = Self.cascadePoint {
            Self.cascadePoint = window.cascadeTopLeft(from: p)
        } else {
            window.center()
            Self.cascadePoint = window.cascadeTopLeft(from: .zero)
        }
        window.makeFirstResponder(tv)
    }

    var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }

    var currentText: String { storage.string }

    // MARK: - Content

    func setText(_ text: String) {
        storage.setAttributedString(NSAttributedString(string: text, attributes: Theme.baseAttributes(sourceMode: styler.sourceMode)))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        restyleAll()
    }

    /// The file was saved somewhere else / renamed: links and images resolve differently.
    // MARK: - Status bar

    private func updateStatus(textChanged: Bool) {
        guard let tv = textView, let statusBar else { return }
        let text = tv.string
        if textChanged { stats = TextStats(text) }
        let sel = tv.selectedRange()
        let pos = TextStats.lineAndColumn(text, sel.location)
        let selected = sel.length > 0 && NSMaxRange(sel) <= (text as NSString).length
            ? TextStats((text as NSString).substring(with: sel)) : nil
        statusBar.show(stats: stats, line: pos.line, column: pos.column, selection: selected)
    }

    func documentLocationChanged() {
        statusBar?.setFile(markdownDocument?.fileURL)
        styler.resolutions.invalidate()
        restyleAll()
    }

    private func restyleAll() {
        styler.baseDirectory = markdownDocument?.fileURL?.deletingLastPathComponent()
        styler.textWidth = textWidth
        styler.reparse(storage.string)
        parseIsStale = false
        styler.revealed = styler.revealedElements(for: selection)
        styler.apply(to: storage, in: NSRange(location: 0, length: storage.length))
        textView.needsDisplay = true
        statusBar?.setFile(markdownDocument?.fileURL)
        updateStatus(textChanged: true)
    }

    private var selection: [NSRange] {
        textView.selectedRanges.map { $0.rangeValue }
    }

    private var textWidth: CGFloat {
        guard let tc = textView?.textContainer else { return Theme.readableWidth }
        return tc.size.width - 2 * tc.lineFragmentPadding
    }

    func textWidthDidChange() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(widthSettled), object: nil)
        perform(#selector(widthSettled), with: nil, afterDelay: 0.08)
    }

    @objc private func widthSettled() {
        // Only images depend on the width.
        guard styler.elements.contains(where: { $0.image != nil }) else { return }
        restyleAll()
    }

    // MARK: - Text system callbacks

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        if editedMask.contains(.editedCharacters) { parseIsStale = true }
    }

    func textDidChange(_ notification: Notification) {
        restyleAll()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if !parseIsStale { updateStatus(textChanged: false) }
        guard !parseIsStale, !styler.sourceMode else { return }
        let new = styler.revealedElements(for: selection)
        let changed = new.symmetricDifference(styler.revealed)
        guard !changed.isEmpty else { return }
        styler.revealed = new

        let ns = storage.string as NSString
        var dirty = IndexSet()
        for i in changed where i < styler.elements.count {
            let r = styler.elements[i].range
            guard NSMaxRange(r) <= ns.length else { continue }
            let p = ns.paragraphRange(for: r)
            dirty.insert(integersIn: p.location..<NSMaxRange(p))
        }
        for r in dirty.rangeView {
            styler.apply(to: storage, in: NSRange(location: r.lowerBound, length: r.count))
        }
    }

    // MARK: - Source mode

    @objc func toggleSourceMode(_ sender: Any?) {
        styler.sourceMode.toggle()
        textView.typingAttributes = Theme.baseAttributes(sourceMode: styler.sourceMode)
        restyleAll()
    }

    // The menu item's checkmark is updated by AppDelegate (NSMenuDelegate).

    // MARK: - Window

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        (document as? NSDocument)?.undoManager
    }

    // MARK: - Elements under the mouse

    func linkElement(at point: NSPoint) -> MDElement? {
        guard !parseIsStale, let ci = textView.characterIndex(onGlyphAt: point) else { return nil }
        return styler.elements.first { $0.link != nil && $0.range.containsIndex(ci) }
            ?? styler.elements.first { $0.image != nil && $0.range.containsIndex(ci) }.flatMap(imageAsLink)
    }

    /// ⌘-clicking an image opens the image file.
    private func imageAsLink(_ e: MDElement) -> MDElement? {
        guard let img = e.image else { return nil }
        var copy = e
        copy.kind = .link(MDLink(style: img.isWiki ? .embed : .markdown, target: img.source,
                                 heading: nil, targetRange: img.targetRange))
        return copy
    }

    func taskElement(at point: NSPoint) -> MDElement? {
        guard !parseIsStale, !styler.sourceMode, let ci = textView.characterIndex(onGlyphAt: point),
              storage.attribute(.sdTask, at: ci, effectiveRange: nil) != nil else { return nil }
        return styler.elements.first {
            if case .task = $0.kind { return $0.marker.containsIndex(ci) }
            return false
        }
    }

    func toggleTask(_ e: MDElement) {
        guard case .task(let checked) = e.kind else { return }
        let r = NSRange(location: e.marker.location + 1, length: 1)
        replace(r, with: checked ? " " : "x", actionName: checked ? "Uncheck Task" : "Check Task")
    }

    private func replace(_ r: NSRange, with s: String, actionName: String) {
        guard NSMaxRange(r) <= storage.length else { return }
        if textView.shouldChangeText(in: r, replacementString: s) {
            storage.replaceCharacters(in: r, with: s)
            textView.didChangeText()
            textView.undoManager?.setActionName(actionName)
        }
    }

    // MARK: - Following links

    func follow(_ e: MDElement) {
        guard let link = e.link else { return }
        let target = MarkdownStyler.fileTarget(of: link)
        let heading = MarkdownStyler.heading(of: link)

        if link.style == .bareURL || LinkResolver.isExternal(target) {
            if let url = URL(string: target) { NSWorkspace.shared.open(url) }
            return
        }
        if target.isEmpty {
            if let heading { reveal(heading: heading) }
            return
        }
        guard let base = markdownDocument?.fileURL?.deletingLastPathComponent() else {
            let alert = NSAlert()
            alert.messageText = "Save this note first"
            alert.informativeText = "Links are looked up relative to the folder the note is saved in."
            alert.beginSheetModal(for: window!)
            return
        }
        if let url = LinkResolver.resolve(target: target, relativeTo: base) {
            Self.open(url, heading: heading)
        } else {
            askAboutMissing(target: target, link: link, base: base, heading: heading)
        }
    }

    static func open(_ url: URL, heading: String? = nil) {
        guard LinkResolver.isMarkdownFile(url) else {
            NSWorkspace.shared.open(url)
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, _, error in
            if let error {
                NSApp.presentError(error)
                return
            }
            if let heading, let editor = (doc as? MarkdownDocument)?.editor {
                editor.reveal(heading: heading)
            }
        }
    }

    private func askAboutMissing(target: String, link: MDLink, base: URL, heading: String?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "“\(target)” doesn’t exist"
        alert.informativeText = "No matching file in “\(base.lastPathComponent)” or its subfolders."
        alert.addButton(withTitle: "Create New File")
        alert.addButton(withTitle: "Choose File…")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.createFile(for: target, base: base)
            case .alertSecondButtonReturn:
                DispatchQueue.main.async { self.chooseFile(for: link, base: base, heading: heading) }
            default:
                break
            }
        }
    }

    private func createFile(for target: String, base: URL) {
        let url = LinkResolver.newFileURL(for: target, relativeTo: base)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) {
                try Data().write(to: url, options: .withoutOverwriting)
            }
            styler.resolutions.invalidate()
            restyleAll()   // the link is no longer "unresolved"
            Self.open(url)
        } catch {
            NSApp.presentError(error)
        }
    }

    private func chooseFile(for link: MDLink, base: URL, heading: String?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = base
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the file this link should point to"
        panel.prompt = "Link"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.retarget(link, to: url, base: base)
            Self.open(url, heading: heading)
        }
    }

    /// Rewrites the link so it points at the chosen file (undoable).
    private func retarget(_ link: MDLink, to url: URL, base: URL) {
        let newTarget = LinkResolver.linkTarget(for: url, relativeTo: base, wikiStyle: link.isWikiStyle)
        replace(link.targetRange, with: newTarget, actionName: "Change Link")
    }

    // MARK: - Headings

    func reveal(heading: String) {
        let ns = storage.string as NSString
        let wanted = heading.trimmingCharacters(in: .whitespaces).lowercased()
        for e in styler.elements {
            guard case .heading = e.kind else { continue }
            let text = ns.substring(with: e.content).trimmingCharacters(in: .whitespaces).lowercased()
            if text == wanted {
                textView.setSelectedRange(NSRange(location: e.content.location, length: 0))
                textView.scrollRangeToVisible(e.range)
                window?.makeKeyAndOrderFront(nil)
                return
            }
        }
        NSSound.beep()
    }
}
#endif
