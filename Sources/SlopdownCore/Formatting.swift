// SPDX-License-Identifier: GPL-3.0-or-later
//
// Formatting commands (bold, link, lists…) as pure text transforms, so they can be
// tested without AppKit. Each returns one edit: replace `range` with `replacement`,
// then select `selection`.

import Foundation

public struct TextEdit: Equatable {
    public var range: NSRange
    public var replacement: String
    public var selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// Applies the edit to a string (used by tests).
    public func apply(to text: String) -> String {
        NSString(string: text).replacingCharacters(in: range, with: replacement)
    }
}

public enum LineFormat: Equatable {
    case paragraph
    case heading(Int)
    case bullet
    case numbered
    case task
    case quote
}

public enum Formatting {

    // MARK: - Inline (bold, italic, ~~strike~~, `code`, ==highlight==)

    public static func toggleInline(_ text: String, _ selection: NSRange, marker: String) -> TextEdit {
        let ns = NSString(string: text)
        let m = (marker as NSString).length
        let c = (marker as NSString).character(at: 0)
        var sel = trimmedSelection(ns, selection)
        if sel.length == 0, let word = wordRange(ns, at: sel.location) { sel = word }

        func run(from i: Int, step: Int) -> Int {
            var k = 0, j = i
            while j >= 0, j < ns.length, ns.character(at: j) == c { k += 1; j += step }
            return k
        }
        func present(_ k: Int) -> Bool {
            if m == 1 && (c == 0x2A || c == 0x5F) { return k % 2 == 1 } // * or _: odd run = italic
            return k >= m
        }

        // 1. Markers just outside the selection: **|word|**
        let left = run(from: sel.location - 1, step: -1)
        let right = run(from: NSMaxRange(sel), step: 1)
        if sel.length > 0 || left > 0, present(min(left, right)) {
            let range = NSRange(location: sel.location - m, length: sel.length + 2 * m)
            return TextEdit(range: range, replacement: ns.substring(with: sel),
                            selection: NSRange(location: sel.location - m, length: sel.length))
        }
        // 2. Markers inside the selection: |**word**|
        if sel.length >= 2 * m {
            let inLeft = min(run(from: sel.location, step: 1), sel.length / 2)
            let inRight = min(run(from: NSMaxRange(sel) - 1, step: -1), sel.length / 2)
            if present(min(inLeft, inRight)) {
                let inner = NSRange(location: sel.location + m, length: sel.length - 2 * m)
                return TextEdit(range: sel, replacement: ns.substring(with: inner),
                                selection: NSRange(location: sel.location, length: inner.length))
            }
        }
        // 3. Wrap (an empty selection gets a pair of markers with the caret between)
        return TextEdit(range: sel, replacement: marker + ns.substring(with: sel) + marker,
                        selection: NSRange(location: sel.location + m, length: sel.length))
    }

    // MARK: - Links

    /// `[selection](|)`; a selected URL becomes `[|](url)`; nothing selected gives `[|]()`.
    public static func link(_ text: String, _ selection: NSRange) -> TextEdit {
        let ns = NSString(string: text)
        let sel = trimmedSelection(ns, selection)
        let s = ns.substring(with: sel)
        if LinkResolver.isExternal(s), !s.contains(" ") {
            return TextEdit(range: sel, replacement: "[](\(s))", selection: NSRange(location: sel.location + 1, length: 0))
        }
        let len = (s as NSString).length
        return TextEdit(range: sel, replacement: "[\(s)]()",
                        selection: NSRange(location: sel.location + (len == 0 ? 1 : len + 3), length: 0))
    }

    /// `[[selection]]`, or `[[|]]`.
    public static func wikiLink(_ text: String, _ selection: NSRange) -> TextEdit {
        let ns = NSString(string: text)
        let sel = trimmedSelection(ns, selection)
        return TextEdit(range: sel, replacement: "[[\(ns.substring(with: sel))]]",
                        selection: NSRange(location: sel.location + 2, length: sel.length))
    }

    /// `![[|]]` for an image or note embed.
    public static func embed(_ text: String, _ selection: NSRange) -> TextEdit {
        let ns = NSString(string: text)
        let sel = trimmedSelection(ns, selection)
        return TextEdit(range: sel, replacement: "![[\(ns.substring(with: sel))]]",
                        selection: NSRange(location: sel.location + 3, length: sel.length))
    }

    // MARK: - Line prefixes (headings, lists, quotes)

    private static let prefixRE = try! NSRegularExpression(
        pattern: #"^([ \t]*)(#{1,6}[ \t]+|>[ \t]?|[-*+][ \t]+\[[ xX]\][ \t]+|[-*+][ \t]+|\d{1,9}[.)][ \t]+)?"#)

    static func format(of marker: String) -> LineFormat {
        let t = marker.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return .paragraph }
        if t.hasPrefix("#") { return .heading(t.count) }
        if t.hasPrefix(">") { return .quote }
        if t.hasSuffix("]") { return .task }
        if t.first!.isNumber { return .numbered }
        return .bullet
    }

