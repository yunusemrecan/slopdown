// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import SlopdownCore

final class StylePlanTests: XCTestCase {
    private func plan(_ text: String, revealed: Bool = false, configure: (inout StylePlanner) -> Void = { _ in })
        -> [(String, StyleRole)] {
        var p = StylePlanner()
        configure(&p)
        let ns = NSString(string: text)
        return MarkdownParser.parse(text).flatMap { p.spans(for: $0, revealed: revealed, in: ns) }
            .map { (ns.substring(with: $0.range), $0.role) }
    }

    private func roles(_ spans: [(String, StyleRole)], _ text: String) -> [StyleRole] {
        spans.filter { $0.0 == text }.map { $0.1 }
    }

    func testEmphasisHiddenUnlessRevealed() {
        let hidden = plan("a **b** c")
        XCTAssertEqual(roles(hidden, "b"), [.bold])
        XCTAssertEqual(roles(hidden, "**"), [.hidden, .hidden])
        XCTAssertEqual(roles(plan("a **b** c", revealed: true), "**"), [.syntax, .syntax])
    }

    func testHeadingQuoteListsTasks() {
        let s = plan("# T\n> q\n- i\n1. n\n- [x] done\n---")
        XCTAssertEqual(roles(s, "# T"), [.heading(level: 1)])
        XCTAssertEqual(roles(s, "# "), [.hidden])
        XCTAssertEqual(roles(s, "> "), [.hidden])
        XCTAssertEqual(roles(s, "q"), [.secondary])
        XCTAssertEqual(roles(s, "-").first, .bullet)
        XCTAssertEqual(roles(s, "1."), [.secondary])
        XCTAssertEqual(roles(s, "[x]"), [.taskBox(checked: true)])
        XCTAssertEqual(roles(s, "done"), [.done])
        XCTAssertEqual(roles(s, "---"), [.rule])
    }

    func testCodeAndFrontMatterBackgrounds() {
        let s = plan("---\na: 1\n---\n```\nx\n```\n")
        XCTAssertTrue(roles(s, "a: 1").contains(.frontmatter))
        XCTAssertTrue(roles(s, "a: 1\n").contains(.blockBackground))
        XCTAssertTrue(roles(s, "x").contains(.codeLine(fence: false)))
        XCTAssertTrue(roles(s, "```").contains(.codeLine(fence: true)))
    }

    func testLinksLooks() {
        let target = URL(fileURLWithPath: "/n/Note.md")
        let resolved = plan("[[Note]] [[Missing]] https://x.org") { p in
            p.resolveLink = { $0.target == "Note" ? target : nil }
            p.isExternal = { $0.style == .bareURL }
        }
        XCTAssertEqual(roles(resolved, "Note"), [.link(.resolved)])
        XCTAssertEqual(roles(resolved, "Missing"), [.link(.unresolved)])
        XCTAssertEqual(roles(resolved, "https://x.org"), [.link(.resolved)])
        let hugo = plan("[[Note]]") { $0.isHugo = true }
        XCTAssertEqual(roles(hugo, "Note"), [.link(.hugoWikiWarning)])
    }

    func testImagesAndEmbeds() {
        let home = NSHomeDirectory()
        let img = URL(fileURLWithPath: home + "/n/p.png")
        let note = URL(fileURLWithPath: home + "/n/Other.md")
        let s = plan("![[p.png|100]]\ntext ![[p.png]] more\n![[Other#H]]\n![r](https://x/a.png)") { p in
            p.resolveImage = { _ in img }
            p.resolveLink = { $0.target == "Other" ? note : nil }
        }
        guard case .blockImage(let u, let w, _, let revealed, _) = roles(s, "![[p.png|100]]").first else {
            return XCTFail("no block image")
        }
        XCTAssertEqual(u, img); XCTAssertEqual(w, 100); XCTAssertFalse(revealed)
        guard case .inlineImage = roles(s, "![[p.png]]").first else { return XCTFail("no inline image") }
        guard case .embed(let eu, let h, _, let fallback) = roles(s, "![[Other#H]]").first else {
            return XCTFail("no embed")
        }
        XCTAssertEqual(eu, note); XCTAssertEqual(h, "H"); XCTAssertFalse(fallback.isEmpty)
        XCTAssertEqual(roles(s, "![r](https://x/a.png)"), [.secondary])   // remote: never loaded
        // Embeds never render from places LinkSafety forbids
        let secret = plan("![[.ssh/config.md]]") { p in p.resolveLink = { _ in URL(fileURLWithPath: home + "/.ssh/config.md") } }
        XCTAssertFalse(secret.contains { if case .embed = $0.1 { return true }; return false })
    }

    func testSourceModeShowsEverything() {
        let s = plan("# T **b** [[l]]") { $0.sourceMode = true }
        XCTAssertFalse(s.contains { $0.1 == .hidden })
        XCTAssertEqual(roles(s, "# T **b** [[l]]"), [.sourceHeading])
    }

    func testTableRole() {
        let s = plan("| a | b |\n|---|---|\n| 1 | 2 |")
        XCTAssertEqual(s.filter { if case .tableRow = $0.1 { return true }; return false }.count, 2)
        XCTAssertEqual(s.filter { if case .tableDelimiter = $0.1 { return true }; return false }.count, 1)
    }
}

final class HeadingSyncTests: XCTestCase {
    func testTitles() {
        let t = "# The **Big** [[Note|Plan]]\ntext\n## Details ##\n## details\n# The Big Plan"
        let h = HeadingSync.headings(MarkdownParser.parse(t), in: NSString(string: t))
        XCTAssertEqual(h.map { $0.title }, ["the big plan", "details", "details", "the big plan"])
        XCTAssertEqual(h.map { $0.occurrence }, [0, 0, 1, 1])
        XCTAssertEqual(h.map { $0.count }, [2, 2, 2, 2])
        XCTAssertEqual(h.map { $0.text }, ["The Big Plan", "Details", "details", "The Big Plan"])
        XCTAssertEqual(h.map { $0.level }, [1, 2, 2, 1])
        let names = ["Second Note", "Index", "Project Plan"]
        XCTAssertEqual(Completion.filter(names, query: "pl") { [$0] }, ["Project Plan"])
        XCTAssertEqual(Completion.filter(names, query: "") { [$0] }, names)
    }
}
