// SPDX-License-Identifier: GPL-3.0-or-later
//
// Visual self-test used by CI (the developer of this app cannot run it locally):
//
//   SLOPDOWN_AUTOTEST="/abs/a.md:/abs/b.md" SLOPDOWN_AUTOTEST_OUT=/tmp/shots Slopdown.app/Contents/MacOS/Slopdown
//
// Opens each file, renders the window at several scroll positions (and with the caret
// on a few interesting lines) into PNG files, logs some layout facts, then quits.

#if canImport(AppKit)
import AppKit
import SlopdownCore

enum Autotest {
    static var isActive: Bool { ProcessInfo.processInfo.environment["SLOPDOWN_AUTOTEST"] != nil }

    private static var outDir: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["SLOPDOWN_AUTOTEST_OUT"] ?? "/tmp/slopdown-autotest")
    }

    static func run() {
        let files = (ProcessInfo.processInfo.environment["SLOPDOWN_AUTOTEST"] ?? "")
            .split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        log("autotest: \(files.count) file(s) → \(outDir.path)")
        step(files, 0)
    }

    private static func step(_ files: [URL], _ i: Int) {
        guard i < files.count else {
            log("autotest: done")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
            return
        }
        let url = files[i]
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, _, error in
            guard let editor = (doc as? MarkdownDocument)?.editor else {
                log("autotest: could not open \(url.path): \(String(describing: error))")
                step(files, i + 1)
                return
            }
            editor.window?.setFrame(NSRect(x: 40, y: 40, width: 900, height: 1000), display: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                capture(editor, name: url.deletingPathExtension().lastPathComponent)
                let next = {
                    doc?.close()
                    step(files, i + 1)
                }
                if url.path.contains("hugo-site") { hugoTest(editor, done: next) } else { next() }
            }
        }
    }

    private static func capture(_ editor: EditorWindowController, name: String) {
        guard let tv = editor.textView, let scroll = tv.enclosingScrollView else { return }
        let base = name.replacingOccurrences(of: " ", with: "_")

        // Layout facts
        if let lm = tv.layoutManager, let ts = tv.textStorage {
            lm.ensureLayout(for: tv.textContainer!)
            ts.enumerateAttribute(.sdCodeBlock, in: NSRange(location: 0, length: ts.length)) { v, r, _ in
                guard v != nil else { return }
                let gr = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
                var rects: [String] = []
                lm.enumerateLineFragments(forGlyphRange: gr) { rect, _, _, _, _ in rects.append("\(Int(rect.minY))-\(Int(rect.maxY))") }
                log("\(base): codeBlock run \(r) lines \(rects)")
            }
            for key in [NSAttributedString.Key.sdTable, .sdImage, .sdEmbed] {
                ts.enumerateAttribute(key, in: NSRange(location: 0, length: ts.length)) { v, r, _ in
                    guard v != nil else { return }
                    let gr = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
                    var rects: [String] = []
                    lm.enumerateLineFragments(forGlyphRange: gr) { rect, used, _, g, _ in
                        let cr = lm.characterRange(forGlyphRange: g, actualGlyphRange: nil)
                        let text = (ts.string as NSString).substring(with: cr).debugDescription
                        rects.append("frag \(Int(rect.minY))-\(Int(rect.maxY)) x \(Int(used.minX))-\(Int(used.maxX)) chars \(cr) \(text)")
                    }
                    log("\(base): \(key.rawValue) \(r) \(rects)")
                }
            }
            log("\(base): elements \(editor.styler.elements.count), used height \(Int(lm.usedRect(for: tv.textContainer!).height))")
        }

        // Scroll positions
        let page = scroll.contentView.bounds.height
        let total = tv.frame.height
        var y: CGFloat = 0
        var n = 0
        while n < 8 {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            snapshot(editor, "\(base)-\(n)")
            n += 1
            if y + page >= total { break }
            y = min(y + page * 0.9, total - page)
        }

        // Caret on interesting lines: reveals syntax there
        let ns = tv.string as NSString
        for (i, e) in editor.styler.elements.enumerated() {
            let tag: String
            switch e.kind {
            case .heading(1): tag = "heading"
            case .tableRow: tag = "table"
            case .image(let img) where !img.standalone: tag = "inlineimage"
            default: continue
            }
            if FileManager.default.fileExists(atPath: outDir.appendingPathComponent("\(base)-caret-\(tag).png").path) { continue }
            _ = i
            tv.setSelectedRange(NSRange(location: e.range.location + min(1, e.range.length), length: 0))
            tv.scrollRangeToVisible(e.range)
            snapshot(editor, "\(base)-caret-\(tag)")
            log("\(base): caret at \(tag) line: \(ns.substring(with: ns.lineRange(for: e.range)).trimmingCharacters(in: .newlines))")
        }
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        if base == "Welcome" { formattingTest(editor) }
    }

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        log("format-test \(name): \(ok ? "PASS" : "FAIL") \(detail)")
    }

    /// Hugo site: detection, link resolution, link writing and `hugo server` preview.
    private static func hugoTest(_ editor: EditorWindowController, done: @escaping () -> Void) {
        guard let tv = editor.textView else { done(); return }
        check("hugo-site", editor.site != nil, editor.site?.root.path ?? "nil")
        guard let site = editor.site else { done(); return }
        check("hugo-style", editor.conventions?.style == .relref, String(describing: editor.conventions))

        let ctx = editor.linkContext
        var resolved: [String: Bool] = [:]
        for e in editor.styler.elements {
            guard let l = e.link else { continue }
            let u = ctx.resolve(l)
            resolved[l.target] = u != nil
            log("hugo link \(l.style) \(l.target) → \(u?.path ?? "nil")")
        }
        check("hugo-resolve", resolved["/posts/second"] == true && resolved["/about"] == true
              && resolved["/posts/future"] == false, String(describing: resolved))

        var hasImage = false
        tv.textStorage?.enumerateAttribute(.sdImage, in: NSRange(location: 0, length: tv.string.utf16.count)) { v, _, _ in
            if v != nil { hasImage = true }
        }
        check("hugo-figure", hasImage)
        let siteTitle = editor.statusBar?.siteButton.itemTitle(at: 0) ?? ""
        check("hugo-statusbar", editor.statusBar?.siteButton.isHidden == false && siteTitle.contains("relref"), siteTitle)
        snapshot(editor, "Hugo-first")

        let original = tv.string
        let end = (original as NSString).length
        // ⌘K writes the project's convention
        tv.setSelectedRange(NSRange(location: end, length: 0))
        editor.formatLink(nil)
        let added1 = (tv.string as NSString).substring(from: end)
        check("hugo-cmdK", added1 == "[]({{< relref \"\" >}})", added1.debugDescription)
        editor.replace(NSRange(location: 0, length: (tv.string as NSString).length), with: original, actionName: "")

        // Link to page
        tv.setSelectedRange(NSRange(location: end, length: 0))
        editor.insertPageLink(to: site.contentDir.appendingPathComponent("posts/second/index.md"))
        let added2 = (tv.string as NSString).substring(from: end)
        check("hugo-pagelink", added2 == "[Second Post]({{< relref \"/posts/second\" >}})", added2.debugDescription)
        editor.replace(NSRange(location: 0, length: (tv.string as NSString).length), with: original, actionName: "")
        check("hugo-restored", tv.string == original)

        // Preview with hugo server
        guard let page = editor.markdownDocument?.fileURL else { done(); return }
        HugoPreview.shared.baseURL(for: site) { base, output in
            guard let base, let url = HugoPreview.pageURL(page, site: site, base: base) else {
                if output.contains("not found") { log("format-test hugo-server: SKIP (hugo not installed)") }
                else { check("hugo-server", false, String(output.suffix(800)).debugDescription) }
                done()
                return
            }
            log("hugo server at \(base) → \(url)")
            URLSession.shared.dataTask(with: url) { data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let body = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                DispatchQueue.main.async {
                    check("hugo-server", status == 200 && body.contains("First Post") && body.contains("/posts/second/"),
                          "status \(status) \(error.map { "\($0)" } ?? "")")
                    previewPaneTest(editor) {
                        HugoPreview.shared.stopAll()
                        done()
                    }
                }
            }.resume()
        }
    }

    /// Preview pane: loads the page from hugo server and live-reloads after an edit.
    private static func previewPaneTest(_ editor: EditorWindowController, done: @escaping () -> Void) {
        guard let tv = editor.textView, let pane = editor.previewPane else { done(); return }
        var finished = false
        func finish() {
            guard !finished else { return }
            finished = true
            pane.onLoad = nil
            done()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            if !finished { check("pane-timeout", false); finish() }
        }
        let original = tv.string
        var loads = 0
        pane.onLoad = {
            loads += 1
            if loads == 1 {
                let path = pane.webView.url?.path ?? ""
                check("pane-load", path == "/posts/first/", path)
                pane.webView.evaluateJavaScript("document.title") { title, _ in
                    check("pane-title", (title as? String)?.contains("First Post") == true, String(describing: title))
                    // Edit → autosave → hugo rebuild → live reload
                    let end = (tv.string as NSString).length
                    editor.replace(NSRange(location: end, length: 0), with: "\n\nLive edit marker 4711\n", actionName: "")
                }
            } else {
                pane.webView.evaluateJavaScript("document.body.innerText") { text, _ in
                    let ok = (text as? String)?.contains("Live edit marker 4711") == true
                    guard ok || loads > 4 else { return }   // wait for the reload that has the edit
                    check("pane-livereload", ok, "after \(loads) loads")
                    paneSnapshot(editor) {
                        editor.replace(NSRange(location: 0, length: (tv.string as NSString).length), with: original, actionName: "")
                        editor.markdownDocument?.autosave(withImplicitCancellability: false) { _ in
                            DispatchQueue.main.async { finish() }
                        }
                    }
                }
            }
        }
        editor.togglePreviewPane(nil)
        check("pane-visible", editor.isPreviewVisible)
    }

    /// Window with the web view composited in (WKWebView draws out of process).
    private static func paneSnapshot(_ editor: EditorWindowController, done: @escaping () -> Void) {
        guard let pane = editor.previewPane, let frameView = editor.window?.contentView?.superview else { done(); return }
        pane.webView.takeSnapshot(with: nil) { image, _ in
            frameView.display()
            if let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
                frameView.cacheDisplay(in: frameView.bounds, to: rep)
                let out = NSImage(size: frameView.bounds.size)
                out.addRepresentation(rep)
                if let image {
                    out.lockFocusFlipped(frameView.isFlipped)
                    let r = pane.webView.convert(pane.webView.bounds, to: frameView)
                    image.draw(in: r)
                    out.unlockFocus()
                }
                if let tiff = out.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff),
                   let png = bmp.representation(using: .png, properties: [:]) {
                    try? png.write(to: outDir.appendingPathComponent("Hugo-pane.png"))
                    log("autotest: wrote Hugo-pane.png")
                }
            }
            done()
        }
    }

    /// Formatting commands round-trip (toggle twice = original) and the status bar.
    private static func formattingTest(_ editor: EditorWindowController) {
        guard let tv = editor.textView else { return }
        func line(containing needle: String) -> NSRange? {
            let ns = tv.string as NSString
            let r = ns.range(of: needle)
            return r.location == NSNotFound ? nil : ns.lineRange(for: r)
        }

        let original = tv.string
        // Bold a word
        let ns = tv.string as NSString
        let word = ns.range(of: "# Welcome to Slopdown")
        tv.setSelectedRange(NSRange(location: word.location + 2, length: 7))
        editor.formatBold(nil)
        let l1 = line(containing: "# **Welcome** to Slopdown").map { (tv.string as NSString).substring(with: $0) } ?? "(not found)"
        check("bold", l1.hasPrefix("# **Welcome** to Slopdown"), l1.debugDescription)
        snapshot(editor, "Welcome-format-bold")
        editor.formatBold(nil)
        check("unbold", tv.string == original)

        // Bullet list on a paragraph line, then off again
        if let r = line(containing: "a link to open it") {
            tv.setSelectedRange(NSRange(location: r.location + 3, length: 0))
            editor.formatBulletList(nil)
            let l2 = line(containing: "a link to open it").map { (tv.string as NSString).substring(with: $0) } ?? ""
            check("bullet", l2.hasPrefix("- "), l2.debugDescription)
            editor.formatBulletList(nil)
            check("unbullet", tv.string == original)
        }

        // Heading 2 on the same line
        if let r = line(containing: "a link to open it") {
            tv.setSelectedRange(NSRange(location: r.location, length: 0))
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.tag = 2
            editor.formatHeading(item)
            let l3 = line(containing: "a link to open it").map { (tv.string as NSString).substring(with: $0) } ?? ""
            check("heading", l3.hasPrefix("## "), l3.debugDescription)
            editor.formatHeading(item)
            check("unheading", tv.string == original)
        }

        // About window with the vibe-coded notice
        (NSApp.delegate as? AppDelegate)?.showAbout(nil)
        if let about = NSApp.windows.first(where: { $0.isVisible && $0 !== editor.window && $0.contentView != nil }),
           let view = about.contentView?.superview ?? about.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.display()
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent("About.png"))
            log("autotest: wrote About.png")
            about.close()
        }
        check("disclaimer", Disclaimer.text(for: ["tr"]).hasPrefix("Bu uygulama"))

        let info = editor.statusBar?.infoLabel.stringValue ?? ""
        check("statusbar", info.contains("words") && info.contains("Ln "), info.debugDescription)
        let path = editor.statusBar?.pathButton.title ?? ""
        check("statuspath", path.hasSuffix("Welcome.md"), path.debugDescription)
    }

    private static func snapshot(_ editor: EditorWindowController, _ name: String) {
        // The window's frame view, so the toolbar is in the picture too.
        guard let view = editor.window?.contentView?.superview ?? editor.window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        view.display()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = outDir.appendingPathComponent("\(name).png")
        try? png.write(to: url)
        log("autotest: wrote \(url.lastPathComponent)")
    }

    static func log(_ s: String) {
        FileHandle.standardOutput.write((s + "\n").data(using: .utf8)!)
    }
}
#endif
