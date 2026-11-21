// SPDX-License-Identifier: GPL-3.0-or-later

#if canImport(AppKit)
import AppKit
import SlopdownCore

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSTextStorageDelegate {
    private(set) var textView: EditorTextView!
    private let storage = NSTextStorage()
    private(set) var statusBar: StatusBarView!
    private(set) var previewPane: PreviewPane!
    private var splitView: NSSplitView!
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
    }

    /// The project's link conventions, with the user's per-site choice applied.
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

    // MARK: - Preview pane

    var isPreviewVisible: Bool { previewPane.map { !$0.isHidden } ?? false }

    @objc func togglePreviewPane(_ sender: Any?) {
        guard let window, let previewPane, let splitView else { return }
        if isPreviewVisible {
            previewPane.isHidden = true
            splitView.adjustSubviews()
            return
        }
        // Make room: widen the window if the editor would get too narrow.
        var frame = window.frame
        if frame.width < 1100, let screen = window.screen?.visibleFrame {
            let extra = min(1100 - frame.width, screen.maxX - frame.maxX + frame.minX - screen.minX)
            frame.size.width += max(0, extra)
            frame.origin.x = max(screen.minX, min(frame.minX, screen.maxX - frame.width))
            window.setFrame(frame, display: true, animate: false)
        }
        previewPane.isHidden = false
        splitView.adjustSubviews()
        splitView.setPosition(splitView.bounds.width * 0.5, ofDividerAt: 0)
        reloadPreview()
    }

    /// Points the pane at this note's page on `hugo server`.
    func reloadPreview() {
        guard isPreviewVisible, let previewPane else { return }
        guard let site, let page = markdownDocument?.fileURL else {
            previewPane.showMessage(markdownDocument?.fileURL == nil
                ? "Save this note to preview it."
                : "The preview pane shows a page the way its Hugo site renders it.\nThis note isn’t in a Hugo site’s content folder.")
            return
        }
        guard Self.isTrusted(site) else {
            previewPane.showMessage("The preview needs permission to run this site’s build.")
            askToTrust(site) { [weak self] in self?.reloadPreview() }
            return
        }
        previewPane.showMessage("Starting hugo server…")
        markdownDocument?.autosave(withImplicitCancellability: false) { _ in }
        HugoPreview.shared.url(of: page, in: site) { [weak self] url, output in
            guard let self, self.isPreviewVisible else { return }
            if let url {
                self.previewPane.show(url)
            } else {
                let m = HugoPreview.failureMessage(output)
                self.previewPane.showMessage(m.title + "\n\n" + m.detail)
            }
        }
    }

    /// Save soon after typing so hugo server rebuilds and the pane live-reloads.
    private func schedulePreviewSave() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(savePreview), object: nil)
        perform(#selector(savePreview), with: nil, afterDelay: 0.6)
    }

    @objc private func savePreview() {
        guard isPreviewVisible, let doc = markdownDocument, doc.fileURL != nil, doc.isDocumentEdited else { return }
        doc.autosave(withImplicitCancellability: false) { _ in }
    }

    @objc private func editorScrolled(_ note: Notification) {
        guard isPreviewVisible, let tv = textView, let clip = tv.enclosingScrollView?.contentView else { return }
        let range = tv.frame.height - clip.bounds.height
        previewPane.scroll(toFraction: range > 0 ? clip.bounds.minY / range : 0)
    }

    func textDidChange(_ notification: Notification) {
        if isPreviewVisible { schedulePreviewSave() }
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

    func replace(_ r: NSRange, with s: String, actionName: String) {
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
        let context = linkContext
        let target = LinkContext.fileTarget(of: link)
        let heading = LinkContext.heading(of: link)

        if context.isExternal(link) {
            openExternal(target)
            return
        }
        if target.isEmpty {
            if let heading { reveal(heading: heading) }
            return
        }
        guard let base = context.baseDirectory else {
            let alert = NSAlert()
            alert.messageText = "Save this note first"
            alert.informativeText = "Links are looked up relative to the folder the note is saved in."
            alert.beginSheetModal(for: window!)
            return
        }
        if let url = context.resolve(link) {
            openTarget(url, heading: heading)
        } else {
            askAboutMissing(target: target, link: link, base: site?.contentDir ?? base, heading: heading)
        }
    }

    /// Notes open in Slopdown; anything else goes through the safety rules.
    func openTarget(_ url: URL, heading: String? = nil) {
        if LinkResolver.isMarkdownFile(url) { Self.open(url, heading: heading) } else { openLocalFile(url) }
    }

    /// Opens a markdown/text note in its own window.
    static func open(_ url: URL, heading: String? = nil) {
        guard LinkResolver.isMarkdownFile(url) else { return }
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
        var info = site == nil
            ? "No matching file in “\(base.lastPathComponent)” or its subfolders."
            : "No page with this path in the site’s “\(base.lastPathComponent)” folder."
        if let newURL = linkContext.newFileURL(for: link) {
            info += "\n\nA new file would be created at:\n" + (newURL.path as NSString).abbreviatingWithTildeInPath
            if !LinkSafety.isInside(newURL, creationRoot) {
                info += "\n\n⚠︎ That is outside “\(creationRoot.lastPathComponent)”."
            }
        }
        alert.informativeText = info
        alert.addButton(withTitle: site == nil ? "Create New File" : "Create New Page")
        alert.addButton(withTitle: "Choose File…")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.createFile(for: link)
            case .alertSecondButtonReturn:
                DispatchQueue.main.async { self.chooseFile(for: link, base: base, heading: heading) }
            default:
                break
            }
        }
    }

    /// New files from links belong here: the note's folder, or the site's content folder.
    var creationRoot: URL {
        site?.contentDir ?? markdownDocument?.fileURL?.deletingLastPathComponent() ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    private func createFile(for link: MDLink) {
        let context = linkContext
        guard let url = context.newFileURL(for: link) else { return }
        let create = { self.createAndOpen(url, contents: context.newFileContents(for: url)) }
        guard LinkSafety.isInside(url, creationRoot) else {
            // A link like [[../../Library/x]] must not quietly create files elsewhere.
            confirm(title: "Create a file outside “\(creationRoot.lastPathComponent)”?",
                    detail: "The link points outside the note’s folder. The file would be created at:\n\n"
                        + (url.path as NSString).abbreviatingWithTildeInPath,
                    button: "Create File", perform: create)
            return
        }
        create()
    }

    func createAndOpen(_ url: URL, contents: String) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) {
                try Data(contents.utf8).write(to: url, options: .withoutOverwriting)
            }
            styler.resolutions.invalidate()
            restyleAll()   // the link is no longer "unresolved"
            openTarget(url)
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
            if let newTarget = self.linkContext.retarget(link, to: url) {
                self.replace(link.targetRange, with: newTarget, actionName: "Change Link")
            }
            self.openTarget(url, heading: heading)
        }
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
