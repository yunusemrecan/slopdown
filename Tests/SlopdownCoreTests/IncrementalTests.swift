// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import SlopdownCore

final class IncrementalTests: XCTestCase {
    static let sample = """
    ---
    title: x
    ---
    # Heading **one**

    Some *italic* and **bold** text with a [[Wiki Link|alias]] and `code`.
    - item one ~~gone~~
    - [ ] task [link](a.md)

    > quote with https://example.org

    | a | b |
    |---|:-:|
    | 1 | **2** |

    ```swift
    let x = 1
    ```

    ![[pic.png|200]]
    Final paragraph with ![inline|20](i.png) image.
    """

    /// Random edits: the incremental result must always equal a full parse.
    func testRandomEditsMatchFullParse() {
        var rng = SystemRandomNumberGenerator()
        let inserts = ["x", "*", "**", "[[", "]]", "`", "\n", " ", "#", "- ", "ab", "|", "```", "\n\n", "é", "😀",
                       "> ", "1. ", "---", "|---|", "![[", "- [ ] ", "{{< x >}}", "+++", "~~"]
        for round in 0..<400 {
            var text = Self.sample
            var elements = MarkdownParser.parse(text)
            for step in 0..<6 {
                let ns = NSString(string: text)
                let loc = Int.random(in: 0...ns.length, using: &rng)
                var delLen = Bool.random(using: &rng) ? Int.random(in: 0...min(4, ns.length - loc), using: &rng) : 0
                // never split a surrogate pair
                var start = loc
                if start > 0, start < ns.length, UTF16.isTrailSurrogate(ns.character(at: start)) { start -= 1 }
                if start + delLen < ns.length, start + delLen > 0, UTF16.isTrailSurrogate(ns.character(at: start + delLen)) { delLen += 1 }
                let insert = inserts.randomElement(using: &rng)!
                let new = ns.replacingCharacters(in: NSRange(location: start, length: delLen), with: insert)
                let edited = NSRange(location: start, length: (insert as NSString).length)
                let delta = (insert as NSString).length - delLen
                let update = MarkdownParser.update(elements, newText: new, editedRange: edited, delta: delta)
                let expected = MarkdownParser.parse(new)
                if update.elements != expected {
                    print("OLD:", text.debugDescription)
                    let a = update.elements, b = expected
                    for i in 0..<max(a.count, b.count) where i >= a.count || i >= b.count || a[i] != b[i] {
                        print("first diff at \(i):\n got \(i < a.count ? String(describing: a[i]) : "-")\n want \(i < b.count ? String(describing: b[i]) : "-")")
                        break
                    }
                    print("counts", a.count, b.count, "dirty", update.dirty, "full", update.wasFullParse)
                    XCTFail("round \(round) step \(step): insert \(insert.debugDescription) at \(start) del \(delLen)\n\(new.debugDescription)")
                    return
                }
                text = new
                elements = update.elements
            }
        }
    }

    func testTypingIsIncremental() {
        let text = Self.sample
        let ns = NSString(string: text)
        let at = ns.range(of: "Some").location
        let new = ns.replacingCharacters(in: NSRange(location: at, length: 0), with: "z")
        let u = MarkdownParser.update(MarkdownParser.parse(text), newText: new,
                                      editedRange: NSRange(location: at, length: 1), delta: 1)
        XCTAssertFalse(u.wasFullParse)
        XCTAssertEqual(u.elements, MarkdownParser.parse(new))
        XCTAssertEqual(NSString(string: new).substring(with: u.dirty).hasPrefix("zSome"), true)
    }

    /// A long document: one keystroke must be much cheaper incrementally.
    func testSpeed() {
        var big = ""
        for i in 0..<3000 { big += "## Section \(i)\n\nText with **bold**, *italic*, [[link \(i)]] and `code` words here.\n- item\n\n" }
        let ns = NSString(string: big)
        let elements = MarkdownParser.parse(big)
        let at = ns.length / 2
        let new = ns.replacingCharacters(in: NSRange(location: at, length: 0), with: "q")

        func time(_ f: () -> Void) -> Double {
            let t = Date(); f(); return Date().timeIntervalSince(t)
        }
        var full = Double.infinity, incremental = Double.infinity
        for _ in 0..<3 {
            full = min(full, time { _ = MarkdownParser.parse(new) })
            incremental = min(incremental, time {
                _ = MarkdownParser.update(elements, newText: new, editedRange: NSRange(location: at, length: 1), delta: 1)
            })
        }
        print("parse \(ns.length) chars: full \(Int(full * 1000)) ms, incremental \(Int(incremental * 1000)) ms")
        XCTAssertLessThan(incremental, full / 5)
    }
}
