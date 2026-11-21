// SPDX-License-Identifier: GPL-3.0-or-later
//
// Link completion: where the caret is (inside `[[…`, a Hugo `ref "…`, or `](…` in a Hugo
// site), which pages exist, and what text to insert for each, in the note's link
// convention.

import Foundation

public enum CompletionKind: Equatable {
    /// `[[partial` (wiki link) or `![[partial` (embed: images too).
    case wiki(embed: Bool)
    /// `{{< relref "partial` in a Hugo site.
    case hugoRef
    /// `[text](partial` in a Hugo site.
    case markdownLink
}

public struct CompletionContext: Equatable {
    public var kind: CompletionKind
    /// The text typed so far, to be replaced by the chosen item.
    public var partial: NSRange
}

public struct CompletionItem: Equatable {
    public var title: String      // shown in bold: page title or file name
    public var detail: String     // shown dimmed: path
    public var insert: String     // replaces the partial text
    public var url: URL
}

/// A page (or image) that links can point to.
public struct PageEntry: Equatable {
    public var url: URL
    public var title: String?

    public init(url: URL, title: String?) {
        self.url = url
        self.title = title
    }
}

public enum Completion {

    private static let refRE = try! NSRegularExpression(pattern: #"\{\{[<%]\s*(?:rel)?ref\s+"([^"\n]*)$"#)
    private static let mdLinkRE = try! NSRegularExpression(pattern: #"\]\(([^)\s]*)$"#)

    /// The completion context at `caret`, if any. Only the current line is looked at.
    public static func context(in text: NSString, caret: Int, hugo: Bool) -> CompletionContext? {
        guard caret >= 0, caret <= text.length else { return nil }
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        let before = NSRange(location: line.location, length: caret - line.location)
        let s = text.substring(with: before)

        // [[partial — no closing brackets, alias or heading separator typed yet
        let open = (s as NSString).range(of: "[[", options: .backwards)
        if open.location != NSNotFound {
            let typed = (s as NSString).substring(from: NSMaxRange(open))
            if !typed.contains("]"), !typed.contains("|"), !typed.contains("#"), !typed.contains("[") {
                let embed = open.location > 0 && (s as NSString).character(at: open.location - 1) == 0x21 // !
                return CompletionContext(kind: .wiki(embed: embed),
                                         partial: NSRange(location: before.location + NSMaxRange(open),
                                                          length: (typed as NSString).length))
            }
        }
        guard hugo else { return nil }
        let all = NSRange(location: 0, length: (s as NSString).length)
        if let m = refRE.firstMatch(in: s, range: all) {
            let g = m.range(at: 1)
            return CompletionContext(kind: .hugoRef, partial: NSRange(location: before.location + g.location, length: g.length))
        }
        if let m = mdLinkRE.firstMatch(in: s, range: all) {
            let g = m.range(at: 1)
            let typed = (s as NSString).substring(with: g)
            // Not for web addresses or anchors
            if LinkResolver.isExternal(typed) || typed.hasPrefix("#") || typed.hasPrefix("{") { return nil }
            return CompletionContext(kind: .markdownLink, partial: NSRange(location: before.location + g.location, length: g.length))
        }
        return nil
    }

    // MARK: - Index

    /// Markdown pages (and images, for embeds) below `root`. Titles come from front matter.
    public static func index(root: URL, includeImages: Bool, readTitles: Bool, limit: Int = 5000,
                             fileManager fm: FileManager = .default) -> [PageEntry] {
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [PageEntry] = []
        while let url = en.nextObject() as? URL, out.count < limit {
            let ext = url.pathExtension.lowercased()
            let isPage = LinkResolver.markdownExtensions.contains(ext) && ext != "txt"
            let isImage = includeImages && MarkdownParser.imageExtensions.contains(ext)
            guard isPage || isImage else { continue }
            var title: String? = nil
            if readTitles, isPage, let h = FileHandle(forReadingAtPath: url.path) {
                let head = h.readData(ofLength: 2048)
                try? h.close()
                title = HugoSite.title(ofPageText: String(decoding: head, as: UTF8.self))
            }
            out.append(PageEntry(url: url.standardizedFileURL, title: title))
        }
        return out
    }

    // MARK: - Candidates

    public static func items(for kind: CompletionKind, typed: String, pages: [PageEntry],
                             context: LinkContext, limit: Int = 40) -> [CompletionItem] {
        guard let doc = context.document, let base = context.baseDirectory else { return [] }
        let site = context.site
        let root = site?.contentDir ?? base

        // Wiki links use the shortest unique name, like Obsidian.
        var nameCount: [String: Int] = [:]
        if case .wiki = kind {
            for p in pages { nameCount[wikiName(p.url).lowercased(), default: 0] += 1 }
        }

        let query = typed.lowercased()
        var scored: [(score: Int, item: CompletionItem)] = []
        for p in pages where p.url != doc.standardizedFileURL {
            let isImage = MarkdownParser.imageExtensions.contains(p.url.pathExtension.lowercased())
            let insert: String
            switch kind {
            case .wiki:
                let name = wikiName(p.url)
                insert = nameCount[name.lowercased(), default: 0] > 1
                    ? LinkResolver.linkTarget(for: p.url, relativeTo: base, wikiStyle: true).removingPercentEncoding ?? name
                    : name
            case .hugoRef:
                guard let site, let c = context.conventions, !isImage else { continue }
                insert = site.refArgument(for: p.url, conventions: c)
            case .markdownLink:
                guard let site, var c = context.conventions, !isImage else { continue }
                if c.style == .relref || c.style == .ref { c.style = site.hasLinkRenderHook ? .logicalPath : .relativeFile }
                insert = site.destination(for: p.url, from: doc, conventions: c)
            }
            let name = p.url.deletingPathExtension().lastPathComponent
            let title = p.title ?? (isImage ? p.url.lastPathComponent : name)
            let path = relative(p.url, to: root)
            guard let score = match(query, [title.lowercased(), name.lowercased(), path.lowercased()]) else { continue }
            scored.append((score, CompletionItem(title: title, detail: path, insert: insert, url: p.url)))
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score < $1.score : $0.item.detail.count < $1.item.detail.count }
            .prefix(limit).map { $0.item }
    }

    /// Lower is better: 0 prefix, 1 word prefix, 2 substring, 3 in-order letters; nil: no match.
    static func match(_ q: String, _ fields: [String]) -> Int? {
        if q.isEmpty { return 0 }
        var best: Int? = nil
        for f in fields {
            let s: Int?
            if f.hasPrefix(q) { s = 0 }
            else if f.split(whereSeparator: { " -_/".contains($0) }).contains(where: { $0.hasPrefix(q) }) { s = 1 }
            else if f.contains(q) { s = 2 }
            else if isSubsequence(q, of: f) { s = 3 }
            else { s = nil }
            if let s { best = min(best ?? s, s) }
        }
        return best
    }

    static func isSubsequence(_ q: String, of s: String) -> Bool {
        var it = s.makeIterator()
        for c in q {
            var found = false
            while let x = it.next() { if x == c { found = true; break } }
            if !found { return false }
        }
        return true
    }

    /// File name as a wiki link writes it: no `.md`, other extensions kept.
    static func wikiName(_ url: URL) -> String {
        url.pathExtension.lowercased() == "md" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
    }

    static func relative(_ url: URL, to root: URL) -> String {
        let p = url.standardizedFileURL.path, r = root.standardizedFileURL.path + "/"
        return p.hasPrefix(r) ? String(p.dropFirst(r.count)) : url.lastPathComponent
    }

    /// Text to add after the inserted item so the link is closed (`]]`, `"`, `)`),
    /// unless it is already there.
    public static func closing(for kind: CompletionKind, after rest: String) -> String {
        switch kind {
        case .wiki: return rest.hasPrefix("]]") ? "" : "]]"
        case .hugoRef: return rest.hasPrefix("\"") ? "" : "\""
        case .markdownLink: return rest.hasPrefix(")") ? "" : ")"
        }
    }
}
