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
    func schedulePreviewSave() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(savePreview), object: nil)
        perform(#selector(savePreview), with: nil, afterDelay: 0.6)
    }

    @objc func savePreview() {
        guard isPreviewVisible, let doc = markdownDocument, doc.fileURL != nil, doc.isDocumentEdited else { return }
        doc.autosave(withImplicitCancellability: false) { _ in }
    }

    @objc func editorScrolled(_ note: Notification) {
        guard isPreviewVisible, let tv = textView, let clip = tv.enclosingScrollView?.contentView else { return }
        let range = tv.frame.height - clip.bounds.height
        previewPane.scroll(toFraction: range > 0 ? clip.bounds.minY / range : 0)
    }
}
#endif
