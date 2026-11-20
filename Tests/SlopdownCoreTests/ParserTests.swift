// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import SlopdownCore

final class ParserTests: XCTestCase {

    private func sub(_ text: String, _ r: NSRange) -> String { NSString(string: text).substring(with: r) }

    private func elements(_ text: String, where pred: (MDElement) -> Bool) -> [MDElement] {
        MarkdownParser.parse(text).filter(pred)
    }

    func testHeading() {
        let t = "## Hello *world*"
        let els = MarkdownParser.parse(t)
        let h = els.first { if case .heading(2) = $0.kind { return true }; return false }!
        XCTAssertEqual(sub(t, h.hidden[0]), "## ")
        XCTAssertEqual(sub(t, h.content), "Hello *world*")
        let it = els.first { $0.kind == .italic }!
        XCTAssertEqual(sub(t, it.content), "world")
        XCTAssertEqual(it.hidden.map { sub(t, $0) }, ["*", "*"])
    }

    func testNotHeadingWithoutSpace() {
        XCTAssertTrue(elements("#tag here") { if case .heading = $0.kind { return true }; return false }.isEmpty)
    }

    func testEmphasisVariants() {
        let t = "a **bold** b *it* c ***both*** d ~~gone~~ e __b2__ f _i2_ g snake_case_name"
        let els = MarkdownParser.parse(t)
        XCTAssertEqual(els.filter { $0.kind == .bold }.map { sub(t, $0.content) }, ["bold", "b2"])
        XCTAssertEqual(els.filter { $0.kind == .italic }.map { sub(t, $0.content) }, ["it", "i2"])
        XCTAssertEqual(els.filter { $0.kind == .boldItalic }.map { sub(t, $0.content) }, ["both"])
        XCTAssertEqual(els.filter { $0.kind == .strikethrough }.map { sub(t, $0.content) }, ["gone"])
    }

    func testNestedEmphasis() {
        let t = "**bold *ital* bold**"
        let els = MarkdownParser.parse(t)
        XCTAssertEqual(els.filter { $0.kind == .bold }.count, 1)
        XCTAssertEqual(els.filter { $0.kind == .italic }.map { sub(t, $0.content) }, ["ital"])
    }

    func testCodeSpanProtectsContent() {
        let t = "x `a **b** [[c]]` y"
        let els = MarkdownParser.parse(t)
        XCTAssertEqual(els.count, 1)
        XCTAssertEqual(els[0].kind, .inlineCode)
        XCTAssertEqual(sub(t, els[0].content), "a **b** [[c]]")
    }

    func testWikiLink() {
        let t = "see [[Folder/My Note#Part|the note]] now"
        let l = MarkdownParser.parse(t).compactMap { $0.link }.first!
        XCTAssertEqual(l.style, .wiki)
        XCTAssertEqual(l.target, "Folder/My Note")
        XCTAssertEqual(l.heading, "Part")
        XCTAssertEqual(sub(t, l.targetRange), "Folder/My Note")
        let e = MarkdownParser.parse(t).first { $0.link != nil }!
        XCTAssertEqual(sub(t, e.content), "the note")
        XCTAssertEqual(Set(e.hidden.map { sub(t, $0) }), Set(["[[", "]]", "Folder/My Note#Part|"]))
    }

    func testMarkdownLink() {
        let t = "a [My **text**](sub/My%20File.md \"title\") b"
        let els = MarkdownParser.parse(t)
        let e = els.first { $0.link != nil }!
        XCTAssertEqual(e.link!.target, "sub/My File.md")
        XCTAssertEqual(sub(t, e.link!.targetRange), "sub/My%20File.md")
        XCTAssertEqual(sub(t, e.content), "My **text**")
        XCTAssertEqual(els.filter { $0.kind == .bold }.count, 1)
    }

    func testAngleDestination() {
        let t = "[x](<a b.md>)"
        XCTAssertEqual(MarkdownParser.parse(t).compactMap { $0.link }.first?.target, "a b.md")
    }

    func testBareURL() {
        let t = "go to https://example.com/x, then"
        let l = MarkdownParser.parse(t).compactMap { $0.link }.first!
        XCTAssertEqual(l.style, .bareURL)
        XCTAssertEqual(l.target, "https://example.com/x")
    }

