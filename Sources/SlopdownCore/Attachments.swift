// SPDX-License-Identifier: GPL-3.0-or-later
//
// Where pasted or dropped images go, what they are called, and whether a dropped file
// is copied or linked where it is.

import Foundation

public enum Attachments {

    /// Folder for new images:
    /// - Hugo page bundle (`index.md` / `_index.md`): next to the page
    /// - other Hugo pages: `static/images`
    /// - plain notes: next to the note
    public static func folder(for document: URL, site: HugoSite?) -> URL {
        let dir = document.deletingLastPathComponent()
        guard let site else { return dir }
        let name = document.deletingPathExtension().lastPathComponent
        if name == "index" || name == "_index" { return dir }
        return (site.staticDirs.first ?? site.root.appendingPathComponent("static")).appendingPathComponent("images")
    }

    /// A dropped file already inside the note's folder (or, in Hugo, the page bundle,
    /// static/ or assets/) is linked where it is; anything else is copied in.
    public static func shouldCopy(_ file: URL, document: URL, site: HugoSite?) -> Bool {
        let f = file.standardizedFileURL
        if let site {
            let name = document.deletingPathExtension().lastPathComponent
            var places = site.staticDirs + [site.assetsDir]
            if name == "index" || name == "_index" { places.append(document.deletingLastPathComponent()) }
            return !places.contains { LinkSafety.isInside(f, $0) }
        }
        return !LinkSafety.isInside(f, document.deletingLastPathComponent())
    }

    /// `pasted-image-2026-11-21-144512.png`
    public static func pastedImageName(date: Date = Date(), ext: String = "png") -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "pasted-image-\(f.string(from: date)).\(ext)"
    }

    /// `name.png`, or `name-2.png`, `name-3.png` … if taken.
    public static func uniqueURL(for name: String, in folder: URL, fileManager fm: FileManager = .default) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
