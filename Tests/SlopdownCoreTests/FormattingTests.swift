// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import SlopdownCore

final class FormattingTests: XCTestCase {
    private func r(_ a: Int, _ l: Int) -> NSRange { NSRange(location: a, length: l) }

    private func check(_ text: String, _ sel: NSRange, _ edit: (String, NSRange) -> TextEdit,
                       _ expected: String, _ expectedSel: NSRange? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let e = edit(text, sel)
        XCTAssertEqual(e.apply(to: text), expected, file: file, line: line)
        if let expectedSel { XCTAssertEqual(e.selection, expectedSel, file: file, line: line) }
    }

    func testBold() {
        let bold = { Formatting.toggleInline($0, $1, marker: "**") }
        check("a word b", r(2, 4), bold, "a **word** b", r(4, 4))
        check("a **word** b", r(4, 4), bold, "a word b", r(2, 4))
        check("a **word** b", r(2, 8), bold, "a word b", r(2, 4))
        check("a word b", r(4, 0), bold, "a **word** b")              // caret in word
        check("a  b", r(2, 0), bold, "a ****  b".replacingOccurrences(of: "****  ", with: "**** "), r(4, 0))
        check("a word  b", r(2, 5), bold, "a **word**  b")            // trailing space excluded
        check("***x***", r(3, 1), bold, "*x*")
    }

    func testItalicVersusBold() {
        let italic = { Formatting.toggleInline($0, $1, marker: "*") }
        check("**word**", r(2, 4), italic, "***word***")              // bold is not italic
        check("***word***", r(3, 4), italic, "**word**")
        check("*w*", r(1, 1), italic, "w")
    }

    func testCode() {
        check("x y", r(0, 1), { Formatting.toggleInline($0, $1, marker: "`") }, "`x` y")
        check("`x` y", r(1, 1), { Formatting.toggleInline($0, $1, marker: "`") }, "x y")
    }

    func testLinks() {
        check("see this", r(4, 4), Formatting.link, "see [this]()", r(11, 0))
        check("x https://a.b y", r(2, 11), Formatting.link, "x [](https://a.b) y", r(3, 0))
        check("x ", r(2, 0), Formatting.link, "x []()", r(3, 0))
        check("a Note b", r(2, 4), Formatting.wikiLink, "a [[Note]] b", r(4, 4))
        check("", r(0, 0), Formatting.embed, "![[]]", r(3, 0))
    }

    func testHeadings() {
        let h2 = { Formatting.setLineFormat($0, $1, .heading(2)) }
        check("Title\nbody", r(2, 0), h2, "## Title\nbody", r(5, 0))
        check("## Title", r(5, 0), h2, "Title", r(2, 0))                 // toggle off
        check("# Title", r(4, 0), h2, "## Title", r(5, 0))               // change level
        check("- item", r(3, 0), h2, "## item")
    }

    func testLists() {
        let bullet = { Formatting.setLineFormat($0, $1, .bullet) }
        check("a\nb\n\nc", r(0, 6), bullet, "- a\n- b\n\n- c")
        check("- a\n- b", r(0, 7), bullet, "a\nb")
        check("1. a\n  2. b", r(0, 10), bullet, "- a\n  - b")
        let numbered = { Formatting.setLineFormat($0, $1, .numbered) }
        check("a\nb\nc", r(0, 5), numbered, "1. a\n2. b\n3. c")
        let task = { Formatting.setLineFormat($0, $1, .task) }
        check("- a", r(3, 0), task, "- [ ] a", r(7, 0))
        check("- [x] a", r(7, 0), task, "a")
        let quote = { Formatting.setLineFormat($0, $1, .quote) }
        check("a\nb\n", r(0, 4), quote, "> a\n> b\n")                    // trailing newline not included
    }

    func testStats() {
        let s = TextStats("# Hello world\n\nTwo **bold** words, çok güzel.")
        XCTAssertEqual(s.words, 7)
        XCTAssertEqual(s.lines, 3)
        XCTAssertEqual(TextStats.lineAndColumn("ab\ncd", 4).line, 2)
        XCTAssertEqual(TextStats.lineAndColumn("ab\ncd", 4).column, 2)
        XCTAssertEqual(TextStats.lineAndColumn("", 0).line, 1)
    }
}
