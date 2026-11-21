// SPDX-License-Identifier: GPL-3.0-or-later
//
// Rendered blocks that are drawn by EditorTextView rather than laid out as text:
// table geometry and embedded notes.

#if canImport(AppKit)
import AppKit
import SlopdownCore

// MARK: - Tables

/// Column geometry of one table, shared by all its rows.
final class TableLayout: NSObject {
    static let padding: CGFloat = 10

    let columnWidths: [CGFloat]
    let alignments: [MDAlignment]
    var totalWidth: CGFloat { columnWidths.reduce(0, +) }

    init(columnWidths: [CGFloat], alignments: [MDAlignment]) {
        self.columnWidths = columnWidths
        self.alignments = alignments
    }

    /// x of each column's left edge, relative to the start of the line.
    var columnStarts: [CGFloat] {
        var x: CGFloat = 0
        return columnWidths.map { w in defer { x += w }; return x }
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? TableLayout else { return false }
        return o.columnWidths == columnWidths && o.alignments == alignments
    }

    override var hash: Int { columnWidths.count }
}

final class TableRowDecoration: NSObject {
    let layout: TableLayout
    let isHeader: Bool
    let isDelimiter: Bool

    init(layout: TableLayout, isHeader: Bool, isDelimiter: Bool) {
        self.layout = layout
        self.isHeader = isHeader
        self.isDelimiter = isDelimiter
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? TableRowDecoration else { return false }
        return o.layout == layout && o.isHeader == isHeader && o.isDelimiter == isDelimiter
    }

    override var hash: Int { layout.hash }
}

// MARK: - Embedded notes

final class RenderedEmbed: NSObject {
    static let inset = NSSize(width: 16, height: 10)
    static let maxHeight: CGFloat = 900

    let text: NSAttributedString
    let textHeight: CGFloat
    let url: URL

    init(text: NSAttributedString, textHeight: CGFloat, url: URL) {
        self.text = text
        self.textHeight = textHeight
        self.url = url
    }

    var boxHeight: CGFloat { min(textHeight, Self.maxHeight) + 2 * Self.inset.height }
}

/// Renders `![[Note]]` / `![[Note#Heading]]` into a flat attributed string (syntax
/// removed, decorations replaced by characters or attachments) and caches it.
final class EmbedStore {
    static let shared = EmbedStore()

    private struct Key: Hashable { let path: String; let heading: String?; let width: Int }
    private var cache: [Key: (modified: Date?, embed: RenderedEmbed)] = [:]

    func embed(_ url: URL, heading: String?, width: CGFloat) -> RenderedEmbed? {
        let key = Key(path: url.path, heading: heading, width: Int(width))
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let c = cache[key], c.modified == modified { return c.embed }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let full = String(decoding: data, as: UTF8.self)
        guard let section = Self.section(of: full, heading: heading) else { return nil }

        let sub = MarkdownStyler()
        sub.allowEmbeds = false
        sub.context = LinkContext(document: url, site: HugoSite.containing(url))
        sub.textWidth = width
        sub.reparse(section)
        let storage = NSTextStorage(string: section)
        sub.apply(to: storage, in: NSRange(location: 0, length: storage.length))
        let flat = Self.flatten(storage)
        let bounds = flat.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        let embed = RenderedEmbed(text: flat, textHeight: ceil(bounds.height), url: url)
        cache[key] = (modified, embed)
        return embed
    }

    /// The whole note, or one heading's section (up to the next heading of the same or
    /// a higher level).
    static func section(of text: String, heading: String?) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let heading, !heading.isEmpty else { return trimmed }
        let ns = NSString(string: text)
        let els = MarkdownParser.parse(text)
        let wanted = heading.trimmingCharacters(in: .whitespaces).lowercased()
        var start: (loc: Int, level: Int)? = nil
        for e in els {
            guard case .heading(let level) = e.kind else { continue }
            if let s = start {
                if level <= s.level {
                    return ns.substring(with: NSRange(location: s.loc, length: e.range.location - s.loc))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if ns.substring(with: e.content).trimmingCharacters(in: .whitespaces).lowercased() == wanted {
                start = (e.range.location, level)
            }
        }
        guard let s = start else { return nil }
        return ns.substring(from: s.loc).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let customKeys: [NSAttributedString.Key] = [
        .sdHidden, .sdBullet, .sdTask, .sdRule, .sdImage, .sdQuote, .sdCodeBlock,
        .sdTabPipe, .sdTable, .sdInlineImage, .sdEmbed,
    ]

    /// Live-preview attributes → plain drawable attributed string.
    static func flatten(_ s: NSAttributedString) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let ns = s.string as NSString
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { attrs, run, _ in
            var clean = attrs
            for k in customKeys { clean[k] = nil }
            func append(_ str: String, color: NSColor? = nil) {
                var a = clean
                if let color { a[.foregroundColor] = color }
                out.append(NSAttributedString(string: str, attributes: a))
            }
            func attachment(_ img: RenderedImage) {
                let att = NSTextAttachment()
                att.image = img.image
                att.bounds = NSRect(origin: .zero, size: img.size)
                let a = NSMutableAttributedString(attachment: att)
                var plain = clean
                plain[.paragraphStyle] = Theme.paragraph   // drop the space reserved for drawing
                a.addAttributes(plain, range: NSRange(location: 0, length: a.length))
                out.append(a)
            }
            if let img = attrs[.sdImage] as? RenderedImage {
                attachment(img)
            } else if let img = attrs[.sdInlineImage] as? RenderedImage {
                attachment(img)
            } else if attrs[.sdHidden] != nil {
                return
            } else if attrs[.sdBullet] != nil {
                append("•", color: .labelColor)
            } else if let checked = attrs[.sdTask] as? NSNumber {
                append(checked.boolValue ? "☑" : "☐", color: .secondaryLabelColor)
            } else if attrs[.sdRule] != nil {
                append(String(repeating: "─", count: 24), color: .separatorColor)
            } else if attrs[.sdTabPipe] != nil {
                append(String(repeating: "\t", count: run.length))
            } else {
                append(ns.substring(with: run))
            }
        }
        return out
    }
}
#endif