    func testURLInsideMarkdownLinkIsNotBare() {
        let t = "[site](https://example.com)"
        let links = MarkdownParser.parse(t).compactMap { $0.link }
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].style, .markdown)
    }

    func testImages() {
        let t = "![[pics/cat.png|300]]\ntext ![alt|200x100](img/dog%201.jpg) more\n![[Other note]]\n![r](https://x.org/a.png)"
        let imgs = MarkdownParser.parse(t).compactMap { $0.image }
        XCTAssertEqual(imgs.count, 3)
        XCTAssertEqual(imgs[0].source, "pics/cat.png")
        XCTAssertEqual(imgs[0].width, 300)
        XCTAssertNil(imgs[0].height)
        XCTAssertTrue(imgs[0].standalone)
        XCTAssertEqual(imgs[1].source, "img/dog 1.jpg")
        XCTAssertEqual(imgs[1].width, 200)
        XCTAssertEqual(imgs[1].height, 100)
        XCTAssertFalse(imgs[1].standalone)
        XCTAssertTrue(imgs[2].isRemote)
        let embed = MarkdownParser.parse(t).compactMap { $0.link }.first { $0.style == .embed }
        XCTAssertEqual(embed?.target, "Other note")
    }

    func testLists() {
        let t = "- item\n  * nested\n1. first\n- [ ] todo\n- [x] done **b**"
        let els = MarkdownParser.parse(t)
        let bullets = els.filter { $0.kind == .bulletItem }
        XCTAssertEqual(bullets.map { sub(t, $0.marker) }, ["-", "*"])
        XCTAssertEqual(els.filter { $0.kind == .orderedItem }.map { sub(t, $0.marker) }, ["1."])
        let tasks = els.filter { if case .task = $0.kind { return true }; return false }
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].kind, .task(checked: false))
        XCTAssertEqual(tasks[1].kind, .task(checked: true))
        XCTAssertEqual(sub(t, tasks[0].marker), "[ ]")
        XCTAssertEqual(sub(t, tasks[0].hidden[0]), "- ")
        XCTAssertEqual(sub(t, tasks[1].content), "done **b**")
        XCTAssertEqual(els.filter { $0.kind == .bold }.count, 1)
    }

    func testQuoteAndRule() {
        let t = "> quoted *x*\n\n---\n***"
        let els = MarkdownParser.parse(t)
        let q = els.first { $0.kind == .blockquote }!
        XCTAssertEqual(sub(t, q.hidden[0]), "> ")
        XCTAssertEqual(els.filter { $0.kind == .rule }.count, 2)
        XCTAssertEqual(els.filter { $0.kind == .italic }.count, 1)
    }

    func testFrontmatterAndFences() {
        let t = "---\ntitle: x\n---\n# H\n```swift\nlet **a** = 1\n```\nafter **b**"
        let els = MarkdownParser.parse(t)
        XCTAssertEqual(els.filter { $0.kind == .frontmatter }.count, 3)
        XCTAssertEqual(els.filter { $0.kind == .codeFence }.count, 2)
        XCTAssertEqual(els.filter { $0.kind == .codeLine }.count, 1)
        XCTAssertEqual(els.filter { $0.kind == .bold }.map { sub(t, $0.content) }, ["b"])
        XCTAssertEqual(els.filter { $0.kind == .rule }.count, 0)
    }

    func testUnclosedFrontmatterIsRule() {
        let els = MarkdownParser.parse("---\nhello")
        XCTAssertEqual(els.filter { $0.kind == .frontmatter }.count, 0)
        XCTAssertEqual(els.filter { $0.kind == .rule }.count, 1)
    }

    func testUnicodeOffsets() {
        let t = "😀 **çğü** [[Ölçü]]"
        let els = MarkdownParser.parse(t)
        XCTAssertEqual(sub(t, els.first { $0.kind == .bold }!.content), "çğü")
        XCTAssertEqual(els.compactMap { $0.link }.first?.target, "Ölçü")
    }

    func testTouches() {
        let r = NSRange(location: 5, length: 3)
        XCTAssertTrue(NSRange(location: 5, length: 0).touches(r))
        XCTAssertTrue(NSRange(location: 8, length: 0).touches(r))
        XCTAssertFalse(NSRange(location: 9, length: 0).touches(r))
        XCTAssertFalse(NSRange(location: 4, length: 0).touches(r))
    }

    func testEmptyAndTrailingNewline() {
        XCTAssertTrue(MarkdownParser.parse("").isEmpty)
        XCTAssertEqual(MarkdownParser.parse("# a\n").count, 1)
    }
}

