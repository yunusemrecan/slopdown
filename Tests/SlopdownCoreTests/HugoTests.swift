// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import SlopdownCore

final class HugoParserTests: XCTestCase {
    private func sub(_ t: String, _ r: NSRange) -> String { NSString(string: t).substring(with: r) }

    func testTomlFrontMatter() {
        let t = "+++\ntitle = 'x'\n+++\n# H"
        let els = MarkdownParser.parse(t)
        XCTAssertEqual(els.filter { $0.kind == .frontmatter }.count, 3)
        XCTAssertEqual(els.filter { if case .heading = $0.kind { return true }; return false }.count, 1)
    }

    func testRefLinks() {
        let t = #"See [the post]({{< relref "/posts/foo.md#sec" >}}) and [x]({{% ref "bar" %}})."#
        let links = MarkdownParser.parse(t).compactMap { $0.link }
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links[0].style, .hugoRef)
        XCTAssertEqual(links[0].target, "/posts/foo.md")
        XCTAssertEqual(links[0].heading, "sec")
        XCTAssertEqual(sub(t, links[0].targetRange), "/posts/foo.md#sec")
        XCTAssertEqual(links[1].target, "bar")
        let e = MarkdownParser.parse(t).first { $0.link != nil }!
        XCTAssertEqual(sub(t, e.content), "the post")
    }

    func testShortcodesAndFigure() {
        let t = "{{< figure src=\"/images/cat.png\" width=\"300\" alt=\"c\" >}}\ntext {{< youtube abc >}} **b**\n{{% notice %}}"
        let els = MarkdownParser.parse(t)
        let img = els.compactMap { $0.image }.first
        XCTAssertEqual(img?.source, "/images/cat.png")
        XCTAssertEqual(img?.width, 300)
        XCTAssertEqual(img?.standalone, true)
        let names = els.compactMap { e -> String? in if case .shortcode(let n) = e.kind { return n }; return nil }
        XCTAssertEqual(names, ["youtube", "notice"])
        XCTAssertEqual(els.filter { $0.kind == .bold }.count, 1)
    }
}

final class HugoSiteTests: XCTestCase {
    var root: URL!
    let fm = FileManager.default

