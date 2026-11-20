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
    var baseDirectory: URL?
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
        let range = NSIntersectionRange(requested, NSRange(location: 0, length: storage.length))
        guard range.length > 0 else { return }

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

        case .link(let link):
            let color = isResolved(link) ? Theme.linkColor : Theme.unresolvedLinkColor
            set(storage, [.foregroundColor: color,
                          .underlineStyle: NSUnderlineStyle.single.rawValue,
                          .underlineColor: color.withAlphaComponent(0.35)], e.content, clip: clip)
            hideOrDim(e, revealed: revealed, storage, clip: clip)

        case .image(let img):
            guard img.standalone, !img.isRemote, let base = baseDirectory,
                  let url = img.isWiki ? resolutions.resolve(img.source, base: base)
                                       : resolveMarkdownImage(img.source, base: base),
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
        case .link:
            set(storage, [.foregroundColor: Theme.linkColor], e.content, clip: clip)
            for h in e.hidden { set(storage, [.foregroundColor: Theme.syntaxColor], h, clip: clip) }
        case .bulletItem, .orderedItem:
            set(storage, [.foregroundColor: Theme.secondaryColor], e.marker, clip: clip)
        case .task:
            set(storage, [.foregroundColor: Theme.secondaryColor], e.marker, clip: clip)
            for h in e.hidden { set(storage, [.foregroundColor: Theme.secondaryColor], h, clip: clip) }
        case .rule, .image:
            set(storage, [.foregroundColor: Theme.syntaxColor], e.range, clip: clip)
        default:
            for h in e.hidden { set(storage, [.foregroundColor: Theme.syntaxColor], h, clip: clip) }
        }
    }

    // MARK: - Links

    func isResolved(_ link: MDLink) -> Bool {
        if link.style == .bareURL || LinkResolver.isExternal(link.target) { return true }
        let target = Self.fileTarget(of: link)
        if target.isEmpty { return true } // same-note heading
        guard let base = baseDirectory else { return false }
        return resolutions.resolve(target, base: base) != nil
    }

    func resolveMarkdownImage(_ source: String, base: URL) -> URL? {
        resolutions.resolve(source, base: base)
    }

    /// Path part of a link (markdown links may carry a "#fragment").
    static func fileTarget(of link: MDLink) -> String {
        guard link.style == .markdown, let hash = link.target.firstIndex(of: "#") else { return link.target }
        return String(link.target[..<hash])
    }

    static func heading(of link: MDLink) -> String? {
        if link.style == .markdown, let hash = link.target.firstIndex(of: "#") {
            let h = String(link.target[link.target.index(after: hash)...])
            return h.isEmpty ? nil : h
        }
        return link.heading
    }
}
#endif
