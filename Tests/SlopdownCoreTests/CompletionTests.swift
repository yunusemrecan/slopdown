// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import SlopdownCore

final class CompletionTests: XCTestCase {
    private func ctx(_ s: String, hugo: Bool = false) -> CompletionContext? {
        let ns = NSString(string: s.replacingOccurrences(of: "|^|", with: ""))
        let caret = (s as NSString).range(of: "|^|").location
        return Completion.context(in: ns, caret: caret, hugo: hugo)
    }

    func testContexts() {
        XCTAssertEqual(ctx("see [[No|^|")?.kind, .wiki(embed: false))
        XCTAssertEqual(ctx("see [[No|^|")?.partial, NSRange(location: 6, length: 2))
        XCTAssertEqual(ctx("![[pi|^|")?.kind, .wiki(embed: true))
        XCTAssertEqual(ctx("[[|^|")?.partial.length, 0)
        XCTAssertNil(ctx("[[Note]] more|^|"))
        XCTAssertNil(ctx("[[Note|ali|^|"))
        XCTAssertNil(ctx("[[a]]\n|^|"))
        XCTAssertEqual(ctx(#"[x]({{< relref "/po|^|" >}})"#, hugo: true)?.kind, .hugoRef)
        XCTAssertEqual(ctx(#"[x]({{< relref "/po|^|" >}})"#, hugo: true)?.partial.length, 3)
        XCTAssertNil(ctx(#"[x]({{< relref "/po|^|" >}})"#, hugo: false))
        XCTAssertEqual(ctx("[x](/po|^|", hugo: true)?.kind, .markdownLink)
        XCTAssertNil(ctx("[x](https://a|^|", hugo: true))
        XCTAssertNil(ctx("[x](/po|^|", hugo: false))
    }

    func testItemsPlainFolder() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cmp-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        for f in ["Index.md", "Project Plan.md", "sub/Notes.md", "other/Notes.md", "img/cat.png"] {
            let u = root.appendingPathComponent(f)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: u)
        }
        let doc = root.appendingPathComponent("Index.md")
        let pages = Completion.index(root: root, includeImages: true, readTitles: false)
        let context = LinkContext(document: doc)
        let plan = Completion.items(for: .wiki(embed: false), typed: "plan", pages: pages, context: context)
        XCTAssertEqual(plan.first?.insert, "Project Plan")
        // Duplicate names get a path
        let notes = Completion.items(for: .wiki(embed: false), typed: "notes", pages: pages, context: context)
        XCTAssertEqual(Set(notes.map { $0.insert }), ["sub/Notes", "other/Notes"])
        // The note itself is not offered; images are
        XCTAssertFalse(Completion.items(for: .wiki(embed: false), typed: "", pages: pages, context: context).contains { $0.insert == "Index" })
        XCTAssertEqual(Completion.items(for: .wiki(embed: true), typed: "cat", pages: pages, context: context).first?.insert, "cat.png")
        // Fuzzy
        XCTAssertEqual(Completion.items(for: .wiki(embed: false), typed: "prjpl", pages: pages, context: context).first?.insert, "Project Plan")
    }

    func testItemsHugo() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cmph-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        func write(_ p: String, _ t: String) throws {
            let u = root.appendingPathComponent(p)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try t.write(to: u, atomically: true, encoding: .utf8)
        }
        try write("hugo.toml", "baseURL = 'x'\n")
        try write("content/posts/a.md", "+++\ntitle = 'Alpha Post'\n+++\n[b]({{< relref \"/posts/b\" >}})")
        try write("content/posts/b/index.md", "+++\ntitle = 'Beta'\n+++\n")
        let a = root.appendingPathComponent("content/posts/a.md")
        let context = LinkContext(document: a, site: HugoSite.containing(a))
        let pages = Completion.index(root: context.site!.contentDir, includeImages: false, readTitles: true)
        let ref = Completion.items(for: .hugoRef, typed: "bet", pages: pages, context: context)
        XCTAssertEqual(ref.first?.title, "Beta")
        XCTAssertEqual(ref.first?.insert, "/posts/b")
        let md = Completion.items(for: .markdownLink, typed: "beta", pages: pages, context: context)
        XCTAssertEqual(md.first?.insert, "b/index.md")
        XCTAssertEqual(Completion.closing(for: .hugoRef, after: "\" >}})"), "")
        XCTAssertEqual(Completion.closing(for: .wiki(embed: false), after: " more"), "]]")
    }
}

final class AttachmentTests: XCTestCase {
    func testFoldersAndCopying() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("att-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        func write(_ p: String, _ t: String = "") throws {
            let u = root.appendingPathComponent(p)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try t.write(to: u, atomically: true, encoding: .utf8)
        }
        try write("site/hugo.toml", "baseURL = 'x'\n")
        try write("site/content/posts/a.md")
        try write("site/content/posts/b/index.md")
        try write("notes/n.md")
        let a = root.appendingPathComponent("site/content/posts/a.md")
        let b = root.appendingPathComponent("site/content/posts/b/index.md")
        let n = root.appendingPathComponent("notes/n.md")
        let site = HugoSite.containing(a)
        XCTAssertEqual(Attachments.folder(for: a, site: site).path,
                       root.appendingPathComponent("site/static/images").standardizedFileURL.path)
        XCTAssertEqual(Attachments.folder(for: b, site: site).path, b.deletingLastPathComponent().path)
        XCTAssertEqual(Attachments.folder(for: n, site: nil).path, n.deletingLastPathComponent().path)

        XCTAssertFalse(Attachments.shouldCopy(root.appendingPathComponent("notes/pics/x.png"), document: n, site: nil))
        XCTAssertTrue(Attachments.shouldCopy(root.appendingPathComponent("elsewhere/x.png"), document: n, site: nil))
        XCTAssertFalse(Attachments.shouldCopy(root.appendingPathComponent("site/static/img/x.png"), document: a, site: site))
        XCTAssertTrue(Attachments.shouldCopy(root.appendingPathComponent("site/content/posts/x.png"), document: a, site: site))
        XCTAssertFalse(Attachments.shouldCopy(root.appendingPathComponent("site/content/posts/b/x.png"), document: b, site: site))

        try write("notes/pasted.png")
        XCTAssertEqual(Attachments.uniqueURL(for: "pasted.png", in: root.appendingPathComponent("notes")).lastPathComponent,
                       "pasted-2.png")
        XCTAssertTrue(Attachments.pastedImageName(date: Date(timeIntervalSince1970: 0)).hasPrefix("pasted-image-19"))
    }
}