    private func write(_ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("hugo-\(UUID().uuidString)")
        try write("hugo.toml", "baseURL = 'https://example.org/'\ntitle = 'x'\n")
        try write("archetypes/default.md", "+++\ntitle = 'x'\n+++\n")
        try write("content/_index.md", "+++\ntitle = 'Home'\n+++\n")
        try write("content/posts/first.md", "+++\ntitle = 'First Post'\n+++\nSee [second]({{< relref \"/posts/second\" >}}) and [b]({{< relref \"/about\" >}}).\n")
        try write("content/posts/second/index.md", "+++\ntitle = 'Second'\n+++\n![](cat.png)\n")
        try write("content/posts/second/cat.png", "")
        try write("content/about.md", "---\ntitle: About\n---\n")
        try write("static/images/logo.png", "")
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    func testDetection() throws {
        let first = root.appendingPathComponent("content/posts/first.md")
        let site = try XCTUnwrap(HugoSite.containing(first))
        XCTAssertEqual(site.root.path, root.standardizedFileURL.path)
        XCTAssertEqual(site.detected.style, .relref)
        XCTAssertEqual(site.detected.shortcodeDelimiter, "<")
        XCTAssertFalse(site.detected.refUsesFiles)
        XCTAssertTrue(site.detected.tomlFrontMatter)
        XCTAssertFalse(site.hasLinkRenderHook)
        // Outside content/: not a site page
        XCTAssertNil(HugoSite.containing(root.appendingPathComponent("archetypes/default.md")))
    }

    func testRenderHookDefaultsToLogicalPaths() throws {
        try write("hugo.toml", "baseURL = 'x'\n[markup.goldmark.renderHooks.link]\nenableDefault = true\n")
        try write("content/posts/first.md", "no links\n")
        let site = try XCTUnwrap(HugoSite.containing(root.appendingPathComponent("content/posts/first.md")))
        XCTAssertTrue(site.hasLinkRenderHook)
        XCTAssertEqual(site.detected.style, .logicalPath)
    }

    func testDetectsRelativeFiles() throws {
        try write("content/posts/first.md", "[a](second/index.md) [b](../about.md) [c](https://x.org)\n")
        let site = try XCTUnwrap(HugoSite.containing(root.appendingPathComponent("content/posts/first.md")))
        XCTAssertEqual(site.detected.style, .relativeFile)
    }

    func testNotZola() throws {
        try write("config.toml", "base_url = 'x'\n")
        try fm.removeItem(at: root.appendingPathComponent("hugo.toml"))
        XCTAssertNil(HugoSite.at(root))
    }

    func testResolveAndWrite() throws {
        let first = root.appendingPathComponent("content/posts/first.md")
        let site = try XCTUnwrap(HugoSite.containing(first))
        let second = root.appendingPathComponent("content/posts/second/index.md").standardizedFileURL
        XCTAssertEqual(site.resolvePage("/posts/second", from: first), second)
        XCTAssertEqual(site.resolvePage("/posts/second/", from: first), second)
        XCTAssertEqual(site.resolvePage("second", from: first), second)
        XCTAssertEqual(site.resolvePage("second/index.md#x", from: first), second)
        XCTAssertEqual(site.resolvePage("/about", from: first)?.lastPathComponent, "about.md")
        XCTAssertEqual(site.resolvePage("about", from: first)?.lastPathComponent, "about.md")
        XCTAssertEqual(site.resolvePage("/", from: first)?.lastPathComponent, "_index.md")
        XCTAssertNil(site.resolvePage("/nope", from: first))
        XCTAssertEqual(site.resolveResource("/images/logo.png", from: first)?.lastPathComponent, "logo.png")
        XCTAssertEqual(site.resolveResource("cat.png", from: second)?.lastPathComponent, "cat.png")

        XCTAssertEqual(site.logicalPath(of: second), "/posts/second")
        let c = site.detected
        XCTAssertEqual(site.destination(for: second, from: first, conventions: c), #"{{< relref "/posts/second" >}}"#)
        var files = c; files.refUsesFiles = true; files.shortcodeDelimiter = "%"
        XCTAssertEqual(site.destination(for: second, from: first, conventions: files), #"{{% relref "/posts/second/index.md" %}}"#)
        var logical = c; logical.style = .logicalPath
        XCTAssertEqual(site.destination(for: second, from: first, conventions: logical), "/posts/second")
        var rel = c; rel.style = .relativeFile
        XCTAssertEqual(site.destination(for: second, from: first, conventions: rel), "second/index.md")
        XCTAssertEqual(site.imageDestination(for: root.appendingPathComponent("static/images/logo.png"), from: first), "/images/logo.png")

        XCTAssertEqual(site.newPageURL(for: "/posts/new-one", from: first).path,
                       root.appendingPathComponent("content/posts/new-one.md").standardizedFileURL.path)
        let fmText = HugoSite.frontMatter(for: URL(fileURLWithPath: "/x/my-new_post.md"), toml: true)
        XCTAssertTrue(fmText.hasPrefix("+++\ntitle = 'My New Post'\ndate = "))
        XCTAssertTrue(fmText.contains("draft = true"))
        XCTAssertEqual(HugoSite.title(ofPageText: "+++\ntitle = 'First Post'\n+++\n"), "First Post")
        XCTAssertEqual(HugoSite.title(ofPageText: "---\ntitle: \"About\"\n---\n"), "About")
    }
}

final class LinkContextTests: XCTestCase {
    func testContextInHugoSite() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ctx-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        func write(_ p: String, _ t: String) throws {
            let u = root.appendingPathComponent(p)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try t.write(to: u, atomically: true, encoding: .utf8)
        }
        try write("hugo.toml", "baseURL = 'x'\n")
        try write("content/posts/a.md", "[b]({{% relref \"/posts/b\" %}})")
        try write("content/posts/b.md", "")
        try write("static/img/x.png", "")
        let a = root.appendingPathComponent("content/posts/a.md")
        let ctx = LinkContext(document: a, site: HugoSite.containing(a))
        XCTAssertNotNil(ctx.site)
        let text = "[b]({{% relref \"/posts/b#top\" %}}) [c](/posts/b) ![i](/img/x.png) [[b]]"
        let els = MarkdownParser.parse(text)
        let links = els.compactMap { $0.link }.sorted { $0.targetRange.location < $1.targetRange.location }
        XCTAssertEqual(links.map { ctx.resolve($0)?.lastPathComponent }, ["b.md", "b.md", "b.md"])
        XCTAssertEqual(ctx.resolveImage(els.compactMap { $0.image }[0])?.lastPathComponent, "x.png")
        let b = root.appendingPathComponent("content/posts/b.md")
        XCTAssertEqual(ctx.retarget(links[0], to: b), "/posts/b#top")
        XCTAssertEqual(ctx.retarget(links[1], to: b), "b.md")
        XCTAssertEqual(ctx.pageLink(text: "B", to: b), "[B]({{% relref \"/posts/b\" %}})")
        XCTAssertEqual(ctx.imageLink(to: root.appendingPathComponent("static/img/x.png")), "![](/img/x.png)")
        let (s, caret) = ctx.emptyLink(text: "t")
        XCTAssertEqual(s, "[t]({{% relref \"\" %}})")
        XCTAssertEqual((s as NSString).substring(from: caret), "\" %}})")
        XCTAssertTrue(ctx.newFileContents(for: b).hasPrefix("+++"))

        // Outside a site: Obsidian behaviour
        let plain = LinkContext(document: a)
        XCTAssertEqual(plain.pageLink(text: "", to: b), "[[b]]")
        XCTAssertEqual(plain.emptyLink(text: "").0, "[]()")
    }
}

final class HugoListTests: XCTestCase {
    func testCSV() {
        let rows = HugoSite.parseCSV("a,b,c\n\"x, y\",\"he said \"\"hi\"\"\",\n")
        XCTAssertEqual(rows, [["a", "b", "c"], ["x, y", "he said \"hi\"", ""]])
    }

    func testPagePaths() {
        let root = URL(fileURLWithPath: "/site")
        var site = HugoSite(root: root, contentDir: root.appendingPathComponent("content"), staticDirs: [],
                            assetsDir: root.appendingPathComponent("assets"), hasLinkRenderHook: false,
                            detected: HugoConventions(style: .relref))
        site.baseURL = "https://example.org/blog/"
        let out = """
        path,slug,title,date,expiryDate,publishDate,draft,permalink,kind,section
        content/posts/first.md,,"First, Post",2026-11-21T10:00:00+03:00,,,false,https://example.org/blog/posts/first/,page,posts
        content/posts/second/index.md,my-slug,Second,2026-11-20T10:00:00+03:00,,,false,https://example.org/blog/posts/my-slug/,page,posts
        content/_index.md,,Home,,,,false,https://example.org/blog/,home,
        """
        let paths = site.pagePaths(fromListOutput: out)
        XCTAssertEqual(paths["/site/content/posts/first.md"], "posts/first/")
        XCTAssertEqual(paths["/site/content/posts/second/index.md"], "posts/my-slug/")
        XCTAssertEqual(paths["/site/content/_index.md"], "")
    }
}
