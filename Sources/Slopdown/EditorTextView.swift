// SPDX-License-Identifier: GPL-3.0-or-later

#if canImport(AppKit)
import AppKit

/// Lays out characters marked `.sdHidden` as null glyphs: they stay in the text (and in
/// the file) but take no space and are not drawn.
final class GlyphConcealer: NSObject, NSLayoutManagerDelegate {
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>,
                       font aFont: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        let count = glyphRange.length
        let length = storage.length
        var modified: [NSLayoutManager.GlyphProperty]? = nil
        var hiddenUntil = -1      // end of the last hidden run found
        var visibleUntil = -1     // end of the last visible run found
        for i in 0..<count {
            let ci = charIndexes[i]
            guard ci < length else { continue }
            var hidden: Bool
            if ci < hiddenUntil {
                hidden = true
            } else if ci < visibleUntil {
                hidden = false
            } else {
                var run = NSRange()
                hidden = storage.attribute(.sdHidden, at: ci, effectiveRange: &run) != nil
                if hidden { hiddenUntil = NSMaxRange(run) } else { visibleUntil = NSMaxRange(run) }
            }
            if hidden {
                if modified == nil { modified = Array(UnsafeBufferPointer(start: props, count: count)) }
                modified![i] = .null
            }
        }
        guard let newProps = modified else { return 0 }
        newProps.withUnsafeBufferPointer { buf in
            layoutManager.setGlyphs(glyphs, properties: buf.baseAddress!, characterIndexes: charIndexes,
                                    font: aFont, forGlyphRange: glyphRange)
        }
        return count
    }
}

final class EditorTextView: NSTextView {
    weak var editor: EditorWindowController?

