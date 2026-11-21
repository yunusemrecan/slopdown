// SPDX-License-Identifier: GPL-3.0-or-later
//
// Focus mode (View ▸ Focus Mode, ⇧⌘D) and the writing column width (View ▸ Text Width).

#if canImport(AppKit)
import AppKit
import SlopdownCore

extension EditorWindowController {
    // MARK: - Focus mode

    @objc func toggleFocusMode(_ sender: Any?) {
        focusMode.toggle()
        setChromeHidden(focusMode)
        if focusMode {
            updateFocusBlock()
            textView.scrollRangeToVisible(textView.selectedRange())
        } else {
            textView.focusBlock = nil
        }
    }

    func updateFocusBlock() {
        let caret = textView.selectedRange().location
        textView.focusBlock = Focus.block(in: storage.mutableString, at: caret)
    }

    /// Hides the toolbar and the status bar (the editor takes the freed space).
    private func setChromeHidden(_ hidden: Bool) {
        window?.toolbar?.isVisible = !hidden
        guard let statusBar, let splitView, let content = splitView.superview else { return }
        statusBar.isHidden = hidden
        let bar = hidden ? 0 : StatusBarView.height
        splitView.frame = NSRect(x: 0, y: bar, width: content.bounds.width, height: content.bounds.height - bar)
    }

    // MARK: - Text width

    // Chosen in AppDelegate.chooseTextWidth; every window follows.
    @objc func textWidthSettingChanged(_ note: Notification) {
        textView?.updateTextWidth()
    }
}
#endif
