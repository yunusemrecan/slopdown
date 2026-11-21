// SPDX-License-Identifier: GPL-3.0-or-later
//
// Focus mode and text width: which block the caret is in, and the column widths.

import Foundation

/// Width of the writing column. `full` fills the window.
public enum TextWidth: String, CaseIterable, Sendable {
    case narrow, medium, wide, full

    public static let defaultsKey = "TextWidth"
    public static let `default` = TextWidth.medium

    /// Column width in points; nil fills the window.
    public var points: Double? {
        switch self {
        case .narrow: return 560
        case .medium: return 720
        case .wide: return 920
        case .full: return nil
        }
    }

    public init(stored: String?) {
        self = stored.flatMap(TextWidth.init(rawValue:)) ?? .default
    }
}

public enum Focus {
    /// The block that stays bright in focus mode: the caret's paragraph (lines up to the
    /// nearest blank line), a single heading line, or one list item with its indented
    /// continuation lines. A blank line is its own block.
    public static func block(in text: NSString, at caret: Int) -> NSRange {
        let length = text.length
        let caret = max(0, min(caret, length))
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        let kind = Kind(text.substring(with: line))
        switch kind {
        case .blank, .heading:
            return line
        case .listItem:
            return extendDown(text, from: line)
        case .text(let indented):
            var start = line
            // Upwards: stop at blank lines and headings; a list item above an indented
            // line is the start of this item.
            while start.location > 0 {
                let prev = text.lineRange(for: NSRange(location: start.location - 1, length: 0))
                switch Kind(text.substring(with: prev)) {
                case .blank, .heading: break
                case .listItem:
                    if indented { start = NSUnionRange(prev, start) }
                    break
                case .text:
                    start = NSUnionRange(prev, start)
                    continue
                }
                break
            }
            return NSUnionRange(start, extendDown(text, from: line))
        }
    }

    /// Adds following text lines (not blank, heading or list item).
    private static func extendDown(_ text: NSString, from line: NSRange) -> NSRange {
        var end = line
        while NSMaxRange(end) < text.length {
            let next = text.lineRange(for: NSRange(location: NSMaxRange(end), length: 0))
            guard case .text = Kind(text.substring(with: next)) else { break }
            end = NSUnionRange(end, next)
        }
        return end
    }

    private enum Kind {
        case blank, heading, listItem, text(indented: Bool)

        init(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { self = .blank; return }
            let indented = line.first == " " || line.first == "\t"
            if !indented, trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" }).count
                let rest = trimmed.dropFirst(hashes)
                if hashes <= 6, rest.isEmpty || rest.first == " " { self = .heading; return }
            }
            if Kind.isListItem(trimmed) { self = .listItem; return }
            self = .text(indented: indented)
        }

        static func isListItem(_ s: String) -> Bool {
            let chars = Array(s)
            guard let first = chars.first else { return false }
            if "-*+".contains(first) {
                return chars.count == 1 || chars[1] == " " || chars[1] == "\t"
            }
            var i = 0
            while i < chars.count, i < 9, chars[i].isASCII, chars[i].isNumber { i += 1 }
            guard i > 0, i < chars.count, chars[i] == "." || chars[i] == ")" else { return false }
            return i + 1 == chars.count || chars[i + 1] == " " || chars[i + 1] == "\t"
        }
    }
}