    // MARK: - Width / insets

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.width
        super.setFrameSize(newSize)
        if newSize.width != oldWidth { updateTextWidth() }
    }

    /// Centers a column of readable width; the text container is sized by hand.
    func updateTextWidth() {
        let width = bounds.width
        let side = floor(max(28, (width - Theme.readableWidth) / 2))
        let inset = NSSize(width: side, height: 30)
        if textContainerInset != inset { textContainerInset = inset }
        let containerWidth = max(120, width - 2 * side)
        if let tc = textContainer, tc.size.width != containerWidth {
            tc.size = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
            editor?.textWidthDidChange()
        }
    }

    // MARK: - Hit testing

    /// Character under a point (only when the point is actually on that glyph).
    func characterIndex(onGlyphAt point: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer, let ts = textStorage, ts.length > 0 else { return nil }
        let origin = textContainerOrigin
        let p = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        var fraction: CGFloat = 0
        let g = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: &fraction)
        guard g < lm.numberOfGlyphs else { return nil }
        let rect = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc)
        guard rect.insetBy(dx: -1, dy: 0).contains(p) else { return nil }
        let ci = lm.characterIndexForGlyph(at: g)
        return ci < ts.length ? ci : nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let editor {
            if event.modifierFlags.contains(.command), let link = editor.linkElement(at: p) {
                editor.follow(link)
                return
            }
            if event.clickCount == 1,
               event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
               let task = editor.taskElement(at: p) {
                editor.toggleTask(task)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateCursor(at: convert(event.locationInWindow, from: nil), flags: event.modifierFlags)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard let window else { return }
        updateCursor(at: convert(window.mouseLocationOutsideOfEventStream, from: nil), flags: event.modifierFlags)
    }

    private func updateCursor(at p: NSPoint, flags: NSEvent.ModifierFlags) {
        guard let editor, bounds.contains(p) else { return }
        if editor.taskElement(at: p) != nil
            || (flags.contains(.command) && editor.linkElement(at: p) != nil) {
            NSCursor.pointingHand.set()
        } else if flags.contains(.command) {
            NSCursor.iBeam.set()
        }
    }

    // MARK: - Drawing

    private func visibleCharacterRange(in rect: NSRect) -> NSRange? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let origin = textContainerOrigin
        let r = rect.offsetBy(dx: -origin.x, dy: -origin.y)
        let gr = lm.glyphRange(forBoundingRect: r, in: tc)
        guard gr.length > 0 else { return nil }
        return lm.characterRange(forGlyphRange: gr, actualGlyphRange: nil)
    }

    private func lineRects(for charRange: NSRange) -> [NSRect] {
        guard let lm = layoutManager else { return [] }
        let gr = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        var rects: [NSRect] = []
        lm.enumerateLineFragments(forGlyphRange: gr) { rect, _, _, _, _ in rects.append(rect) }
        let origin = textContainerOrigin
        return rects.map { $0.offsetBy(dx: origin.x, dy: origin.y) }
    }

    /// Vertical center of lowercase letters on the line of a character.
    private func xHeightCenter(forCharacterAt ci: Int) -> CGFloat? {
        guard let lm = layoutManager, let ts = textStorage else { return nil }
        let g = lm.glyphIndexForCharacter(at: ci)
        guard g < lm.numberOfGlyphs else { return nil }
        let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
        let baseline = lm.location(forGlyphAt: g).y
        let font = (ts.attribute(.font, at: ci, effectiveRange: nil) as? NSFont) ?? Theme.bodyFont
        return textContainerOrigin.y + frag.minY + baseline - font.xHeight / 2
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let ts = textStorage, let range = visibleCharacterRange(in: rect) else { return }

        Theme.codeBlockBackground.setFill()
        ts.enumerateAttribute(.sdCodeBlock, in: range) { value, run, _ in
            guard value != nil else { return }
            for r in lineRects(for: run) {
                NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height).fill()
            }
        }

        Theme.quoteBar.setFill()
        ts.enumerateAttribute(.sdQuote, in: range) { value, run, _ in
            guard value != nil else { return }
            for r in lineRects(for: run) {
                NSRect(x: r.minX + 4, y: r.minY, width: 3, height: r.height).fill()
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let lm = layoutManager, let tc = textContainer, let ts = textStorage,
              let range = visibleCharacterRange(in: dirtyRect) else { return }
        let origin = textContainerOrigin

        // Images below their (hidden) syntax line
        ts.enumerateAttribute(.sdImage, in: range) { value, run, _ in
            guard let img = value as? RenderedImage, run.length > 0 else { return }
            let g = lm.glyphIndexForCharacter(at: NSMaxRange(run) - 1)
            guard g < lm.numberOfGlyphs else { return }
            // The styler reserved `height + 12` of paragraph spacing at the bottom of this
            // line fragment; draw the image into that space.
            let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            let r = NSRect(x: origin.x + frag.minX + tc.lineFragmentPadding,
                           y: origin.y + frag.maxY - img.size.height - 8,
                           width: img.size.width, height: img.size.height)
            guard r.intersects(dirtyRect) else { return }
            img.image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1,
                           respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }

        // List bullets
        NSColor.labelColor.withAlphaComponent(0.75).setFill()
        ts.enumerateAttribute(.sdBullet, in: range) { value, run, _ in
            guard value != nil, let cy = xHeightCenter(forCharacterAt: run.location) else { return }
            let gr = lm.glyphRange(forCharacterRange: run, actualCharacterRange: nil)
            let box = lm.boundingRect(forGlyphRange: gr, in: tc).offsetBy(dx: origin.x, dy: origin.y)
            let d: CGFloat = 5.5
            NSBezierPath(ovalIn: NSRect(x: box.midX - d / 2, y: cy - d / 2, width: d, height: d)).fill()
        }

        // Task checkboxes
        ts.enumerateAttribute(.sdTask, in: range) { value, run, _ in
            guard let checked = (value as? NSNumber)?.boolValue,
                  let cy = xHeightCenter(forCharacterAt: run.location) else { return }
            let gr = lm.glyphRange(forCharacterRange: run, actualCharacterRange: nil)
            let box = lm.boundingRect(forGlyphRange: gr, in: tc).offsetBy(dx: origin.x, dy: origin.y)
            let s: CGFloat = 14
            let r = NSRect(x: box.minX + max(0, (box.width - s) / 2), y: cy - s / 2, width: s, height: s)
            Self.drawCheckbox(in: r, checked: checked)
        }

        // Horizontal rules
        NSColor.separatorColor.setStroke()
        ts.enumerateAttribute(.sdRule, in: range) { value, run, _ in
            guard value != nil else { return }
            for r in lineRects(for: run) {
                let path = NSBezierPath()
                let y = floor(r.midY) + 0.5
                path.move(to: NSPoint(x: r.minX + tc.lineFragmentPadding, y: y))
                path.line(to: NSPoint(x: r.maxX - tc.lineFragmentPadding, y: y))
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    static func drawCheckbox(in r: NSRect, checked: Bool) {
        let box = NSBezierPath(roundedRect: r.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.5, yRadius: 3.5)
        if checked {
            NSColor.controlAccentColor.setFill()
            box.fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: r.minX + r.width * 0.25, y: r.minY + r.height * 0.52))
            check.line(to: NSPoint(x: r.minX + r.width * 0.43, y: r.minY + r.height * 0.70))
            check.line(to: NSPoint(x: r.minX + r.width * 0.76, y: r.minY + r.height * 0.32))
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            NSColor.secondaryLabelColor.setStroke()
            box.lineWidth = 1.2
            box.stroke()
        }
    }
}
#endif
