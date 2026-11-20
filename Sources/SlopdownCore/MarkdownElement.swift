// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A link found in the text: `[[wiki]]`, `![[note embed]]`, `[text](url)` or a bare URL.
public struct MDLink: Equatable {
    public enum Style: Equatable {
        case wiki        // [[Target#Heading|Alias]]
        case embed       // ![[Note]] (non-image embed, followed like a wiki link)
        case markdown    // [text](target)
        case bareURL     // https://example.com
    }

    public var style: Style
    /// Path / URL part, percent-decoded for markdown links. Empty for same-note heading links.
    public var target: String
    /// `#Heading` part of a wiki link, if any.
    public var heading: String?
    /// Range of the raw target text in the document (what gets rewritten when the user
    /// picks a file manually).
    public var targetRange: NSRange

    public init(style: Style, target: String, heading: String?, targetRange: NSRange) {
        self.style = style
        self.target = target
        self.heading = heading
        self.targetRange = targetRange
    }

    public var isWikiStyle: Bool { style == .wiki || style == .embed }
}

/// An image: `![[picture.png|300]]` or `![alt|300x200](path/picture.png)`.
public struct MDImage: Equatable {
    public var source: String          // percent-decoded path
    public var isWiki: Bool
    public var width: Double?
    public var height: Double?
    public var isRemote: Bool          // http(s) — never loaded
    /// True when the image is the only thing on its line (then it is rendered as a block).
    public var standalone: Bool
    public var targetRange: NSRange
}

public enum MDAlignment: Equatable {
    case left, center, right
}

/// One line of a pipe table.
public struct MDTableRow: Equatable {
    /// Range of the whole table (all lines); identifies the table.
    public var table: NSRange
    public var rowIndex: Int          // 0 = header; the delimiter row is not counted
    public var isHeader: Bool { rowIndex == 0 }
    public var isLast: Bool
    /// Every `|` that separates cells (not escaped, not inside code or wiki links).
    public var pipes: [NSRange]
    /// True when the row starts / ends with a pipe.
    public var leadingPipe: Bool
    public var trailingPipe: Bool
    /// Trimmed cell contents, left to right.
    public var cells: [NSRange]
    /// Column alignments from the delimiter row.
    public var alignments: [MDAlignment]
}

public struct MDElement: Equatable {
    public enum Kind: Equatable {
        // Block level (one element per line)
        case heading(level: Int)
        case blockquote
        case bulletItem
        case orderedItem
        case task(checked: Bool)
        case rule
        case codeFence
        case codeLine
        case frontmatter
        case tableRow(MDTableRow)
        case tableDelimiter(MDTableRow)
        // Inline
        case bold
        case italic
        case boldItalic
        case strikethrough
        case inlineCode
        case link(MDLink)
        case image(MDImage)
    }

    public var kind: Kind
    /// Whole element (for block elements: the line without its line break).
    public var range: NSRange
    /// When the selection touches this range, the element shows its markdown syntax.
    public var revealRange: NSRange
    /// Syntax characters hidden while the element is not revealed.
    public var hidden: [NSRange]
    /// The visible, styled part.
    public var content: NSRange
    /// Special marker: the bullet character, the `[ ]` of a task, the number of an
    /// ordered item. Empty range when unused.
    public var marker: NSRange

    public var isBlock: Bool {
        switch kind {
        case .heading, .blockquote, .bulletItem, .orderedItem, .task, .rule,
             .codeFence, .codeLine, .frontmatter, .tableRow, .tableDelimiter:
            return true
        default:
            return false
        }
    }

    public var link: MDLink? {
        if case .link(let l) = kind { return l }
        return nil
    }

    public var tableRow: MDTableRow? {
        switch kind {
        case .tableRow(let r), .tableDelimiter(let r): return r
        default: return nil
        }
    }

    public var image: MDImage? {
        if case .image(let i) = kind { return i }
        return nil
    }
}

public extension NSRange {
    /// Inclusive "touch" test used for revealing: a caret sitting right before or right
    /// after the range counts.
    func touches(_ other: NSRange) -> Bool {
        let aEnd = location + length
        let bEnd = other.location + other.length
        return Swift.max(location, other.location) <= Swift.min(aEnd, bEnd)
    }

    func overlaps(_ other: NSRange) -> Bool {
        let aEnd = location + length
        let bEnd = other.location + other.length
        return Swift.max(location, other.location) < Swift.min(aEnd, bEnd)
    }

    func containsIndex(_ i: Int) -> Bool {
        i >= location && i < location + length
    }
}
