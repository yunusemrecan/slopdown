// SPDX-License-Identifier: GPL-3.0-or-later
//
// Links: elements under the mouse, following links, creating or choosing missing targets, task boxes.

#if canImport(AppKit)
import AppKit
import SlopdownCore

extension EditorWindowController {
    // MARK: - Elements under the mouse

    func linkElement(at point: NSPoint) -> MDElement? {
        guard !parseIsStale, let ci = textView.characterIndex(onGlyphAt: point) else { return nil }
        return styler.elements.first { $0.link != nil && $0.range.containsIndex(ci) }
            ?? styler.elements.first { $0.image != nil && $0.range.containsIndex(ci) }.flatMap(imageAsLink)
    }

    /// ⌘-clicking an image opens the image file.
    func imageAsLink(_ e: MDElement) -> MDElement? {
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
        replace(r, with: checked ? " " : "x", actionName: checked ? L("Uncheck Task") : L("Check Task"))
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
            alert.messageText = L("Save this note first")
            alert.informativeText = L("Links are looked up relative to the folder the note is saved in.")
            alert.beginSheetModal(for: window!)
            return
        }
        if let url = context.resolve(link) {
            openTarget(url, heading: heading)
        } else {
            askAboutMissing(target: target, link: link, base: site?.contentRoot(for: base.appendingPathComponent("x")) ?? base, heading: heading)
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

    func askAboutMissing(target: String, link: MDLink, base: URL, heading: String?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = LF("“%@” doesn’t exist", target)
        var info = site == nil
            ? LF("No matching file in “%@” or its subfolders.", base.lastPathComponent)
            : LF("No page with this path in the site’s “%@” folder.", base.lastPathComponent)
        if let newURL = linkContext.newFileURL(for: link) {
            info += "\n\n" + LF("A new file would be created at:\n%@", (newURL.path as NSString).abbreviatingWithTildeInPath)
            if !LinkSafety.isInside(newURL, creationRoot) {
                info += "\n\n" + LF("⚠︎ That is outside “%@”.", creationRoot.lastPathComponent)
            }
        }
        alert.informativeText = info
        alert.addButton(withTitle: site == nil ? L("Create New File") : L("Create New Page"))
        alert.addButton(withTitle: L("Choose File…"))
        alert.addButton(withTitle: L("Cancel"))
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
        if let doc = markdownDocument?.fileURL { return site?.contentRoot(for: doc) ?? doc.deletingLastPathComponent() }
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    func createFile(for link: MDLink) {
        let context = linkContext
        guard let url = context.newFileURL(for: link) else { return }
        let create = { self.createAndOpen(url, contents: context.newFileContents(for: url)) }
        guard LinkSafety.isInside(url, creationRoot) else {
            // A link like [[../../Library/x]] must not quietly create files elsewhere.
            confirm(title: LF("Create a file outside “%@”?", creationRoot.lastPathComponent),
                    detail: L("The link points outside the note’s folder. The file would be created at:\n\n")
                        + (url.path as NSString).abbreviatingWithTildeInPath,
                    button: L("Create File"), perform: create)
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

    func chooseFile(for link: MDLink, base: URL, heading: String?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = base
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = L("Choose the file this link should point to")
        panel.prompt = L("Use This File")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            if let newTarget = self.linkContext.retarget(link, to: url) {
                self.replace(link.targetRange, with: newTarget, actionName: L("Change Link"))
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
