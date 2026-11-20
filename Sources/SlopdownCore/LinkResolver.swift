// SPDX-License-Identifier: GPL-3.0-or-later
//
// Turns link targets into files. There is no vault: everything is relative to the
// folder of the document that contains the link. A target is looked up first as a
// path relative to that folder, then by name anywhere below it (subfolders).

import Foundation

public enum LinkResolver {

    /// Max number of filesystem entries visited when searching subfolders, so a note
    /// that lives in ~ does not trigger a scan of the whole home folder.
    public static var searchLimit = 20_000

    public static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt"]

    /// `https://…`, `mailto:…`, `obsidian://…` — anything with a URL scheme
    /// (but not a Windows-style drive letter).
    public static func isExternal(_ target: String) -> Bool {
        if target.hasPrefix("//") { return true }
        guard let colon = target.firstIndex(of: ":") else { return false }
        let scheme = target[..<colon]
        guard scheme.count >= 2, let first = scheme.first, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-" }
    }

    /// Candidate relative paths for a target: notes may be written without ".md".
    static func candidates(for target: String) -> [String] {
        let ext = NSString(string: target).pathExtension
        if ext.isEmpty { return [target + ".md", target] }
        return [target, target + ".md"]
    }

    public static func resolve(target rawTarget: String, relativeTo baseDirectory: URL,
                               fileManager fm: FileManager = .default) -> URL? {
        let target = rawTarget.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !isExternal(target) else { return nil }

        func isFile(_ url: URL) -> Bool {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
        }

        // Absolute path
        if target.hasPrefix("/") {
            for c in candidates(for: target) {
                let url = URL(fileURLWithPath: c).standardizedFileURL
                if isFile(url) { return url }
            }
            return nil
        }

        // 1. Relative to the document's folder
        for c in candidates(for: target) {
            let url = baseDirectory.appendingPathComponent(c).standardizedFileURL
            if isFile(url) { return url }
        }

        // 2. By name (or trailing path) anywhere below the document's folder
        if target.hasPrefix("../") || target.hasPrefix("./") { return nil }
        let wanted = candidates(for: target).map { $0.lowercased() }
        let base = baseDirectory.standardizedFileURL
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard let en = fm.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        var best: (url: URL, depth: Int)? = nil
        var visited = 0
        while let any = en.nextObject() {
            visited += 1
            if visited > searchLimit { break }
            guard let url = any as? URL else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(basePath) else { continue }
            let rel = String(path.dropFirst(basePath.count)).lowercased()
            for w in wanted where rel == w || rel.hasSuffix("/" + w) {
                guard isFile(url) else { continue }
                let depth = rel.split(separator: "/").count
                if best == nil || depth < best!.depth { best = (url.standardizedFileURL, depth) }
            }
        }
        return best?.url
    }

    /// Where "Create new file" puts a missing link target: in the linking document's
    /// folder (keeping any subfolder written in the link), with ".md" added when the
    /// target has no extension.
    public static func newFileURL(for rawTarget: String, relativeTo baseDirectory: URL) -> URL {
        let target = rawTarget.trimmingCharacters(in: .whitespaces)
        let name = NSString(string: target).pathExtension.isEmpty ? target + ".md" : target
        if name.hasPrefix("/") { return URL(fileURLWithPath: name).standardizedFileURL }
        return baseDirectory.appendingPathComponent(name).standardizedFileURL
    }

    /// Relative path from a folder to a file, using "../" where needed.
    public static func relativePath(from directory: URL, to file: URL) -> String {
        let a = directory.standardizedFileURL.pathComponents
        let b = file.standardizedFileURL.pathComponents
        var common = 0
        while common < a.count, common < b.count - 1, a[common] == b[common] { common += 1 }
        let ups = Array(repeating: "..", count: a.count - common)
        return (ups + b[common...]).joined(separator: "/")
    }

    /// Text to write into a link that should point to `file`.
    /// Wiki links drop the ".md" extension, markdown links are percent-encoded.
    public static func linkTarget(for file: URL, relativeTo baseDirectory: URL, wikiStyle: Bool) -> String {
        let rel = relativePath(from: baseDirectory, to: file)
        if wikiStyle {
            let ns = NSString(string: rel)
            return ns.pathExtension.lowercased() == "md" ? ns.deletingPathExtension : rel
        }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return rel.addingPercentEncoding(withAllowedCharacters: allowed) ?? rel
    }

    public static func isMarkdownFile(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }
}
