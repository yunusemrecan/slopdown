// SPDX-License-Identifier: GPL-3.0-or-later

#if canImport(AppKit)
import AppKit

extension NSAttributedString.Key {
    /// Character is laid out as a null glyph (syntax hidden in live preview).
    static let sdHidden = NSAttributedString.Key("sd.hidden")
    /// List bullet drawn as a dot (value: true).
    static let sdBullet = NSAttributedString.Key("sd.bullet")
    /// Task checkbox drawn over `[ ]` (value: NSNumber checked).
    static let sdTask = NSAttributedString.Key("sd.task")
    /// Horizontal rule drawn across the line (value: true).
    static let sdRule = NSAttributedString.Key("sd.rule")
    /// Image drawn below the line (value: RenderedImage).
    static let sdImage = NSAttributedString.Key("sd.image")
    /// Quote bar drawn left of the line (value: true).
    static let sdQuote = NSAttributedString.Key("sd.quote")
    /// Code block / frontmatter background (value: true).
    static let sdCodeBlock = NSAttributedString.Key("sd.codeBlock")
    /// A table `|` laid out as a tab (value: true).
    static let sdTabPipe = NSAttributedString.Key("sd.tabPipe")
    /// Table row decoration: grid lines, header background (value: TableRowDecoration).
    static let sdTable = NSAttributedString.Key("sd.table")
    /// First character of an inline image; laid out as a box of the image's size
    /// (value: RenderedImage). The rest of the image syntax is hidden.
    static let sdInlineImage = NSAttributedString.Key("sd.inlineImage")
    /// Embedded note drawn below the line (value: RenderedEmbed).
    static let sdEmbed = NSAttributedString.Key("sd.embed")
}

enum Theme {
    static let bodySize: CGFloat = 15
    static let monoSize: CGFloat = 13.5
    /// Max width of a text line, Obsidian-style "readable line length".
    static let readableWidth: CGFloat = 720

    static var bodyFont: NSFont { .systemFont(ofSize: bodySize) }
    static var monoFont: NSFont { .monospacedSystemFont(ofSize: monoSize, weight: .regular) }

    static func headingFont(level: Int) -> NSFont {
        let scale: [CGFloat] = [1.75, 1.5, 1.3, 1.15, 1.05, 1.0]
        let s = scale[max(0, min(5, level - 1))]
        return .systemFont(ofSize: (bodySize * s).rounded(), weight: level <= 2 ? .bold : .semibold)
    }

    static var paragraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 4
        return p
    }

    static func baseAttributes(sourceMode: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: sourceMode ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular) : bodyFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraph,
        ]
    }

    static var syntaxColor: NSColor { .tertiaryLabelColor }
    static var secondaryColor: NSColor { .secondaryLabelColor }
    static var linkColor: NSColor { .linkColor }
    static var unresolvedLinkColor: NSColor { NSColor.linkColor.withAlphaComponent(0.55) }
    static var inlineCodeBackground: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.35) }
    static var codeBlockBackground: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.25) }
    static var quoteBar: NSColor { .tertiaryLabelColor }
}
#endif
