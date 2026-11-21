// SPDX-License-Identifier: GPL-3.0-or-later
//
// Pasting and dropping images: files are linked where they are when they already
// belong to the note (or Hugo page/site), copied in otherwise; pasted image data is
// saved as a PNG. Links are written in the note's convention.

#if canImport(AppKit)
import AppKit
import SlopdownCore
import UniformTypeIdentifiers

extension EditorWindowController {

    /// Image files on a pasteboard (Finder copy or drag).
    private func imageFiles(_ pb: NSPasteboard) -> [URL] {
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]) as? [URL] ?? []
        return urls
    }

    /// Raw image data (screenshot, copied image) when the pasteboard has no text.
    private func imageData(_ pb: NSPasteboard) -> Data? {
        guard pb.string(forType: .string) == nil else { return nil }
        if let png = pb.data(forType: .png) { return png }
        if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }

    func hasImages(_ pb: NSPasteboard) -> Bool {
        !imageFiles(pb).isEmpty || imageData(pb) != nil
    }

    /// Inserts links for the images on `pb` at the selection. Returns false when the
    /// pasteboard holds no images (normal paste/drop then happens).
    @discardableResult
    func importImages(from pb: NSPasteboard) -> Bool {
        let files = imageFiles(pb)
        let data = files.isEmpty ? imageData(pb) : nil
        guard !files.isEmpty || data != nil else { return false }
        guard let doc = markdownDocument?.fileURL else {
            let alert = NSAlert()
            alert.messageText = L("Save this note first")
            alert.informativeText = L("Images are saved next to the note, so it needs a place on disk.")
            if let window { alert.beginSheetModal(for: window) }
            return true
        }
        let folder = Attachments.folder(for: doc, site: site)
        let fm = FileManager.default
        var targets: [URL] = []
        do {
            if let data {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = Attachments.uniqueURL(for: Attachments.pastedImageName(), in: folder)
                try data.write(to: url, options: .withoutOverwriting)
                targets.append(url)
            }
            for file in files {
                if Attachments.shouldCopy(file, document: doc, site: site) {
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    let url = Attachments.uniqueURL(for: file.lastPathComponent, in: folder)
                    try fm.copyItem(at: file, to: url)
                    targets.append(url)
                } else {
                    targets.append(file)
                }
            }
        } catch {
            NSApp.presentError(error)
            return true
        }
        let context = linkContext
        let links = targets.compactMap { context.imageLink(to: $0) }
        guard !links.isEmpty, let tv = textView else { return true }
        let sel = tv.selectedRange()
        let text = links.joined(separator: "\n")
        styler.resolutions.invalidate()
        replace(sel, with: text, actionName: targets.count == 1 ? L("Insert Image") : L("Insert Images"))
        tv.setSelectedRange(NSRange(location: sel.location + (text as NSString).length, length: 0))
        return true
    }

    /// Hugo: ⇧⌘E picks an image file (copied into the page bundle or static/ as needed).
    @objc func insertImage(_ sender: Any?) {
        guard let window, let doc = markdownDocument?.fileURL else { NSSound.beep(); return }
        let panel = NSOpenPanel()
        panel.directoryURL = Attachments.folder(for: doc, site: site)
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = L("Choose images to insert")
        panel.prompt = L("Insert")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, !panel.urls.isEmpty else { return }
            let pb = NSPasteboard(name: NSPasteboard.Name("slopdown.insert.\(UUID().uuidString)"))
            pb.clearContents()
            pb.writeObjects(panel.urls as [NSURL])
            self.importImages(from: pb)
            pb.releaseGlobally()
        }
    }
}
#endif
