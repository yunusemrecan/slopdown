// SPDX-License-Identifier: GPL-3.0-or-later
//
// What the live preview should look like, as plain data: for each parsed element a list
// of spans (range + role). The app turns roles into fonts, colors and drawing; every
// decision about what is hidden, dimmed, rendered or left as text is made here, where
// it can be unit-tested without AppKit.

import Foundation

public enum LinkLook: Equatable {
    case resolved
    case unresolved
    /// `[[wiki link]]` inside a Hugo site: Hugo can't build it.
    case hugoWikiWarning
}

public indirect enum StyleRole: Equatable {
    /// Laid out as nothing (null glyphs).
    case hidden
    /// Visible markdown syntax, dimmed.
    case syntax
    /// Secondary text color (quotes, ordered-list numbers, unrendered images).
    case secondary
    case heading(level: Int)
    case bold
    case italic
    case strikethrough
    case inlineCode
    /// Monospaced code block line (`fence`: the ``` line itself, dimmed).
    case codeLine(fence: Bool)
    case frontmatter
    /// Code block / front matter background, on the line including its line break.
    case blockBackground
    case quote
    /// List bullet drawn as a dot (the character is kept for layout but not drawn).
    case bullet
    /// Task checkbox drawn over `[ ]`.
    case taskBox(checked: Bool)
    /// Checked task text.
    case done
    /// Horizontal rule drawn across the line.
    case rule
    case link(LinkLook)
    case shortcode
    /// An image on its own line, drawn below it. `fallback` applies when it can't be loaded.
    case blockImage(url: URL, width: Double?, height: Double?, revealed: Bool, fallback: [StyleSpan])
    /// An image inside a sentence (only when not revealed).
    case inlineImage(url: URL, width: Double?, height: Double?, fallback: [StyleSpan])
    /// A note embedded below its line.
    case embed(url: URL, heading: String?, revealed: Bool, fallback: [StyleSpan])
    /// Table rows are measured and drawn by the app after all other spans.
    case tableRow(MDTableRow, hidden: [NSRange], revealed: Bool)
    case tableDelimiter(MDTableRow, revealed: Bool)
    /// Source mode heading line (bold, monospaced).
    case sourceHeading
}

public struct StyleSpan: Equatable {
    public var range: NSRange
    public var role: StyleRole

    public init(_ range: NSRange, _ role: StyleRole) {
        self.range = range
        self.role = role
    }
}

public struct StylePlanner {
    public var sourceMode = false
    /// Render `![[Note]]` contents (off inside an embed, so embeds don't nest).
    public var allowEmbeds = true
    public var isHugo = false
    /// File behind a link, nil when it doesn't exist.
    public var resolveLink: (MDLink) -> URL? = { _ in nil }
    public var isExternal: (MDLink) -> Bool = { _ in false }
    /// Image file that may be rendered (safety rules already applied).
    public var resolveImage: (MDImage) -> URL? = { _ in nil }

    public init() {}

    /// Spans for one element, in the order they should be applied.
    public func spans(for e: MDElement, revealed: Bool, in text: NSString) -> [StyleSpan] {
        sourceMode ? sourceSpans(e) : previewSpans(e, revealed: revealed, text)
    }

    // MARK: - Live preview

    private func hideOrDim(_ e: MDElement, _ revealed: Bool) -> [StyleSpan] {
        e.hidden.map { StyleSpan($0, revealed ? .syntax : .hidden) }
    }

    private func lineWithBreak(_ r: NSRange, _ text: NSString) -> NSRange {
        NSRange(location: r.location, length: min(r.length + 1, text.length - r.location))
    }

