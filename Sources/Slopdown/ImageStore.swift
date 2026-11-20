// SPDX-License-Identifier: GPL-3.0-or-later

#if canImport(AppKit)
import AppKit
import ImageIO
import SlopdownCore

/// A decoded image ready to draw, plus its size in the text.
final class RenderedImage: NSObject {
    let image: NSImage
    let size: NSSize
    init(image: NSImage, size: NSSize) {
        self.image = image
        self.size = size
    }

    // Equal when it would draw the same thing (lets the styler skip unchanged runs).
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RenderedImage else { return false }
        return other.image === image && other.size == size
    }

    override var hash: Int { ObjectIdentifier(image).hashValue }
}

/// Loads local images once (downsampled, EXIF orientation applied) and caches them.
/// Remote images are never loaded.
final class ImageStore {
    static let shared = ImageStore()
    /// Tallest an image is drawn (also bounds how far above the dirty rect we look).
    static let maxHeight: CGFloat = 1000

    private struct Entry {
        let image: NSImage
        let naturalSize: NSSize   // in points, 1 image pixel = 1 point (like a browser)
        let modified: Date?
    }

    private var cache: [URL: Entry] = [:]

    func image(at url: URL) -> (image: NSImage, naturalSize: NSSize)? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let e = cache[url], e.modified == modified { return (e.image, e.naturalSize) }
        guard let loaded = load(url) else {
            cache[url] = nil
            return nil
        }
        cache[url] = Entry(image: loaded.0, naturalSize: loaded.1, modified: modified)
        return loaded
    }

    private func load(_ url: URL) -> (NSImage, NSSize)? {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           CGImageSourceGetCount(src) > 0 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) {
                var natural = NSSize(width: cg.width, height: cg.height)
                if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                   let w = props[kCGImagePropertyPixelWidth] as? Int,
                   let h = props[kCGImagePropertyPixelHeight] as? Int {
                    let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
                    natural = orientation >= 5 ? NSSize(width: h, height: w) : NSSize(width: w, height: h)
                }
                return (NSImage(cgImage: cg, size: natural), natural)
            }
        }
        // SVG and anything ImageIO cannot decode
        if let img = NSImage(contentsOf: url), img.size.width > 0, img.size.height > 0 {
            return (img, img.size)
        }
        return nil
    }

    /// Size of an image in the text: explicit size from the markdown, otherwise the
    /// natural size; never wider than the text column.
    static func displaySize(natural: NSSize, width: Double?, height: Double?, maxWidth: CGFloat) -> NSSize {
        let aspect = natural.width > 0 ? natural.height / natural.width : 1
        var w: CGFloat
        var h: CGFloat
        switch (width, height) {
        case let (w0?, h0?): w = CGFloat(w0); h = CGFloat(h0)
        case let (w0?, nil): w = CGFloat(w0); h = w * aspect
        default: w = natural.width; h = natural.height
        }
        if w > maxWidth, w > 0 {
            h = h * maxWidth / w
            w = maxWidth
        }
        if h > maxHeight, h > 0 {
            w = w * maxHeight / h
            h = maxHeight
        }
        return NSSize(width: max(1, w.rounded()), height: max(1, h.rounded()))
    }
}

/// Link target → file lookups are cached, because styling runs on every keystroke.
/// Hits are kept while the file exists; misses are retried after a few seconds.
final class ResolutionCache {
    private var hits: [String: URL] = [:]
    private var misses: [String: Date] = [:]

    func resolve(_ target: String, base: URL) -> URL? {
        let key = base.path + "\u{0}" + target
        if let u = hits[key] {
            if FileManager.default.fileExists(atPath: u.path) { return u }
            hits[key] = nil
        }
        if let t = misses[key], Date().timeIntervalSince(t) < 4 { return nil }
        if let u = LinkResolver.resolve(target: target, relativeTo: base) {
            hits[key] = u
            misses[key] = nil
            return u
        }
        misses[key] = Date()
        return nil
    }

    func invalidate() {
        hits.removeAll()
        misses.removeAll()
    }
}
#endif
