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
                doc?.close()
                step(files, i + 1)
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

    /// Formatting commands round-trip (toggle twice = original) and the status bar.
    private static func formattingTest(_ editor: EditorWindowController) {
        guard let tv = editor.textView else { return }
        func line(containing needle: String) -> NSRange? {
            let ns = tv.string as NSString
            let r = ns.range(of: needle)
            return r.location == NSNotFound ? nil : ns.lineRange(for: r)
        }
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            log("format-test \(name): \(ok ? "PASS" : "FAIL") \(detail)")
        }

        let original = tv.string
        // Bold a word
        let ns = tv.string as NSString
        let word = ns.range(of: "Welcome to Slopdown")
        tv.setSelectedRange(NSRange(location: word.location, length: 7))
        editor.formatBold(nil)
        let l1 = line(containing: "to Slopdown").map { (tv.string as NSString).substring(with: $0) } ?? ""
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
