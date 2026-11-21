// SPDX-License-Identifier: GPL-3.0-or-later
//
// Preview pane: the note's page from hugo server, kept in sync with the editor.

#if canImport(AppKit)
import AppKit
import SlopdownCore

extension EditorWindowController {
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
                ? L("Save this note to preview it.")
                : L("The preview pane shows a page the way its Hugo site renders it.\nThis note isn’t in a Hugo site’s content folder."))
            return
        }
        guard Self.isTrusted(site) else {
            previewPane.showMessage(L("The preview needs permission to run this site’s build."))
            askToTrust(site) { [weak self] in self?.reloadPreview() }
            return
        }
        previewPane.showMessage(L("Starting hugo server…"))
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
    func schedulePreviewSave() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(savePreview), object: nil)
        perform(#selector(savePreview), with: nil, afterDelay: 0.6)
    }

    @objc func savePreview() {
        #if SLOPDOWN_AUTOTEST
        Autotest.log("savePreview: visible \(isPreviewVisible) edited \(markdownDocument?.isDocumentEdited == true) undo level \(textView.undoManager?.groupingLevel ?? -1)")
        #endif
        guard isPreviewVisible, let doc = markdownDocument, doc.fileURL != nil else { return }
        // Compare with what is on disk rather than trusting the edited flag, which only
        // updates when the undo group closes.
        guard currentText != doc.diskText else { return }
        if !doc.isDocumentEdited { doc.updateChangeCount(.changeDone) }
        doc.autosave(withImplicitCancellability: false) { error in
            #if SLOPDOWN_AUTOTEST
            Autotest.log("savePreview: saved, error \(String(describing: error))")
            #endif
        }
    }

    @objc func editorScrolled(_ note: Notification) {
        guard isPreviewVisible, let tv = textView, let clip = tv.enclosingScrollView?.contentView else { return }
        previewPane.sync(previewAnchor(top: clip.bounds.minY, visibleHeight: clip.bounds.height))
    }

    /// The heading at the top of the editor and how far past it the view is.
    func previewAnchor(top: CGFloat, visibleHeight: CGFloat) -> PreviewPane.Anchor {
        guard let tv = textView, let lm = tv.layoutManager else { return .fraction(0) }
        let range = tv.frame.height - visibleHeight
        let fallback = PreviewPane.Anchor.fraction(range > 0 ? top / range : 0)
        if headingCache.generation != styler.generation {
            headingCache = (styler.generation, HeadingSync.headings(styler.elements, in: storage.mutableString))
        }
        let headings = headingCache.list
        guard !headings.isEmpty else { return fallback }
        func y(_ h: HeadingInfo) -> CGFloat {
            let g = lm.glyphIndexForCharacter(at: h.range.location)
            return lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil).minY + tv.textContainerOrigin.y
        }
        let probe = top + 4
        // Last heading at or above the top of the view (binary search: y grows with index).
        var lo = 0, hi = headings.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if y(headings[mid]) <= probe { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        if found < 0 {
            let first = headings[0]
            let fy = y(first)
            return .heading(title: first.title, occurrence: first.occurrence, count: first.count,
                            fraction: fy > 0 ? max(0, probe / fy) : 0, before: true)
        }
        let h = headings[found]
        let hy = y(h)
        let ny = found + 1 < headings.count ? y(headings[found + 1]) : tv.frame.height
        let fraction = ny > hy ? (probe - hy) / (ny - hy) : 0
        return .heading(title: h.title, occurrence: h.occurrence, count: h.count,
                        fraction: max(0, min(1, fraction)), before: false)
    }
}
#endif