    private func previewSpans(_ e: MDElement, revealed: Bool, _ text: NSString) -> [StyleSpan] {
        switch e.kind {
        case .heading(let level):
            return [StyleSpan(e.range, .heading(level: level))] + hideOrDim(e, revealed)
        case .blockquote:
            return [StyleSpan(e.range, .quote), StyleSpan(e.content, .secondary)] + hideOrDim(e, revealed)
        case .bulletItem:
            return [StyleSpan(e.marker, revealed ? .syntax : .bullet)]
        case .orderedItem:
            return [StyleSpan(e.marker, .secondary)]
        case .task(let checked):
            var s = revealed
                ? [StyleSpan(e.marker, .syntax)] + hideOrDim(e, true)
                : hideOrDim(e, false) + [StyleSpan(e.marker, .taskBox(checked: checked))]
            if checked { s.append(StyleSpan(e.content, .done)) }
            return s
        case .rule:
            return [StyleSpan(e.range, revealed ? .syntax : .rule)]
        case .codeFence:
            return [StyleSpan(e.range, .codeLine(fence: true)), StyleSpan(lineWithBreak(e.range, text), .blockBackground)]
        case .codeLine:
            return [StyleSpan(e.range, .codeLine(fence: false)), StyleSpan(lineWithBreak(e.range, text), .blockBackground)]
        case .frontmatter:
            return [StyleSpan(e.range, .frontmatter), StyleSpan(lineWithBreak(e.range, text), .blockBackground)]
        case .bold:
            return [StyleSpan(e.content, .bold)] + hideOrDim(e, revealed)
        case .italic:
            return [StyleSpan(e.content, .italic)] + hideOrDim(e, revealed)
        case .boldItalic:
            return [StyleSpan(e.content, .bold), StyleSpan(e.content, .italic)] + hideOrDim(e, revealed)
        case .strikethrough:
            return [StyleSpan(e.content, .strikethrough)] + hideOrDim(e, revealed)
        case .inlineCode:
            return [StyleSpan(e.content, .inlineCode)] + hideOrDim(e, revealed)
        case .shortcode:
            return [StyleSpan(e.range, .shortcode)]
        case .tableRow(let row):
            return [StyleSpan(e.range, .tableRow(row, hidden: e.hidden, revealed: revealed))]
        case .tableDelimiter(let row):
            return [StyleSpan(e.range, .tableDelimiter(row, revealed: revealed))]
        case .link(let link):
            let linkSpans = self.linkSpans(e, link, revealed)
            if link.style == .embed, allowEmbeds, !link.target.isEmpty, isAloneOnLine(e.range, text),
               let url = resolveLink(link), LinkResolver.isMarkdownFile(url), LinkSafety.isRenderable(url) {
                return [StyleSpan(e.range, .embed(url: url, heading: link.heading, revealed: revealed,
                                                  fallback: linkSpans))]
            }
            return linkSpans
        case .image(let img):
            let dimmed = [StyleSpan(e.range, revealed ? .syntax : .secondary)]
            guard !img.isRemote, let url = resolveImage(img) else { return dimmed }
            if img.standalone {
                return [StyleSpan(e.range, .blockImage(url: url, width: img.width, height: img.height,
                                                       revealed: revealed, fallback: dimmed))]
            }
            guard !revealed, e.range.length > 1 else { return dimmed }
            return [StyleSpan(e.range, .inlineImage(url: url, width: img.width, height: img.height, fallback: dimmed))]
        }
    }

    private func linkSpans(_ e: MDElement, _ link: MDLink, _ revealed: Bool) -> [StyleSpan] {
        let look: LinkLook
        if isHugo, link.isWikiStyle {
            look = .hugoWikiWarning
        } else if isExternal(link) || LinkContext.fileTarget(of: link).isEmpty || resolveLink(link) != nil {
            look = .resolved
        } else {
            look = .unresolved
        }
        return [StyleSpan(e.content, .link(look))] + hideOrDim(e, revealed)
    }

    func isAloneOnLine(_ r: NSRange, _ text: NSString) -> Bool {
        let line = text.lineRange(for: r)
        let before = text.substring(with: NSRange(location: line.location, length: r.location - line.location))
        let after = text.substring(with: NSRange(location: NSMaxRange(r), length: NSMaxRange(line) - NSMaxRange(r)))
        return before.trimmingCharacters(in: .whitespaces).isEmpty
            && after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Source mode: everything visible, light coloring

    private func sourceSpans(_ e: MDElement) -> [StyleSpan] {
        let dimHidden = e.hidden.map { StyleSpan($0, .syntax) }
        switch e.kind {
        case .heading:
            return [StyleSpan(e.range, .sourceHeading)] + dimHidden
        case .codeFence, .codeLine, .frontmatter, .shortcode:
            return [StyleSpan(e.range, .secondary)]
        case .link:
            return [StyleSpan(e.content, .link(.resolved))] + dimHidden
        case .bulletItem, .orderedItem:
            return [StyleSpan(e.marker, .secondary)]
        case .task:
            return [StyleSpan(e.marker, .secondary)] + e.hidden.map { StyleSpan($0, .secondary) }
        case .rule, .image, .tableDelimiter:
            return [StyleSpan(e.range, .syntax)]
        case .tableRow(let row):
            return row.pipes.map { StyleSpan($0, .syntax) } + dimHidden
        default:
            return dimHidden
        }
    }
}