final class LinkResolverTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sd-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("notes/deep/deeper"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("other"), withIntermediateDirectories: true)
        for f in ["notes/Index.md", "notes/Sibling.md", "notes/deep/Far Note.md", "notes/deep/deeper/Far Note.md",
                  "notes/deep/pic.png", "other/Outside.md"] {
            try Data().write(to: root.appendingPathComponent(f))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testResolve() {
        let base = root.appendingPathComponent("notes")
        XCTAssertEqual(LinkResolver.resolve(target: "Sibling", relativeTo: base)?.lastPathComponent, "Sibling.md")
        XCTAssertEqual(LinkResolver.resolve(target: "Sibling.md", relativeTo: base)?.lastPathComponent, "Sibling.md")
        // Found in a subfolder, shallowest wins
        XCTAssertEqual(LinkResolver.resolve(target: "far note", relativeTo: base)?.path,
                       root.appendingPathComponent("notes/deep/Far Note.md").standardizedFileURL.path)
        XCTAssertEqual(LinkResolver.resolve(target: "pic.png", relativeTo: base)?.lastPathComponent, "pic.png")
        XCTAssertEqual(LinkResolver.resolve(target: "deeper/Far Note", relativeTo: base)?.path,
                       root.appendingPathComponent("notes/deep/deeper/Far Note.md").standardizedFileURL.path)
        // Parent folders are only reachable with an explicit relative path
        XCTAssertNil(LinkResolver.resolve(target: "Outside", relativeTo: base))
        XCTAssertNotNil(LinkResolver.resolve(target: "../other/Outside.md", relativeTo: base))
        XCTAssertNil(LinkResolver.resolve(target: "Missing", relativeTo: base))
        XCTAssertNil(LinkResolver.resolve(target: "https://x.org", relativeTo: base))
    }

    func testExternal() {
        XCTAssertTrue(LinkResolver.isExternal("https://a.b"))
        XCTAssertTrue(LinkResolver.isExternal("mailto:a@b.c"))
        XCTAssertFalse(LinkResolver.isExternal("notes/a.md"))
        XCTAssertFalse(LinkResolver.isExternal("C:/x"))
    }

    func testNewFileAndRelative() {
        let base = root.appendingPathComponent("notes")
        XCTAssertEqual(LinkResolver.newFileURL(for: "New", relativeTo: base).lastPathComponent, "New.md")
        XCTAssertEqual(LinkResolver.newFileURL(for: "sub/a.txt", relativeTo: base).path,
                       base.appendingPathComponent("sub/a.txt").standardizedFileURL.path)
        let other = root.appendingPathComponent("other/Outside.md")
        XCTAssertEqual(LinkResolver.relativePath(from: base, to: other), "../other/Outside.md")
        XCTAssertEqual(LinkResolver.linkTarget(for: other, relativeTo: base, wikiStyle: true), "../other/Outside")
        let far = root.appendingPathComponent("notes/deep/Far Note.md")
        XCTAssertEqual(LinkResolver.linkTarget(for: far, relativeTo: base, wikiStyle: false), "deep/Far%20Note.md")
    }
}

final class TableTests: XCTestCase {
    private func sub(_ text: String, _ r: NSRange) -> String { NSString(string: text).substring(with: r) }

    func testTable() {
        let t = "| Name | Dose `a|b` | [[x|y]] |\n|:--|:-:|--:|\n| **A** | 5 mg | z |\nb | c\n\nafter"
        let els = MarkdownParser.parse(t)
        let rows = els.compactMap { e -> MDTableRow? in if case .tableRow(let r) = e.kind { return r }; return nil }
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].cells.map { sub(t, $0) }, ["Name", "Dose `a|b`", "[[x|y]]"])
        XCTAssertEqual(rows[0].alignments, [.left, .center, .right])
        XCTAssertEqual(rows[0].pipes.count, 2)
        XCTAssertTrue(rows[0].leadingPipe && rows[0].trailingPipe)
        XCTAssertEqual(rows[1].cells.map { sub(t, $0) }, ["**A**", "5 mg", "z"])
        XCTAssertEqual(rows[2].cells.map { sub(t, $0) }, ["b", "c"])
        XCTAssertFalse(rows[2].leadingPipe)
        XCTAssertTrue(rows[2].isLast)
        XCTAssertEqual(els.filter { if case .tableDelimiter = $0.kind { return true }; return false }.count, 1)
        XCTAssertEqual(els.filter { $0.kind == .bold }.count, 1)
        XCTAssertEqual(els.filter { $0.kind == .inlineCode }.count, 1)
        XCTAssertEqual(els.compactMap { $0.link }.first?.target, "x")
        // Hidden: everything but cells and inner pipes
        let row0 = els.first { if case .tableRow = $0.kind { return true }; return false }!
        XCTAssertEqual(row0.hidden.map { sub(t, $0) }, [" ", " ", " ", " ", " ", " |"])
        XCTAssertEqual(row0.tableRow?.leading.map { sub(t, $0) }, "|")
    }

    func testNotATable() {
        let t = "a | b\nnot a delimiter"
        XCTAssertTrue(MarkdownParser.parse(t).allSatisfy { if case .tableRow = $0.kind { return false }; return true })
        let t2 = "| a | b |\n|---|\n"
        XCTAssertTrue(MarkdownParser.parse(t2).allSatisfy { if case .tableRow = $0.kind { return false }; return true })
    }
}

final class EscapedAliasTests: XCTestCase {
    func testEscapedPipeInWikiLink() {
        let t = "| a |\n|---|\n| [[Note\\|alias]] |"
        XCTAssertEqual(MarkdownParser.parse(t).compactMap { $0.link }.first?.target, "Note")
    }
}
