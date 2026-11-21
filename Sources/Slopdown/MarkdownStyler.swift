// SPDX-License-Identifier: GPL-3.0-or-later
//
// Turns parser elements into text attributes. Nothing here changes the characters:
// live preview is done purely with attributes (fonts, colors, "hidden" marks read
// by GlyphConcealer, and decoration marks drawn by EditorTextView).

#if canImport(AppKit)
import AppKit
import SlopdownCore

final class MarkdownStyler {
    private(set) var elements: [MDElement] = []
    /// Indexes of elements whose markdown syntax is currently shown.
    var revealed: Set<Int> = []
    var sourceMode = false
    /// Render `![[Note]]` contents (off inside an embed, so embeds don't nest).
    var allowEmbeds = true
    /// Where the note lives (plain folder or Hugo site): how links resolve.
    var context = LinkContext()
    var baseDirectory: URL? { context.baseDirectory }
    /// Usable text width (for image sizing).
    var textWidth: CGFloat = Theme.readableWidth
    let resolutions = ResolutionCache()

    func reparse(_ text: String) {
        elements = MarkdownParser.parse(text)
    }

    /// Elements touched by the selection show their syntax.
    func revealedElements(for selection: [NSRange]) -> Set<Int> {
        guard !sourceMode else { return [] }
        var result = Set<Int>()
        for (i, e) in elements.enumerated() {
            for sel in selection where sel.touches(e.revealRange) {
                result.insert(i)
                break
            }
        }
        return result
    }

    // MARK: - Styling

    /// Restyles `requested`. The wanted attributes are computed on a scratch copy and only
    /// runs that actually differ are written back, so the text system re-lays out as
    /// little as possible (important because this runs on every keystroke).
    func apply(to storage: NSTextStorage, in requested: NSRange) {
        var range = NSIntersectionRange(requested, NSRange(location: 0, length: storage.length))
        guard range.length > 0 else { return }
        // A table is measured as a whole, so restyle whole tables.
        for e in elements {
            if let row = e.tableRow, row.table.overlaps(range) {
                range = NSUnionRange(range, (storage.string as NSString).paragraphRange(for: row.table))
            }
        }

        let scratch = NSMutableAttributedString(string: storage.string)
        scratch.setAttributes(Theme.baseAttributes(sourceMode: sourceMode), range: range)
        if sourceMode {
            for e in elements where e.range.overlaps(range) || paragraphTouches(e, range) {
                styleSource(e, scratch, clip: range)
            }
        } else {
            for (i, e) in elements.enumerated() where e.range.overlaps(range) || paragraphTouches(e, range) {
                style(e, revealed: revealed.contains(i), scratch, clip: range)
            }
            styleTables(scratch, clip: range)
        }

        storage.beginEditing()
        var loc = range.location
        let end = NSMaxRange(range)
        while loc < end {
            var wantRun = NSRange(), haveRun = NSRange()
            let want = scratch.attributes(at: loc, longestEffectiveRange: &wantRun, in: range)
            let have = storage.attributes(at: loc, longestEffectiveRange: &haveRun, in: range)
            let runEnd = min(NSMaxRange(wantRun), NSMaxRange(haveRun))
            if !NSDictionary(dictionary: want).isEqual(to: have) {
                storage.setAttributes(want, range: NSRange(location: loc, length: runEnd - loc))
            }
            loc = max(runEnd, loc + 1)
        }
        storage.endEditing()
    }

    /// Empty lines inside code blocks have an empty range but still need their background.
    private func paragraphTouches(_ e: MDElement, _ range: NSRange) -> Bool {
        e.range.length == 0 && range.containsIndex(e.range.location)
    }

    private func set(_ storage: NSMutableAttributedString, _ attrs: [NSAttributedString.Key: Any], _ r: NSRange, clip: NSRange) {
        let x = NSIntersectionRange(r, clip)
        if x.length > 0 { storage.addAttributes(attrs, range: x) }
    }

