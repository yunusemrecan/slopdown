// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import SlopdownCore

final class FocusTests: XCTestCase {
    private func block(_ text: String, caretAfter marker: String) -> String {
        let ns = text as NSString
        let r = ns.range(of: marker)
        XCTAssertNotEqual(r.location, NSNotFound)
        return ns.substring(with: Focus.block(in: ns, at: NSMaxRange(r)))
    }

    let doc = """
    # Title
    First line of a paragraph
    second line.

    - item one
      continued
    - item two
    1. numbered

    Last paragraph
    after the list
    """

    func testParagraph() {
        XCTAssertEqual(block(doc, caretAfter: "second"), "First line of a paragraph\nsecond line.\n")
        XCTAssertEqual(block(doc, caretAfter: "Last"), "Last paragraph\nafter the list")
    }

    func testHeadingIsOneLine() {
        XCTAssertEqual(block(doc, caretAfter: "Tit"), "# Title\n")
    }

    func testListItems() {
        XCTAssertEqual(block(doc, caretAfter: "item o"), "- item one\n  continued\n")
        XCTAssertEqual(block(doc, caretAfter: "contin"), "- item one\n  continued\n")
        XCTAssertEqual(block(doc, caretAfter: "item t"), "- item two\n")
        XCTAssertEqual(block(doc, caretAfter: "numb"), "1. numbered\n")
    }

    func testBlankLineAndEdges() {
        let ns = doc as NSString
        let blank = ns.range(of: "line.\n").location + 6
        XCTAssertEqual(ns.substring(with: Focus.block(in: ns, at: blank)), "\n")
        XCTAssertEqual(Focus.block(in: "" as NSString, at: 0), NSRange(location: 0, length: 0))
        XCTAssertEqual(ns.substring(with: Focus.block(in: ns, at: ns.length)), "Last paragraph\nafter the list")
    }

    func testTextWidth() {
        XCTAssertEqual(TextWidth(stored: nil), .medium)
        XCTAssertEqual(TextWidth(stored: "wide"), .wide)
        XCTAssertEqual(TextWidth(stored: "bogus"), .medium)
        XCTAssertNil(TextWidth.full.points)
        XCTAssertEqual(TextWidth.medium.points, 720)
    }
}
