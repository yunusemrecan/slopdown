// SPDX-License-Identifier: GPL-3.0-or-later

#if canImport(AppKit)
import AppKit
import SlopdownCore

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSTextStorageDelegate {
    private(set) var textView: EditorTextView!
    let storage = NSTextStorage()
    private(set) var statusBar: StatusBarView!
    private(set) var previewPane: PreviewPane!
    private(set) var splitView: NSSplitView!
    private var stats = TextStats("")
    private let layoutManager = NSLayoutManager()
    private let concealer = GlyphConcealer()
    let styler = MarkdownStyler()
    let completion = CompletionState()
    private var watcher: DirectoryWatcher?

    /// Characters changed but the parser has not run yet (element ranges are stale).
    private(set) var parseIsStale = false
    /// The edit since the last parse: (edited range in the new text, change in length).
    /// nil plus `parseIsStale` means several edits: parse everything.
    private var pendingEdit: (range: NSRange, delta: Int)?
    private var pendingEdits = 0
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

        let split = NSSplitView(frame: NSRect(x: 0, y: barHeight, width: content.bounds.width,
                                              height: content.bounds.height - barHeight))
        split.isVertical = true
        split.dividerStyle = .thin
        split.autoresizingMask = [.width, .height]
        splitView = split

        let scroll = NSScrollView(frame: split.bounds)
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
        tv.registerForDraggedTypes(tv.registeredDraggedTypes + [.fileURL, .png, .tiff])
        storage.delegate = self

        scroll.documentView = tv
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(editorScrolled(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        let pane = PreviewPane(frame: NSRect(x: 0, y: 0, width: 400, height: split.bounds.height))
        pane.isHidden = true
        previewPane = pane
        split.addArrangedSubview(scroll)
        split.addArrangedSubview(pane)
        content.addSubview(split)
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

    private var statsAreStale = true

    /// Coalesced: counting a long document on every keystroke would slow typing.
    private func updateStatus(textChanged: Bool) {
        if textChanged { statsAreStale = true }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(refreshStatus), object: nil)
        perform(#selector(refreshStatus), with: nil, afterDelay: textChanged ? 0.25 : 0.05)
    }

    @objc private func refreshStatus() {
        guard let tv = textView, let statusBar else { return }
        let text = tv.string
        if statsAreStale { stats = TextStats(text); statsAreStale = false }
        let sel = tv.selectedRange()
        let pos = TextStats.lineAndColumn(text, sel.location)
        let selected = sel.length > 0 && NSMaxRange(sel) <= (text as NSString).length
            ? TextStats((text as NSString).substring(with: sel)) : nil
        statusBar.show(stats: stats, line: pos.line, column: pos.column, selection: selected)
    }

    func documentLocationChanged() {
        siteChecked = nil
        styler.resolutions.invalidate()
        restyleAll()
        reloadPreview()
    }

    // MARK: - Hugo site

    private var siteChecked: URL?        // document URL the site was looked up for
    private(set) var site: HugoSite?

    /// The site the note belongs to (looked up once per file location).
    private func refreshSite() {
        let url = markdownDocument?.fileURL
        guard url != siteChecked else { return }
        siteChecked = url
        site = url.flatMap { HugoSite.containing($0) }
        statusBar?.setSite(site, conventions: conventions)
        watchFolder()
    }

    /// The project's link conventions, with the user's per-site choice applied.
    /// Files added, removed or renamed in the note's folder (or the Hugo site) refresh
    /// link colors, images, embeds and the completion list.
    private func watchFolder() {
        guard let doc = markdownDocument?.fileURL else { watcher = nil; return }
        let root = site?.root ?? doc.deletingLastPathComponent()
        let ownPath = doc.standardizedFileURL.path
        watcher = DirectoryWatcher(root: root) { [weak self] paths in
            let relevant = paths.contains { path in
                path != ownPath && !path.split(separator: "/").contains(where: { $0.hasPrefix(".") })
                    && !path.contains("/public/") && !path.contains("/resources/_gen/")
            }
            guard relevant, let self else { return }
            self.styler.resolutions.invalidate()
            self.completion.index = [:]
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.folderChanged), object: nil)
            self.perform(#selector(self.folderChanged), with: nil, afterDelay: 0.3)
        }
    }

    @objc private func folderChanged() {
        guard !parseIsStale else { return }
        styler.apply(to: storage, in: NSRange(location: 0, length: storage.length))
        textView.needsDisplay = true
    }

    var conventions: HugoConventions? {
        guard let site else { return nil }
        var c = site.detected
        if let raw = UserDefaults.standard.string(forKey: Self.styleKey(site)), let style = HugoLinkStyle(rawValue: raw) {
            c.style = style
        }
        return c
    }

    static func styleKey(_ site: HugoSite) -> String { "HugoLinkStyle:" + site.root.path }

    func setLinkStyle(_ style: HugoLinkStyle?) {
        guard let site else { return }
        if let style { UserDefaults.standard.set(style.rawValue, forKey: Self.styleKey(site)) }
        else { UserDefaults.standard.removeObject(forKey: Self.styleKey(site)) }
        // Other open notes of the same site follow.
        for doc in NSDocumentController.shared.documents {
            if let editor = (doc as? MarkdownDocument)?.editor, editor.site?.root == site.root {
                editor.statusBar?.setSite(editor.site, conventions: editor.conventions)
                editor.restyleAll()
            }
        }
    }

    var linkContext: LinkContext {
        LinkContext(document: markdownDocument?.fileURL, site: site, conventions: conventions)
    }

    func restyleAll() {
        refreshSite()
        styler.context = linkContext
        styler.textWidth = textWidth
        styler.reparse(storage.string)
        parseIsStale = false
        pendingEdit = nil
        pendingEdits = 0
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
        guard editedMask.contains(.editedCharacters) else { return }
        parseIsStale = true
        pendingEdits += 1
        pendingEdit = (editedRange, delta)
    }

    /// After typing: re-parse only the edited paragraphs and restyle only what changed
    /// (the edited lines and lines whose syntax was or becomes revealed).
    private func restyleAfterEdit() {
        guard let edit = pendingEdit, pendingEdits == 1, !styler.sourceMode else {
            restyleAll()
            return
        }
        let ns = storage.mutableString as NSString
        // Revealed elements before the edit, moved to where they are now.
        let oldEnd = NSMaxRange(edit.range) - edit.delta
        let previouslyRevealed: [NSRange] = styler.revealed.compactMap { i in
            guard i < styler.elements.count else { return nil }
            let r = styler.elements[i].range
            return r.location >= oldEnd ? NSRange(location: r.location + edit.delta, length: r.length) : r
        }
        let dirtyRange = styler.update(storage.string, editedRange: edit.range, delta: edit.delta)
        parseIsStale = false
        pendingEdit = nil
        pendingEdits = 0
        styler.revealed = styler.revealedElements(for: selection)

        var dirty = IndexSet(integersIn: dirtyRange.location..<NSMaxRange(dirtyRange))
        for r in previouslyRevealed + styler.revealed.map({ styler.elements[$0].range })
            where NSMaxRange(r) <= ns.length {
            let p = ns.paragraphRange(for: r)
            dirty.insert(integersIn: p.location..<NSMaxRange(p))
        }
        for r in dirty.rangeView {
            styler.apply(to: storage, in: NSRange(location: r.lowerBound, length: r.count))
        }
        updateStatus(textChanged: true)
    }

    func textDidChange(_ notification: Notification) {
        if isPreviewVisible { schedulePreviewSave() }
        restyleAfterEdit()
        updateCompletion()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if !parseIsStale { updateStatus(textChanged: false) }
        if !parseIsStale, completionVisible { updateCompletion() }
        guard !parseIsStale, !styler.sourceMode else { return }
        let new = styler.revealedElements(for: selection)
        let changed = new.symmetricDifference(styler.revealed)
        guard !changed.isEmpty else { return }
        styler.revealed = new

        let ns = storage.mutableString as NSString
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

    func windowDidResignKey(_ notification: Notification) {
        hideCompletion()
    }

    func windowWillClose(_ notification: Notification) {
        hideCompletion()
        watcher = nil
        // Stop hugo server when the last window of its site closes.
        if let site {
            let others = NSDocumentController.shared.documents.compactMap { ($0 as? MarkdownDocument)?.editor }
                .filter { $0 !== self && $0.site?.root == site.root }
            if others.isEmpty { HugoPreview.shared.stop(site) }
        }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        (document as? NSDocument)?.undoManager
    }

}
#endif