    private func addTrait(_ storage: NSMutableAttributedString, _ trait: NSFontTraitMask, _ r: NSRange, clip: NSRange) {
        let x = NSIntersectionRange(r, clip)
        guard x.length > 0 else { return }
        storage.enumerateAttribute(.font, in: x) { value, sub, _ in
            let font = (value as? NSFont) ?? Theme.bodyFont
            let converted = NSFontManager.shared.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: sub)
        }
    }

    private func hideOrDim(_ e: MDElement, revealed: Bool, _ storage: NSMutableAttributedString, clip: NSRange) {
        for h in e.hidden {
            if revealed {
                set(storage, [.foregroundColor: Theme.syntaxColor], h, clip: clip)
            } else {
                set(storage, [.sdHidden: true], h, clip: clip)
            }
        }
    }

    /// Line range including its line break (so empty lines get a line fragment to draw on).
    private func lineWithBreak(_ r: NSRange, _ storage: NSMutableAttributedString) -> NSRange {
        NSRange(location: r.location, length: min(r.length + 1, storage.length - r.location))
    }

    private func style(_ e: MDElement, revealed: Bool, _ storage: NSMutableAttributedString, clip: NSRange) {
        switch e.kind {
        case .heading(let level):
            set(storage, [.font: Theme.headingFont(level: level)], e.range, clip: clip)
            let p = NSMutableParagraphStyle()
            p.setParagraphStyle(Theme.paragraph)
            p.paragraphSpacingBefore = level <= 2 ? 10 : 6
            p.paragraphSpacing = 4
            set(storage, [.paragraphStyle: p], e.range, clip: clip)
            hideOrDim(e, revealed: revealed, storage, clip: clip)

        case .blockquote:
            let p = NSMutableParagraphStyle()
            p.setParagraphStyle(Theme.paragraph)
            p.firstLineHeadIndent = 18
            p.headIndent = 18
            set(storage, [.paragraphStyle: p, .sdQuote: true], e.range, clip: clip)
            set(storage, [.foregroundColor: Theme.secondaryColor], e.content, clip: clip)
            hideOrDim(e, revealed: revealed, storage, clip: clip)

        case .bulletItem:
            if revealed {
                set(storage, [.foregroundColor: Theme.syntaxColor], e.marker, clip: clip)
            } else {
                set(storage, [.foregroundColor: NSColor.clear, .sdBullet: true], e.marker, clip: clip)
            }

        case .orderedItem:
            set(storage, [.foregroundColor: Theme.secondaryColor], e.marker, clip: clip)

        case .task(let checked):
            if revealed {
                set(storage, [.foregroundColor: Theme.syntaxColor], e.marker, clip: clip)
                hideOrDim(e, revealed: true, storage, clip: clip)
            } else {
                hideOrDim(e, revealed: false, storage, clip: clip)
                set(storage, [.foregroundColor: NSColor.clear, .sdTask: NSNumber(value: checked)], e.marker, clip: clip)
            }
            if checked {
                set(storage, [.foregroundColor: Theme.secondaryColor,
                              .strikethroughStyle: NSUnderlineStyle.single.rawValue], e.content, clip: clip)
            }

        case .rule:
            if revealed {
                set(storage, [.foregroundColor: Theme.syntaxColor], e.range, clip: clip)
            } else {
                set(storage, [.foregroundColor: NSColor.clear, .sdRule: true], e.range, clip: clip)
            }

        case .codeFence:
            set(storage, [.font: Theme.monoFont, .foregroundColor: Theme.syntaxColor], e.range, clip: clip)
            set(storage, [.sdCodeBlock: true], lineWithBreak(e.range, storage), clip: clip)

        case .codeLine:
            set(storage, [.font: Theme.monoFont], e.range, clip: clip)
            set(storage, [.sdCodeBlock: true], lineWithBreak(e.range, storage), clip: clip)

        case .frontmatter:
            set(storage, [.font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                          .foregroundColor: Theme.secondaryColor], e.range, clip: clip)
            set(storage, [.sdCodeBlock: true], lineWithBreak(e.range, storage), clip: clip)

        case .bold:
            addTrait(storage, .boldFontMask, e.content, clip: clip)
            hideOrDim(e, revealed: revealed, storage, clip: clip)

        case .italic:
            addTrait(storage, .italicFontMask, e.content, clip: clip)
            hideOrDim(e, revealed: revealed, storage, clip: clip)

        case .boldItalic:
            addTrait(storage, .boldFontMask, e.content, clip: clip)
            addTrait(storage, .italicFontMask, e.content, clip: clip)
            hideOrDim(e, revealed: revealed, storage, clip: clip)

        case .strikethrough:
            set(storage, [.strikethroughStyle: NSUnderlineStyle.single.rawValue], e.content, clip: clip)
            hideOrDim(e, revealed: revealed, storage, clip: clip)

        case .inlineCode:
            set(storage, [.font: Theme.monoFont, .backgroundColor: Theme.inlineCodeBackground], e.content, clip: clip)
            hideOrDim(e, revealed: revealed, storage, clip: clip)

        case .tableRow, .tableDelimiter:
            break // styleTables()

        case .link(let link) where link.style == .embed && allowEmbeds && !link.target.isEmpty:
            guard isAloneOnLine(e, storage), let url = resolvedURL(link), LinkResolver.isMarkdownFile(url),
                  let embed = EmbedStore.shared.embed(url, heading: link.heading,
                                                      width: max(100, textWidth - RenderedEmbed.inset.width * 2)) else {
                styleLink(e, link, revealed: revealed, storage, clip: clip)
                return
            }
            if revealed {
                styleLink(e, link, revealed: true, storage, clip: clip)
            } else {
                set(storage, [.sdHidden: true], e.range, clip: clip)
            }
            let p = NSMutableParagraphStyle()
            p.setParagraphStyle(Theme.paragraph)
            p.paragraphSpacing = embed.boxHeight + 12
            set(storage, [.paragraphStyle: p, .sdEmbed: embed], e.range, clip: clip)

        case .link(let link):
            styleLink(e, link, revealed: revealed, storage, clip: clip)

        case .shortcode:
            set(storage, [.foregroundColor: Theme.secondaryColor, .font: Theme.monoFont,
                          .backgroundColor: Theme.inlineCodeBackground], e.range, clip: clip)

        case .image(let img) where img.standalone:
            styleBlockImage(e, img, revealed: revealed, storage, clip: clip)

        case .image(let img):
            guard !revealed, !img.isRemote, let url = resolvedURL(img),
                  let loaded = ImageStore.shared.image(at: url), e.range.length > 1 else {
                set(storage, [.foregroundColor: revealed ? Theme.syntaxColor : Theme.secondaryColor], e.range, clip: clip)
                return
            }
            let size = ImageStore.displaySize(natural: loaded.naturalSize, width: img.width,
                                              height: img.height, maxWidth: textWidth)
            let first = NSRange(location: e.range.location, length: 1)
            let rest = NSRange(location: e.range.location + 1, length: e.range.length - 1)
            set(storage, [.sdInlineImage: RenderedImage(image: loaded.image, size: size),
                          .foregroundColor: NSColor.clear], first, clip: clip)
            set(storage, [.sdHidden: true], rest, clip: clip)
        }
    }

    private func styleLink(_ e: MDElement, _ link: MDLink, revealed: Bool, _ storage: NSMutableAttributedString, clip: NSRange) {
        do {
            if context.site != nil, link.isWikiStyle {
                // Hugo does not understand [[wiki links]]: they would be published as text.
                set(storage, [.foregroundColor: NSColor.systemOrange,
                              .underlineStyle: NSUnderlineStyle.single.union(.patternDot).rawValue,
                              .underlineColor: NSColor.systemOrange,
                              .toolTip: "Hugo doesn’t understand [[wiki links]]. Use ⇧⌘K to insert a link Hugo can build."],
                    e.content, clip: clip)
                hideOrDim(e, revealed: revealed, storage, clip: clip)
                return
            }
            let color = isResolved(link) ? Theme.linkColor : Theme.unresolvedLinkColor
            set(storage, [.foregroundColor: color,
                          .underlineStyle: NSUnderlineStyle.single.rawValue,
                          .underlineColor: color.withAlphaComponent(0.35)], e.content, clip: clip)
            hideOrDim(e, revealed: revealed, storage, clip: clip)
        }
    }

    private func styleBlockImage(_ e: MDElement, _ img: MDImage, revealed: Bool, _ storage: NSMutableAttributedString, clip: NSRange) {
        do {
            guard img.standalone, !img.isRemote, let url = resolvedURL(img),
                  let loaded = ImageStore.shared.image(at: url) else {
                // Remote, inline, missing or undecodable: leave the syntax visible, dimmed.
                set(storage, [.foregroundColor: Theme.secondaryColor], e.range, clip: clip)
                return
            }
            let size = ImageStore.displaySize(natural: loaded.naturalSize, width: img.width,
                                              height: img.height, maxWidth: textWidth)
            if revealed {
                set(storage, [.foregroundColor: Theme.syntaxColor], e.range, clip: clip)
            } else {
                set(storage, [.sdHidden: true], e.range, clip: clip)
            }
            let p = NSMutableParagraphStyle()
            p.setParagraphStyle(Theme.paragraph)
            p.paragraphSpacing = size.height + 12
            set(storage, [.paragraphStyle: p,
                          .sdImage: RenderedImage(image: loaded.image, size: size)], e.range, clip: clip)
        }
    }

    /// Source mode: everything visible, monospaced, only light syntax coloring.
    private func styleSource(_ e: MDElement, _ storage: NSMutableAttributedString, clip: NSRange) {
        switch e.kind {
        case .heading:
            set(storage, [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)], e.range, clip: clip)
            for h in e.hidden { set(storage, [.foregroundColor: Theme.syntaxColor], h, clip: clip) }
        case .codeFence, .codeLine, .frontmatter:
            set(storage, [.foregroundColor: Theme.secondaryColor], e.range, clip: clip)
        case .shortcode:
            set(storage, [.foregroundColor: Theme.secondaryColor], e.range, clip: clip)
        case .link:
            set(storage, [.foregroundColor: Theme.linkColor], e.content, clip: clip)
            for h in e.hidden { set(storage, [.foregroundColor: Theme.syntaxColor], h, clip: clip) }
        case .bulletItem, .orderedItem:
            set(storage, [.foregroundColor: Theme.secondaryColor], e.marker, clip: clip)
        case .task:
            set(storage, [.foregroundColor: Theme.secondaryColor], e.marker, clip: clip)
            for h in e.hidden { set(storage, [.foregroundColor: Theme.secondaryColor], h, clip: clip) }
        case .rule, .image, .tableDelimiter:
            set(storage, [.foregroundColor: Theme.syntaxColor], e.range, clip: clip)
        case .tableRow(let row):
            for p in row.pipes { set(storage, [.foregroundColor: Theme.syntaxColor], p, clip: clip) }
            for h in e.hidden { set(storage, [.foregroundColor: Theme.syntaxColor], h, clip: clip) }
        default:
            for h in e.hidden { set(storage, [.foregroundColor: Theme.syntaxColor], h, clip: clip) }
        }
    }

    // MARK: - Tables

    /// Tables are styled after everything else, because column widths are measured
    /// from the already-styled cell text (bold, code, hidden syntax, inline images).
    private func styleTables(_ storage: NSMutableAttributedString, clip: NSRange) {
        var tables: [Int: [(index: Int, element: MDElement, row: MDTableRow)]] = [:]
        for (i, e) in elements.enumerated() {
            guard let row = e.tableRow, row.table.overlaps(clip) else { continue }
            tables[row.table.location, default: []].append((i, e, row))
        }
        for (_, rows) in tables {
            let isRevealed = rows.contains { revealed.contains($0.index) }
            if isRevealed || !renderTable(rows.map { ($0.element, $0.row) }, storage, clip: clip) {
                // Plain markdown, pipes dimmed
                for (_, e, row) in rows {
                    if case .tableDelimiter = e.kind {
                        set(storage, [.foregroundColor: Theme.syntaxColor], e.range, clip: clip)
                        continue
                    }
                    for p in row.pipes + [row.leading].compactMap({ $0 }) {
                        set(storage, [.foregroundColor: Theme.syntaxColor], p, clip: clip)
                    }
                    for h in e.hidden { set(storage, [.foregroundColor: Theme.syntaxColor], h, clip: clip) }
                }
            }
        }
    }

    /// Visible width of a styled range: hidden characters skipped, inline images counted.
    private func visibleWidth(_ storage: NSMutableAttributedString, _ r: NSRange) -> CGFloat {
        guard r.length > 0 else { return 0 }
        let visible = NSMutableAttributedString()
        var extra: CGFloat = 0
        storage.enumerateAttributes(in: r) { attrs, run, _ in
            if let img = attrs[.sdInlineImage] as? RenderedImage { extra += img.size.width + 2; return }
            if attrs[.sdHidden] != nil { return }
            visible.append(storage.attributedSubstring(from: run))
        }
        return ceil(visible.size().width + extra)
    }

    /// Returns false when the table does not fit the text width (it then stays raw).
    private func renderTable(_ rows: [(MDElement, MDTableRow)], _ storage: NSMutableAttributedString, clip: NSRange) -> Bool {
        guard let first = rows.first?.1 else { return false }
        let columns = first.alignments.count
        let pad = TableLayout.padding

        // Header in bold, then measure
        for (e, row) in rows where row.isHeader {
            if case .tableRow = e.kind { for c in row.cells { addTrait(storage, .boldFontMask, c, clip: clip) } }
        }
        var cellWidth: [Int: CGFloat] = [:]
        var widths = [CGFloat](repeating: 16, count: columns)
        for (e, row) in rows {
            guard case .tableRow = e.kind else { continue }
            for (c, cell) in row.cells.enumerated() where c < columns {
                let w = visibleWidth(storage, cell)
                cellWidth[cell.location] = w
                widths[c] = max(widths[c], w)
            }
        }
        let layout = TableLayout(columnWidths: widths.map { $0 + 2 * pad }, alignments: first.alignments)
        guard layout.totalWidth <= textWidth else { return false }
        let starts = layout.columnStarts

        for (e, row) in rows {
            if case .tableDelimiter = e.kind {
                let p = NSMutableParagraphStyle()
                p.minimumLineHeight = 1
                p.maximumLineHeight = 1
                set(storage, [.sdHidden: true, .font: NSFont.systemFont(ofSize: 1), .paragraphStyle: p,
                              .sdTable: TableRowDecoration(layout: layout, isHeader: false, isDelimiter: true)],
                    lineWithBreak(e.range, storage), clip: clip)
                continue
            }
            let p = NSMutableParagraphStyle()
            p.setParagraphStyle(Theme.paragraph)
            p.lineSpacing = 5
            p.paragraphSpacingBefore = 4
            p.firstLineHeadIndent = row.leading == nil ? pad : 0
            p.headIndent = pad
            p.lineBreakMode = .byClipping
            set(storage, [.paragraphStyle: p,
                          .sdTable: TableRowDecoration(layout: layout, isHeader: row.isHeader, isDelimiter: false)],
                lineWithBreak(e.range, storage), clip: clip)
            for h in e.hidden { set(storage, [.sdHidden: true], h, clip: clip) }

            // The separator before each cell becomes a gap that ends where the cell starts.
            for (c, cell) in row.cells.enumerated() where c < columns {
                let sep: NSRange? = c == 0 ? row.leading : (c - 1 < row.pipes.count ? row.pipes[c - 1] : nil)
                guard let sep else { continue }
                let content = layout.columnWidths[c] - 2 * pad
                let w = cellWidth[cell.location] ?? 0
                let offset: CGFloat
                switch layout.alignments[c] {
                case .left: offset = 0
                case .center: offset = max(0, (content - w) / 2)
                case .right: offset = max(0, content - w)
                }
                set(storage, [.sdTabPipe: NSNumber(value: Double(starts[c] + pad + offset)),
                              .foregroundColor: NSColor.clear], sep, clip: clip)
            }
            // Extra pipes (more cells than columns) are just hidden.
            for p in row.pipes.dropFirst(max(0, columns - 1)) { set(storage, [.sdHidden: true], p, clip: clip) }
        }
        return true
    }

    private func isAloneOnLine(_ e: MDElement, _ storage: NSMutableAttributedString) -> Bool {
        let ns = storage.string as NSString
        let line = ns.lineRange(for: e.range)
        let before = ns.substring(with: NSRange(location: line.location, length: e.range.location - line.location))
        let after = ns.substring(with: NSRange(location: NSMaxRange(e.range), length: NSMaxRange(line) - NSMaxRange(e.range)))
        return before.trimmingCharacters(in: .whitespaces).isEmpty && after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Links

    func isResolved(_ link: MDLink) -> Bool {
        if context.isExternal(link) || LinkContext.fileTarget(of: link).isEmpty { return true }
        return resolvedURL(link) != nil
    }

    func resolvedURL(_ link: MDLink) -> URL? {
        resolutions.lookup("L\(link.style)|\(link.target)|\(context.document?.path ?? "")") { context.resolve(link) }
    }

    func resolvedURL(_ img: MDImage) -> URL? {
        resolutions.lookup("I\(img.isWiki)|\(img.source)|\(context.document?.path ?? "")") { context.resolveImage(img) }
    }
}
#endif