    /// Sets (or, when every line already has it, removes) a line format on all lines
    /// touched by the selection.
    public static func setLineFormat(_ text: String, _ selection: NSRange, _ target: LineFormat) -> TextEdit {
        let ns = NSString(string: text)
        var sel = selection
        // A selection of whole lines ends at the start of the next line: don't include it.
        if sel.length > 0, NSMaxRange(sel) <= ns.length, NSMaxRange(sel) > 0,
           ns.character(at: NSMaxRange(sel) - 1) == 0x0A {
            sel.length -= 1
        }
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: sel)
        let block = NSRange(location: start, length: contentsEnd - start)
        let lines = ns.substring(with: block).components(separatedBy: "\n")

        struct Line { var indent: String; var marker: String; var rest: String }
        let parsed: [Line] = lines.map { line in
            let l = line as NSString
            guard let m = prefixRE.firstMatch(in: line, range: NSRange(location: 0, length: l.length)) else {
                return Line(indent: "", marker: "", rest: line)
            }
            let indent = l.substring(with: m.range(at: 1))
            let marker = m.range(at: 2).location == NSNotFound ? "" : l.substring(with: m.range(at: 2))
            return Line(indent: indent, marker: marker, rest: l.substring(from: NSMaxRange(m.range)))
        }
        let multi = parsed.count > 1
        let relevant = parsed.filter { !multi || !($0.marker.isEmpty && $0.rest.trimmingCharacters(in: .whitespaces).isEmpty) }
        let allHave = !relevant.isEmpty && relevant.allSatisfy { format(of: $0.marker) == target }
        let goal: LineFormat = allHave ? .paragraph : target

        var number = 0
        var out: [String] = []
        var firstDelta = 0
        for (i, l) in parsed.enumerated() {
            if multi && l.marker.isEmpty && l.rest.trimmingCharacters(in: .whitespaces).isEmpty {
                out.append(l.indent + l.rest)
                continue
            }
            let marker: String
            switch goal {
            case .paragraph: marker = ""
            case .heading(let n): marker = String(repeating: "#", count: max(1, min(6, n))) + " "
            case .bullet: marker = "- "
            case .task: marker = "- [ ] "
            case .quote: marker = "> "
            case .numbered: number += 1; marker = "\(number). "
            }
            let indent: String
            switch goal {
            case .bullet, .task, .numbered: indent = l.indent
            default: indent = ""
            }
            out.append(indent + marker + l.rest)
            if i == 0 {
                firstDelta = (indent + marker as NSString).length - (l.indent + l.marker as NSString).length
            }
        }
        let replacement = out.joined(separator: "\n")
        let newSelection: NSRange
        if multi {
            newSelection = NSRange(location: block.location, length: (replacement as NSString).length)
        } else {
            let prefixEnd = block.location + (out[0] as NSString).length - (parsed[0].rest as NSString).length
            let loc = max(prefixEnd, selection.location + firstDelta)
            newSelection = NSRange(location: loc, length: selection.length)
        }
        return TextEdit(range: block, replacement: replacement, selection: newSelection)
    }

    // MARK: - Helpers

    /// Selection without leading/trailing whitespace (emphasis can't start with a space).
    static func trimmedSelection(_ ns: NSString, _ sel: NSRange) -> NSRange {
        var a = sel.location, b = NSMaxRange(sel)
        func space(_ i: Int) -> Bool { let c = ns.character(at: i); return c == 0x20 || c == 0x09 || c == 0x0A }
        while a < b, space(a) { a += 1 }
        while b > a, space(b - 1) { b -= 1 }
        return NSRange(location: a, length: b - a)
    }

    /// The word around a caret, if the caret is inside or at the edge of one.
    static func wordRange(_ ns: NSString, at i: Int) -> NSRange? {
        func isWord(_ k: Int) -> Bool {
            guard k >= 0, k < ns.length else { return false }
            guard let scalar = Unicode.Scalar(ns.character(at: k)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "'" || scalar == "-"
        }
        guard isWord(i) || isWord(i - 1) else { return nil }
        var a = i, b = i
        while isWord(a - 1) { a -= 1 }
        while isWord(b) { b += 1 }
        return NSRange(location: a, length: b - a)
    }
}

/// Document statistics for the status bar.
public struct TextStats: Equatable {
    public var words: Int
    public var characters: Int
    public var lines: Int

    public init(_ text: String) {
        // A word is a run of letters/digits (apostrophes and hyphens inside a word don't
        // split it). Markdown syntax characters never count.
        var w = 0
        var inWord = false
        var previousJoiner = false
        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if !inWord { w += 1; inWord = true }
                previousJoiner = false
            } else if inWord, !previousJoiner, scalar == "'" || scalar == "’" || scalar == "-" {
                previousJoiner = true
            } else {
                inWord = false
                previousJoiner = false
            }
        }
        words = w
        characters = text.count
        lines = text.isEmpty ? 1 : text.components(separatedBy: "\n").count
    }

    /// 1-based line and column of a UTF-16 location.
    public static func lineAndColumn(_ text: String, _ location: Int) -> (line: Int, column: Int) {
        let ns = NSString(string: text)
        let loc = min(max(0, location), ns.length)
        var line = 1
        var lineStart = 0
        var i = 0
        while i < loc {
            if ns.character(at: i) == 0x0A { line += 1; lineStart = i + 1 }
            i += 1
        }
        let column = ns.substring(with: NSRange(location: lineStart, length: loc - lineStart)).count + 1
        return (line, column)
    }
}
