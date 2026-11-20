// SPDX-License-Identifier: GPL-3.0-or-later
//
// A small, forgiving, line-based parser for the subset of CommonMark + Obsidian
// syntax that the editor renders live. It does not build a document tree: it only
// reports where styled elements and their syntax characters are, in UTF-16 offsets
// (NSRange), which is what the text system needs.

import Foundation

public enum MarkdownParser {

    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "svg", "avif",
    ]

    public static func parse(_ text: String) -> [MDElement] {
        let ns = NSString(string: text)
        let lines = splitLines(ns)
        var out: [MDElement] = []
        out.reserveCapacity(lines.count)

        var i = 0

        // --- YAML frontmatter: first line "---", closed by "---" or "..."
        if let first = lines.first, ns.substring(with: first).trimmingCharacters(in: .whitespaces) == "---" {
            var j = 1
            while j < lines.count {
                let s = ns.substring(with: lines[j]).trimmingCharacters(in: .whitespaces)
                if s == "---" || s == "..." { break }
                j += 1
            }
            if j < lines.count {
                for k in 0...j {
                    out.append(block(.frontmatter, lines[k]))
                }
                i = j + 1
            }
        }

        // --- Body
        var fence: (char: Character, count: Int)? = nil
        while i < lines.count {
            let line = lines[i]
            let s = ns.substring(with: line)
            i += 1

            if let f = fence {
                if isClosingFence(s, f) {
                    out.append(block(.codeFence, line))
                    fence = nil
                } else {
                    out.append(block(.codeLine, line))
                }
                continue
            }
            if let open = openingFence(s) {
                fence = open
                out.append(block(.codeFence, line))
                continue
            }

            parseLine(text, ns, line, into: &out)
        }
        return out
    }

    // MARK: - Lines

    /// Line content ranges (without the line terminator).
    static func splitLines(_ ns: NSString) -> [NSRange] {
        var result: [NSRange] = []
        let length = ns.length
        var pos = 0
        while pos < length {
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: pos, length: 0))
            result.append(NSRange(location: start, length: contentsEnd - start))
            if end <= pos { break }
            pos = end
        }
        // A trailing newline starts an (empty) last line; nothing to style there.
        return result
    }

    private static func block(_ kind: MDElement.Kind, _ line: NSRange) -> MDElement {
        MDElement(kind: kind, range: line, revealRange: line, hidden: [], content: line,
                  marker: NSRange(location: line.location, length: 0))
    }

    // MARK: - Fences

    private static func openingFence(_ s: String) -> (char: Character, count: Int)? {
        let trimmed = s.drop(while: { $0 == " " })
        guard s.count - trimmed.count <= 3, let c = trimmed.first, c == "`" || c == "~" else { return nil }
        let run = trimmed.prefix(while: { $0 == c }).count
        guard run >= 3 else { return nil }
        if c == "`" && trimmed.dropFirst(run).contains("`") { return nil }
        return (c, run)
    }

    private static func isClosingFence(_ s: String, _ f: (char: Character, count: Int)) -> Bool {
        let trimmed = s.drop(while: { $0 == " " })
        guard s.count - trimmed.count <= 3 else { return false }
        let run = trimmed.prefix(while: { $0 == f.char }).count
        guard run >= f.count else { return false }
        return trimmed.dropFirst(run).allSatisfy { $0 == " " || $0 == "\t" }
    }

    // MARK: - Block prefixes

    private static let ruleRE = re(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let headingRE = re(#"^(#{1,6})(?:[ \t]+|$)"#)
    private static let quoteRE = re(#"^(?: {0,3}>[ \t]?)+"#)
    private static let taskRE = re(#"^([ \t]*)([-*+])([ \t]+)(\[[ xX]\])(?=[ \t]|$)[ \t]?"#)
    private static let bulletRE = re(#"^([ \t]*)([-*+])[ \t]+"#)
    private static let orderedRE = re(#"^([ \t]*)(\d{1,9}[.)])[ \t]+"#)

    private static func parseLine(_ str: String, _ ns: NSString, _ line: NSRange, into out: inout [MDElement]) {
        guard line.length > 0 else { return }
        var inlineStart = line.location
        let lineEnd = NSMaxRange(line)

        if ruleRE.firstMatch(in: str, options: [], range: line) != nil {
            var e = block(.rule, line)
            e.marker = line
            out.append(e)
            return
        }

        if let m = headingRE.firstMatch(in: str, options: [], range: line) {
            let hashes = m.range(at: 1)
            var e = block(.heading(level: hashes.length), line)
            e.hidden = [m.range]
            e.content = NSRange(location: NSMaxRange(m.range), length: lineEnd - NSMaxRange(m.range))
            e.marker = hashes
            out.append(e)
            inlineStart = NSMaxRange(m.range)
        } else {
            if let m = quoteRE.firstMatch(in: str, options: [], range: line) {
                var e = block(.blockquote, line)
                e.hidden = [m.range]
                e.marker = m.range
                e.content = NSRange(location: NSMaxRange(m.range), length: lineEnd - NSMaxRange(m.range))
                out.append(e)
                inlineStart = NSMaxRange(m.range)
            }
            let rest = NSRange(location: inlineStart, length: lineEnd - inlineStart)
            if let m = taskRE.firstMatch(in: str, options: [], range: rest) {
                let box = m.range(at: 4)
                let checked = ns.substring(with: NSRange(location: box.location + 1, length: 1)).lowercased() == "x"
                var e = block(.task(checked: checked), line)
                // Hide "- " (bullet and the spaces before the box); the box itself is drawn.
                e.hidden = [NSRange(location: m.range(at: 2).location, length: box.location - m.range(at: 2).location)]
                e.marker = box
                e.content = NSRange(location: NSMaxRange(m.range), length: lineEnd - NSMaxRange(m.range))
                // Only touching the "- [ ]" prefix reveals it, not editing the item text.
                e.revealRange = NSRange(location: line.location, length: NSMaxRange(m.range) - line.location)
                out.append(e)
                inlineStart = NSMaxRange(m.range)
            } else if let m = bulletRE.firstMatch(in: str, options: [], range: rest) {
                var e = block(.bulletItem, line)
                e.marker = m.range(at: 2)
                e.content = NSRange(location: NSMaxRange(m.range), length: lineEnd - NSMaxRange(m.range))
                e.revealRange = NSRange(location: line.location, length: NSMaxRange(m.range) - line.location)
                out.append(e)
                inlineStart = NSMaxRange(m.range)
            } else if let m = orderedRE.firstMatch(in: str, options: [], range: rest) {
                var e = block(.orderedItem, line)
                e.marker = m.range(at: 2)
                e.content = NSRange(location: NSMaxRange(m.range), length: lineEnd - NSMaxRange(m.range))
                out.append(e)
                inlineStart = NSMaxRange(m.range)
            }
        }

        let inlineRange = NSRange(location: inlineStart, length: lineEnd - inlineStart)
        if inlineRange.length > 0 {
            parseInline(str, ns, inlineRange, line: line, into: &out)
        }
    }

    // MARK: - Inline

    private static let codeRE = re(#"(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)
    private static let embedRE = re(#"!\[\[([^\[\]\n]+?)\]\]"#)
    private static let wikiRE = re(#"\[\[([^\[\]\n]+?)\]\]"#)
    private static let mdImageRE = re(#"!\[([^\]\n]*)\]\(([^)\n]*)\)"#)
    private static let mdLinkRE = re(#"\[([^\]\n]+)\]\(([^)\n]*)\)"#)
    private static let bareURLRE = re(#"(?<![\w(<\[/])https?://[^\s<>()\[\]]+"#)
    private static let boldItalicRE = re(#"(\*\*\*|___)(?=\S)(.+?)(?<=\S)\1"#)
    private static let boldRE = re(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicStarRE = re(#"(?<![*\\])\*(?=[^\s*])(.+?)(?<=[^\s*\\])\*(?!\*)"#)
    private static let italicUnderscoreRE = re(#"(?<![_\w\\])_(?=[^\s_])(.+?)(?<=[^\s_\\])_(?![_\w])"#)
    private static let strikeRE = re(#"~~(?=\S)(.+?)(?<=\S)~~"#)

    private static func parseInline(_ str: String, _ ns: NSString, _ range: NSRange, line: NSRange, into out: inout [MDElement]) {
        var occupied: [NSRange] = []
        func free(_ r: NSRange) -> Bool { !occupied.contains { $0.overlaps(r) } }

        // Escapes: "\*" etc. are never syntax.
        // (Handled by the negative lookbehinds above for emphasis.)

        // 1. Code spans — nothing inside is markdown.
        for m in codeRE.matches(in: str, options: [], range: range) {
            let ticks = m.range(at: 1).length
            let open = NSRange(location: m.range.location, length: ticks)
            let close = NSRange(location: NSMaxRange(m.range) - ticks, length: ticks)
            out.append(MDElement(kind: .inlineCode, range: m.range, revealRange: m.range,
                                 hidden: [open, close], content: m.range(at: 2), marker: empty(m.range)))
            occupied.append(m.range)
        }

        // 2. Wiki embeds ![[...]]
        for m in embedRE.matches(in: str, options: [], range: range) where free(m.range) {
            let inner = m.range(at: 1)
            let parts = splitWiki(ns, inner)
            let ext = NSString(string: parts.path).pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                let size = parts.alias.flatMap(parseSize)
                let img = MDImage(source: parts.path, isWiki: true, width: size?.0, height: size?.1,
                                  isRemote: isRemote(parts.path),
                                  standalone: isStandalone(ns, m.range, line: line),
                                  targetRange: parts.pathRange)
                out.append(MDElement(kind: .image(img), range: m.range, revealRange: m.range,
                                     hidden: [m.range], content: m.range, marker: empty(m.range)))
            } else {
                out.append(wikiElement(ns, m.range, inner: inner, parts: parts, prefix: 3, style: .embed))
            }
            occupied.append(m.range)
        }

        // 3. Wiki links [[...]]
        for m in wikiRE.matches(in: str, options: [], range: range) where free(m.range) {
            let inner = m.range(at: 1)
            out.append(wikiElement(ns, m.range, inner: inner, parts: splitWiki(ns, inner), prefix: 2, style: .wiki))
            occupied.append(m.range)
        }

        // 4. Markdown images ![alt](src)
        for m in mdImageRE.matches(in: str, options: [], range: range) where free(m.range) {
            let altRange = m.range(at: 1)
            let alt = ns.substring(with: altRange)
            let dest = parseDestination(ns, m.range(at: 2))
            var size: (Double, Double?)? = nil
            if let bar = alt.lastIndex(of: "|") {
                size = parseSize(String(alt[alt.index(after: bar)...]))
            }
            let img = MDImage(source: dest.path, isWiki: false, width: size?.0, height: size?.1,
                              isRemote: isRemote(dest.path),
                              standalone: isStandalone(ns, m.range, line: line),
                              targetRange: dest.range)
            out.append(MDElement(kind: .image(img), range: m.range, revealRange: m.range,
                                 hidden: [m.range], content: m.range, marker: empty(m.range)))
            occupied.append(m.range)
        }

        // 5. Markdown links [text](target)
        for m in mdLinkRE.matches(in: str, options: [], range: range) where free(m.range) {
            let text = m.range(at: 1)
            let dest = parseDestination(ns, m.range(at: 2))
            let open = NSRange(location: m.range.location, length: 1)
            let tail = NSRange(location: NSMaxRange(text), length: NSMaxRange(m.range) - NSMaxRange(text))
            let link = MDLink(style: .markdown, target: dest.path, heading: nil, targetRange: dest.range)
            out.append(MDElement(kind: .link(link), range: m.range, revealRange: m.range,
                                 hidden: [open, tail], content: text, marker: empty(m.range)))
            occupied.append(open)
            occupied.append(tail)
        }

        // 6. Bare URLs
        for m in bareURLRE.matches(in: str, options: [], range: range) {
            var r = m.range
            // Trailing punctuation is not part of the URL.
            while r.length > 0, let last = ns.substring(with: NSRange(location: NSMaxRange(r) - 1, length: 1)).first,
                  ".,;:!?'\"".contains(last) {
                r.length -= 1
            }
            guard r.length > 0, free(r) else { continue }
            let link = MDLink(style: .bareURL, target: ns.substring(with: r), heading: nil, targetRange: r)
            out.append(MDElement(kind: .link(link), range: r, revealRange: r, hidden: [], content: r, marker: empty(r)))
            occupied.append(r)
        }

        // 7. Emphasis. Markers may not overlap any syntax found above, nor each other.
        func emphasis(_ regex: NSRegularExpression, _ kind: MDElement.Kind, markerLength: (NSTextCheckingResult) -> Int) {
            for m in regex.matches(in: str, options: [], range: range) {
                let n = markerLength(m)
                let open = NSRange(location: m.range.location, length: n)
                let close = NSRange(location: NSMaxRange(m.range) - n, length: n)
                guard free(open), free(close) else { continue }
                let content = NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open))
                out.append(MDElement(kind: kind, range: m.range, revealRange: m.range,
                                     hidden: [open, close], content: content, marker: empty(m.range)))
                occupied.append(open)
                occupied.append(close)
            }
        }
        emphasis(boldItalicRE, .boldItalic) { $0.range(at: 1).length }
        emphasis(boldRE, .bold) { $0.range(at: 1).length }
        emphasis(italicStarRE, .italic) { _ in 1 }
        emphasis(italicUnderscoreRE, .italic) { _ in 1 }
        emphasis(strikeRE, .strikethrough) { _ in 2 }
    }

    // MARK: - Helpers

    struct WikiParts {
        var path: String
        var pathRange: NSRange
        var heading: String?
        var alias: String?
        var aliasRange: NSRange?
        var targetPartRange: NSRange   // "path#heading"
    }

    static func splitWiki(_ ns: NSString, _ inner: NSRange) -> WikiParts {
        let s = ns.substring(with: inner)
        let u = Array(s.utf16)
        let bar = u.firstIndex(of: 0x7C)          // |
        let targetLen = bar ?? u.count
        let hash = u[0..<targetLen].firstIndex(of: 0x23) // #
        let pathLen = hash ?? targetLen
        func sub(_ a: Int, _ b: Int) -> String {
            String(utf16CodeUnits: Array(u[a..<b]), count: b - a)
        }
        let rawPath = sub(0, pathLen)
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespaces)
        var parts = WikiParts(
            path: trimmedPath,
            pathRange: NSRange(location: inner.location, length: pathLen),
            heading: hash.map { sub($0 + 1, targetLen) },
            alias: nil, aliasRange: nil,
            targetPartRange: NSRange(location: inner.location, length: targetLen))
        if let b = bar {
            parts.alias = sub(b + 1, u.count)
            parts.aliasRange = NSRange(location: inner.location + b + 1, length: u.count - b - 1)
        }
        return parts
    }

    private static func wikiElement(_ ns: NSString, _ whole: NSRange, inner: NSRange, parts: WikiParts,
                                    prefix: Int, style: MDLink.Style) -> MDElement {
        let open = NSRange(location: whole.location, length: prefix)
        let close = NSRange(location: NSMaxRange(whole) - 2, length: 2)
        var hidden = [open, close]
        var content = parts.targetPartRange
        if let aliasRange = parts.aliasRange, aliasRange.length > 0 {
            // Hide "target|", show only the alias.
            hidden.append(NSRange(location: inner.location, length: aliasRange.location - inner.location))
            content = aliasRange
        }
        let link = MDLink(style: style, target: parts.path,
                          heading: parts.heading.flatMap { $0.isEmpty ? nil : $0 },
                          targetRange: parts.pathRange)
        return MDElement(kind: .link(link), range: whole, revealRange: whole,
                         hidden: hidden, content: content, marker: empty(whole))
    }

    /// `path`, `<path with spaces>`, `path "title"` → decoded path + raw range of the path.
    static func parseDestination(_ ns: NSString, _ r: NSRange) -> (path: String, range: NSRange) {
        let s = ns.substring(with: r)
        let u = Array(s.utf16)
        var start = 0
        while start < u.count, u[start] == 0x20 || u[start] == 0x09 { start += 1 }
        var end: Int
        if start < u.count, u[start] == 0x3C, let close = u[(start + 1)...].firstIndex(of: 0x3E) { // < >
            let pathRange = NSRange(location: r.location + start + 1, length: close - start - 1)
            let raw = ns.substring(with: pathRange)
            return (raw.removingPercentEncoding ?? raw, pathRange)
        }
        end = start
        while end < u.count, u[end] != 0x20, u[end] != 0x09 { end += 1 }
        let pathRange = NSRange(location: r.location + start, length: end - start)
        let raw = ns.substring(with: pathRange)
        return (raw.removingPercentEncoding ?? raw, pathRange)
    }

    /// "300" → (300, nil), "300x200" → (300, 200); anything else → nil.
    static func parseSize(_ s: String) -> (Double, Double?)? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let parts = t.split(separator: "x", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let w = Double(first), w > 0 else { return nil }
        if parts.count == 2 {
            guard let h = Double(parts[1]), h > 0 else { return nil }
            return (w, h)
        }
        return (w, nil)
    }

    static func isRemote(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.hasPrefix("http://") || l.hasPrefix("https://") || l.hasPrefix("//")
    }

    private static func isStandalone(_ ns: NSString, _ r: NSRange, line: NSRange) -> Bool {
        let before = ns.substring(with: NSRange(location: line.location, length: r.location - line.location))
        let after = ns.substring(with: NSRange(location: NSMaxRange(r), length: NSMaxRange(line) - NSMaxRange(r)))
        return before.trimmingCharacters(in: .whitespaces).isEmpty
            && after.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func empty(_ r: NSRange) -> NSRange { NSRange(location: r.location, length: 0) }

    private static func re(_ pattern: String) -> NSRegularExpression {
        // Patterns are constants; a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }
}
