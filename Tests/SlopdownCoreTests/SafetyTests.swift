// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import SlopdownCore

final class SafetyTests: XCTestCase {
    func testURLs() {
        XCTAssertEqual(LinkSafety.action(forURL: "https://example.org"), .open)
        XCTAssertEqual(LinkSafety.action(forURL: "HTTP://example.org"), .open)
        XCTAssertEqual(LinkSafety.action(forURL: "mailto:a@b.c"), .open)
        XCTAssertEqual(LinkSafety.action(forURL: "ssh://host"), .confirm)
        XCTAssertEqual(LinkSafety.action(forURL: "file:///Applications/Calculator.app"), .confirm)
        XCTAssertEqual(LinkSafety.action(forURL: "x-apple.systempreferences:com.apple"), .confirm)
        XCTAssertEqual(LinkSafety.action(forURL: "javascript:alert(1)"), .confirm)
    }

    func testFiles() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("safety-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appendingPathComponent("Tool.app"), withIntermediateDirectories: true)
        func make(_ name: String, executable: Bool = false) throws -> URL {
            let u = dir.appendingPathComponent(name)
            try Data("x".utf8).write(to: u)
            if executable { try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path) }
            return u
        }
        XCTAssertEqual(LinkSafety.action(forFile: try make("photo.png")), .open)
        XCTAssertEqual(LinkSafety.action(forFile: try make("paper.pdf")), .open)
        XCTAssertEqual(LinkSafety.action(forFile: try make("install.command")), .revealOnly)
        XCTAssertEqual(LinkSafety.action(forFile: try make("run.sh")), .revealOnly)
        XCTAssertEqual(LinkSafety.action(forFile: try make("binary", executable: true)), .revealOnly)
        XCTAssertEqual(LinkSafety.action(forFile: dir.appendingPathComponent("Tool.app")), .revealOnly)
        XCTAssertEqual(LinkSafety.action(forFile: try make("data.csv")), .confirm)
    }

    func testRenderable() {
        let home = "/Users/emre"
        XCTAssertTrue(LinkSafety.isRenderable(URL(fileURLWithPath: "/Users/emre/Notes/a.png"), home: home))
        XCTAssertTrue(LinkSafety.isRenderable(URL(fileURLWithPath: "/Volumes/Disk/notes/a.md"), home: home))
        XCTAssertFalse(LinkSafety.isRenderable(URL(fileURLWithPath: "/Users/emre/.ssh/id_rsa"), home: home))
        XCTAssertFalse(LinkSafety.isRenderable(URL(fileURLWithPath: "/Users/emre/Notes/../.aws/credentials"), home: home))
        XCTAssertFalse(LinkSafety.isRenderable(URL(fileURLWithPath: "/Users/emre/Library/Mail/x.txt"), home: home))
        XCTAssertFalse(LinkSafety.isRenderable(URL(fileURLWithPath: "/etc/hosts"), home: home))
        XCTAssertFalse(LinkSafety.isRenderable(URL(fileURLWithPath: "/Users/someone/Notes/a.md"), home: home))
        XCTAssertFalse(LinkSafety.isRenderable(URL(fileURLWithPath: "/Users/emre/project/.git/config"), home: home))
    }

    func testInside() {
        let base = URL(fileURLWithPath: "/n/notes")
        XCTAssertTrue(LinkSafety.isInside(URL(fileURLWithPath: "/n/notes/a/b.md"), base))
        XCTAssertFalse(LinkSafety.isInside(URL(fileURLWithPath: "/n/notes/../x.md"), base))
        XCTAssertFalse(LinkSafety.isInside(URL(fileURLWithPath: "/n/notesX/a.md"), base))
    }

    func testLongLineNotStyled() {
        let long = String(repeating: "**a** ", count: 3000)
        XCTAssertTrue(MarkdownParser.parse(long).isEmpty)
        XCTAssertEqual(MarkdownParser.parse("# " + long).filter { if case .heading = $0.kind { return true }; return false }.count, 1)
    }
}
