// SPDX-License-Identifier: GPL-3.0-or-later
//
// Applies the StylePlan (SlopdownCore) to the text storage. Every decision about what is
// hidden, dimmed or rendered is made by StylePlanner; this file only turns roles into
// fonts, colors and drawing marks, and measures what needs AppKit (images, embeds,
// table columns). Nothing here changes the characters.

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

    // MARK: - Parsing

    func reparse(_ text: String) {
        elements = MarkdownParser.parse(text)
    }

    /// Incremental re-parse after an edit; returns the range whose elements changed.
    func update(_ text: String, editedRange: NSRange, delta: Int) -> NSRange {
        let u = MarkdownParser.update(elements, newText: text, editedRange: editedRange, delta: delta)
        elements = u.elements
        return u.dirty
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

    var planner: StylePlanner {
        var p = StylePlanner()
        p.sourceMode = sourceMode
        p.allowEmbeds = allowEmbeds
        p.isHugo = context.site != nil
        p.resolveLink = { [unowned self] in self.resolvedURL($0) }
        p.isExternal = { [context] in context.isExternal($0) }
        p.resolveImage = { [unowned self] in self.resolvedURL($0) }
        return p
    }

    // MARK: - Applying

    /// Restyles `requested`. The wanted attributes are computed on a scratch copy of just
    /// that range and only runs that differ are written back, so the text system
    /// re-lays out as little as possible.
    func apply(to storage: NSTextStorage, in requested: NSRange) {
        let text = storage.mutableString as NSString
        var range = NSIntersectionRange(requested, NSRange(location: 0, length: text.length))
        guard range.length > 0 else { return }
        // A table is measured as a whole, so restyle whole tables.
        for e in elements {
            if let row = e.tableRow, row.table.overlaps(range) {
                range = NSUnionRange(range, text.paragraphRange(for: row.table))
            }
        }

        let target = Target(scratch: NSMutableAttributedString(string: text.substring(with: range)), clip: range)
        target.scratch.setAttributes(Theme.baseAttributes(sourceMode: sourceMode),
                                     range: NSRange(location: 0, length: range.length))
        let planner = self.planner
        var tableSpans: [StyleSpan] = []
        for (i, e) in elements.enumerated() where e.range.overlaps(range)
            || (e.range.length == 0 && range.containsIndex(e.range.location)) {
            for span in planner.spans(for: e, revealed: revealed.contains(i), in: text) {
                switch span.role {
                case .tableRow, .tableDelimiter: tableSpans.append(span)
                default: apply(span, target)
                }
            }
        }
        if !tableSpans.isEmpty { styleTables(tableSpans, target) }

        storage.beginEditing()
        var loc = 0
        let end = range.length
        let whole = NSRange(location: 0, length: end)
        while loc < end {
            var wantRun = NSRange(), haveRun = NSRange()
            let want = target.scratch.attributes(at: loc, longestEffectiveRange: &wantRun, in: whole)
            let have = storage.attributes(at: loc + range.location, longestEffectiveRange: &haveRun, in: range)
            let runEnd = min(NSMaxRange(wantRun), NSMaxRange(haveRun) - range.location)
            if !NSDictionary(dictionary: want).isEqual(to: have) {
                storage.setAttributes(want, range: NSRange(location: loc + range.location, length: runEnd - loc))
            }
            loc = max(runEnd, loc + 1)
        }
        storage.endEditing()
    }

    /// Scratch copy of the restyled range; spans use document coordinates.
    private final class Target {
        let scratch: NSMutableAttributedString
        let clip: NSRange
        init(scratch: NSMutableAttributedString, clip: NSRange) { self.scratch = scratch; self.clip = clip }

        func local(_ r: NSRange) -> NSRange? {
            let x = NSIntersectionRange(r, clip)
            return x.length > 0 ? NSRange(location: x.location - clip.location, length: x.length) : nil
        }

        func set(_ attrs: [NSAttributedString.Key: Any], _ r: NSRange) {
            if let x = local(r) { scratch.addAttributes(attrs, range: x) }
        }

        func addTrait(_ trait: NSFontTraitMask, _ r: NSRange) {
            guard let x = local(r) else { return }
            scratch.enumerateAttribute(.font, in: x) { value, sub, _ in
                let font = (value as? NSFont) ?? Theme.bodyFont
                self.scratch.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: sub)
            }
        }
    }

    private func paragraph(_ change: (NSMutableParagraphStyle) -> Void) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.setParagraphStyle(Theme.paragraph)
        change(p)
        return p
    }

    private func apply(_ span: StyleSpan, _ t: Target) {
        let r = span.range
        switch span.role {
        case .hidden: t.set([.sdHidden: true], r)
        case .syntax: t.set([.foregroundColor: Theme.syntaxColor], r)
        case .secondary: t.set([.foregroundColor: Theme.secondaryColor], r)
        case .heading(let level):
            t.set([.font: Theme.headingFont(level: level),
                   .paragraphStyle: paragraph { $0.paragraphSpacingBefore = level <= 2 ? 10 : 6; $0.paragraphSpacing = 4 }], r)
        case .bold: t.addTrait(.boldFontMask, r)
        case .italic: t.addTrait(.italicFontMask, r)
        case .strikethrough: t.set([.strikethroughStyle: NSUnderlineStyle.single.rawValue], r)
        case .inlineCode: t.set([.font: Theme.monoFont, .backgroundColor: Theme.inlineCodeBackground], r)
        case .codeLine(let fence):
            t.set(fence ? [.font: Theme.monoFont, .foregroundColor: Theme.syntaxColor] : [.font: Theme.monoFont], r)
        case .frontmatter:
            t.set([.font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                   .foregroundColor: Theme.secondaryColor], r)
        case .blockBackground: t.set([.sdCodeBlock: true], r)
        case .quote:
            t.set([.paragraphStyle: paragraph { $0.firstLineHeadIndent = 18; $0.headIndent = 18 }, .sdQuote: true], r)
        case .bullet: t.set([.foregroundColor: NSColor.clear, .sdBullet: true], r)
        case .taskBox(let checked): t.set([.foregroundColor: NSColor.clear, .sdTask: NSNumber(value: checked)], r)
        case .done: t.set([.foregroundColor: Theme.secondaryColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue], r)
        case .rule: t.set([.foregroundColor: NSColor.clear, .sdRule: true], r)
        case .shortcode:
            t.set([.foregroundColor: Theme.secondaryColor, .font: Theme.monoFont,
                   .backgroundColor: Theme.inlineCodeBackground], r)
        case .sourceHeading: t.set([.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)], r)
        case .link(let look):
            switch look {
            case .hugoWikiWarning:
                // Hugo does not understand [[wiki links]]: they would be published as text.
                t.set([.foregroundColor: NSColor.systemOrange,
                       .underlineStyle: NSUnderlineStyle.single.union(.patternDot).rawValue,
                       .underlineColor: NSColor.systemOrange,
                       .toolTip: "Hugo doesn’t understand [[wiki links]]. Use ⇧⌘K to insert a link Hugo can build."], r)
            case .resolved, .unresolved:
                let color = look == .resolved ? Theme.linkColor : Theme.unresolvedLinkColor
                t.set([.foregroundColor: color, .underlineStyle: NSUnderlineStyle.single.rawValue,
                       .underlineColor: color.withAlphaComponent(0.35)], r)
            }
        case .blockImage(let url, let width, let height, let revealed, let fallback):
            guard let loaded = ImageStore.shared.image(at: url) else { return fallback.forEach { apply($0, t) } }
            let size = ImageStore.displaySize(natural: loaded.naturalSize, width: width, height: height, maxWidth: textWidth)
            t.set(revealed ? [.foregroundColor: Theme.syntaxColor] : [.sdHidden: true], r)
            t.set([.paragraphStyle: paragraph { $0.paragraphSpacing = size.height + 12 },
                   .sdImage: RenderedImage(image: loaded.image, size: size)], r)
        case .inlineImage(let url, let width, let height, let fallback):
            guard let loaded = ImageStore.shared.image(at: url) else { return fallback.forEach { apply($0, t) } }
            let size = ImageStore.displaySize(natural: loaded.naturalSize, width: width, height: height, maxWidth: textWidth)
            t.set([.sdInlineImage: RenderedImage(image: loaded.image, size: size), .foregroundColor: NSColor.clear],
                  NSRange(location: r.location, length: 1))
            t.set([.sdHidden: true], NSRange(location: r.location + 1, length: r.length - 1))
        case .embed(let url, let heading, let revealed, let fallback):
            guard let embed = EmbedStore.shared.embed(url, heading: heading,
                                                      width: max(100, textWidth - RenderedEmbed.inset.width * 2)) else {
                return fallback.forEach { apply($0, t) }
            }
            if revealed { fallback.forEach { apply($0, t) } } else { t.set([.sdHidden: true], r) }
            t.set([.paragraphStyle: paragraph { $0.paragraphSpacing = embed.boxHeight + 12 }, .sdEmbed: embed], r)
        case .tableRow, .tableDelimiter:
            break // styleTables
        }
    }

    // MARK: - Tables

    private struct TableLine {
        var range: NSRange
        var row: MDTableRow
        var hidden: [NSRange]
        var isDelimiter: Bool
        var revealed: Bool
    }

    /// Tables are styled after everything else, because column widths are measured
    /// from the already-styled cell text (bold, code, hidden syntax, inline images).
    private func styleTables(_ spans: [StyleSpan], _ t: Target) {
        var tables: [Int: [TableLine]] = [:]
        for s in spans {
            switch s.role {
            case .tableRow(let row, let hidden, let revealed):
                tables[row.table.location, default: []].append(TableLine(range: s.range, row: row, hidden: hidden,
                                                                          isDelimiter: false, revealed: revealed))
            case .tableDelimiter(let row, let revealed):
                tables[row.table.location, default: []].append(TableLine(range: s.range, row: row, hidden: [],
                                                                          isDelimiter: true, revealed: revealed))
            default: break
            }
        }
        for (_, lines) in tables {
            if lines.contains(where: { $0.revealed }) || !renderTable(lines, t) {
                for l in lines {   // plain markdown, pipes dimmed
                    if l.isDelimiter { t.set([.foregroundColor: Theme.syntaxColor], l.range); continue }
                    for p in l.row.pipes + [l.row.leading].compactMap({ $0 }) + l.hidden {
                        t.set([.foregroundColor: Theme.syntaxColor], p)
                    }
                }
            }
        }
    }

    /// Visible width of a styled range: hidden characters skipped, inline images counted.
    private func visibleWidth(_ t: Target, _ r: NSRange) -> CGFloat {
        guard let x = t.local(r) else { return 0 }
        let visible = NSMutableAttributedString()
        var extra: CGFloat = 0
        t.scratch.enumerateAttributes(in: x) { attrs, run, _ in
            if let img = attrs[.sdInlineImage] as? RenderedImage { extra += img.size.width + 2; return }
            if attrs[.sdHidden] != nil { return }
            visible.append(t.scratch.attributedSubstring(from: run))
        }
        return ceil(visible.size().width + extra)
    }

    private func lineWithBreak(_ r: NSRange, _ t: Target) -> NSRange {
        NSRange(location: r.location, length: r.length + 1)   // clipped by Target
    }

    /// Returns false when the table does not fit the text width (it then stays raw).
    private func renderTable(_ lines: [TableLine], _ t: Target) -> Bool {
        guard let first = lines.first?.row else { return false }
        let columns = first.alignments.count
        let pad = TableLayout.padding

        for l in lines where !l.isDelimiter && l.row.isHeader {
            for c in l.row.cells { t.addTrait(.boldFontMask, c) }
        }
        var cellWidth: [Int: CGFloat] = [:]
        var widths = [CGFloat](repeating: 16, count: columns)
        for l in lines where !l.isDelimiter {
            for (c, cell) in l.row.cells.enumerated() where c < columns {
                let w = visibleWidth(t, cell)
                cellWidth[cell.location] = w
                widths[c] = max(widths[c], w)
            }
        }
        let layout = TableLayout(columnWidths: widths.map { $0 + 2 * pad }, alignments: first.alignments)
        guard layout.totalWidth <= textWidth else { return false }
        let starts = layout.columnStarts

        for l in lines {
            if l.isDelimiter {
                let p = NSMutableParagraphStyle()
                p.minimumLineHeight = 1
                p.maximumLineHeight = 1
                t.set([.sdHidden: true, .font: NSFont.systemFont(ofSize: 1), .paragraphStyle: p,
                       .sdTable: TableRowDecoration(layout: layout, isHeader: false, isDelimiter: true)],
                      lineWithBreak(l.range, t))
                continue
            }
            let p = paragraph {
                $0.lineSpacing = 5
                $0.paragraphSpacingBefore = 4
                $0.firstLineHeadIndent = l.row.leading == nil ? pad : 0
                $0.headIndent = pad
                $0.lineBreakMode = .byClipping
            }
            t.set([.paragraphStyle: p,
                   .sdTable: TableRowDecoration(layout: layout, isHeader: l.row.isHeader, isDelimiter: false)],
                  lineWithBreak(l.range, t))
            for h in l.hidden { t.set([.sdHidden: true], h) }

            // The separator before each cell becomes a gap that ends where the cell starts.
            for (c, cell) in l.row.cells.enumerated() where c < columns {
                let sep: NSRange? = c == 0 ? l.row.leading : (c - 1 < l.row.pipes.count ? l.row.pipes[c - 1] : nil)
                guard let sep else { continue }
                let content = layout.columnWidths[c] - 2 * pad
                let w = cellWidth[cell.location] ?? 0
                let offset: CGFloat
                switch layout.alignments[c] {
                case .left: offset = 0
                case .center: offset = max(0, (content - w) / 2)
                case .right: offset = max(0, content - w)
                }
                t.set([.sdTabPipe: NSNumber(value: Double(starts[c] + pad + offset)), .foregroundColor: NSColor.clear], sep)
            }
            // Extra pipes (more cells than columns) are just hidden.
            for pipe in l.row.pipes.dropFirst(max(0, columns - 1)) { t.set([.sdHidden: true], pipe) }
        }
        return true
    }

    // MARK: - Links

    func isResolved(_ link: MDLink) -> Bool {
        if context.isExternal(link) || LinkContext.fileTarget(of: link).isEmpty { return true }
        return resolvedURL(link) != nil
    }

    func resolvedURL(_ link: MDLink) -> URL? {
        resolutions.lookup("L\(link.style)|\(link.target)|\(context.document?.path ?? "")") { context.resolve(link) }
    }

    /// Images and embeds are drawn into the note without a click, so files in hidden,
    /// Library, system or other users' folders are never rendered (LinkSafety).
    func resolvedURL(_ img: MDImage) -> URL? {
        resolutions.lookup("I\(img.isWiki)|\(img.source)|\(context.document?.path ?? "")") {
            context.resolveImage(img).flatMap { LinkSafety.isRenderable($0) ? $0 : nil }
        }
    }
}
#endif
