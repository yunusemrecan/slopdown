// SPDX-License-Identifier: GPL-3.0-or-later

#if canImport(AppKit)
import AppKit

/// One markdown file. macOS takes care of autosave, versions, rename/move and
/// reloading when the file changes on disk.
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    private var loadedText = ""

    override class var autosavesInPlace: Bool { true }

    var editor: EditorWindowController? {
        windowControllers.first as? EditorWindowController
    }

    override func makeWindowControllers() {
        let controller = EditorWindowController.make()
        addWindowController(controller)
        controller.setText(loadedText)
    }

    override func data(ofType typeName: String) throws -> Data {
        if let editor {
            editor.textView.breakUndoCoalescing()
            loadedText = editor.currentText
        }
        return Data(loadedText.utf8)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let text = String(decoding: data, as: UTF8.self)
        loadedText = text
        // Revert / file changed on disk while the window is open
        let update = { [weak self] in
            guard let editor = self?.editor else { return }
            editor.setText(text)
            self?.undoManager?.removeAllActions()
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }

    override var fileURL: URL? {
        didSet {
            guard oldValue != fileURL else { return }
            let update = { [weak self] in self?.editor?.documentLocationChanged() }
            if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
        }
    }
}
#endif
