// SPDX-License-Identifier: GPL-3.0-or-later
//
// Hugo awareness: find the site a note belongs to, learn which link convention the
// project already uses, resolve Hugo link destinations to files, and write new links
// in that convention.

import Foundation

public enum HugoLinkStyle: String, CaseIterable, Equatable {
    /// `[t](/posts/foo)` — logical page paths, resolved by Hugo's link render hook.
    case logicalPath
    /// `[t](../foo.md)` — file paths relative to the note.
    case relativeFile
    /// `[t]({{% relref "/posts/foo" %}})`
    case relref
    /// `[t]({{% ref "/posts/foo" %}})`
    case ref

    public var title: String {
        switch self {
        case .logicalPath: return "Page paths  /posts/foo"
        case .relativeFile: return "Relative files  ../foo.md"
        case .relref: return "relref shortcode"
        case .ref: return "ref shortcode"
        }
    }

    public var shortName: String {
        switch self {
        case .logicalPath: return "page paths"
        case .relativeFile: return "relative .md"
        case .relref: return "relref"
        case .ref: return "ref"
        }
    }
}

public struct HugoConventions: Equatable {
    public var style: HugoLinkStyle
    /// `%` or `<` for ref/relref shortcodes.
    public var shortcodeDelimiter: Character
    /// ref/relref arguments written as files ("/posts/foo.md") instead of logical paths.
    public var refUsesFiles: Bool
    /// Front matter format for new pages.
    public var tomlFrontMatter: Bool

    public init(style: HugoLinkStyle, shortcodeDelimiter: Character = "%", refUsesFiles: Bool = false,
                tomlFrontMatter: Bool = true) {
        self.style = style
        self.shortcodeDelimiter = shortcodeDelimiter
        self.refUsesFiles = refUsesFiles
        self.tomlFrontMatter = tomlFrontMatter
    }
}

public struct HugoSite: Equatable {
    public var root: URL
    public var contentDir: URL
    public var staticDirs: [URL]
    public var assetsDir: URL
    /// The link render hook is on (config or a custom render-link template).
    public var hasLinkRenderHook: Bool
    /// `baseURL` from the config (used to turn permalinks into server paths).
    public var baseURL: String? = nil
    /// Language codes from `[languages.xx]`; empty or one entry: a single-language site.
    public var languages: [String] = []
    public var defaultLanguage = "en"
    /// Languages with their own content folder (`contentDir` inside `[languages.xx]`).
    public var languageContentDirs: [String: URL] = [:]

    public var isMultilingual: Bool { languages.count > 1 }

    /// Every content folder: the main one and per-language ones.
    public var contentDirs: [URL] {
        var dirs = [contentDir]
        for code in languages { if let d = languageContentDirs[code], !dirs.contains(d) { dirs.append(d) } }
        return dirs
    }

    /// The content folder a file lives in (the most specific one).
    public func contentRoot(for file: URL) -> URL {
        contentDirs.filter { LinkSafety.isInside(file, $0) }.max { $0.path.count < $1.path.count } ?? contentDir
    }

    /// `post.tr.md` → "tr"; a file in a language's content folder → that language.
    public func language(of file: URL) -> String {
        if let suffix = languageSuffix(file.deletingPathExtension().lastPathComponent) { return suffix }
        let root = contentRoot(for: file)
        return languageContentDirs.first { $0.value == root }?.key ?? defaultLanguage
    }

    /// The language code at the end of a file name stem ("post.tr"), if it is one of the site's.
    func languageSuffix(_ stem: String) -> String? {
        guard isMultilingual else { return nil }
        let ext = (stem as NSString).pathExtension
        return languages.contains(ext) ? ext : nil
    }

    func stripLanguage(_ stem: String) -> String {
        languageSuffix(stem) != nil ? (stem as NSString).deletingPathExtension : stem
    }
    /// What the project itself does (from its content files).
    public var detected: HugoConventions

    // MARK: - Detection

    static let configNames = ["hugo.toml", "hugo.yaml", "hugo.yml", "hugo.json",
                              "config.toml", "config.yaml", "config.yml", "config.json"]

    /// The Hugo site containing `file`, if any (walks up the folder tree).
    public static func containing(_ file: URL, fileManager fm: FileManager = .default) -> HugoSite? {
        var dir = file.deletingLastPathComponent().standardizedFileURL
        for _ in 0..<12 {
            if let site = at(dir, fileManager: fm) {
                // The note must be inside the content folder to count as a site page.
                return site.contentDirs.contains { LinkSafety.isInside(file, $0) && file.standardizedFileURL != $0 }
                    ? site : nil
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    /// A Hugo site rooted exactly at `dir`.
    public static func at(_ dir: URL, fileManager fm: FileManager = .default) -> HugoSite? {
        var configText: String?
        for name in configNames {
            let url = dir.appendingPathComponent(name)
            if let data = fm.contents(atPath: url.path) { configText = String(decoding: data, as: UTF8.self); break }
        }
        if configText == nil {
            for name in configNames {
                let url = dir.appendingPathComponent("config/_default").appendingPathComponent(name)
                if let data = fm.contents(atPath: url.path) { configText = String(decoding: data, as: UTF8.self); break }
            }
        }
        guard let config = configText else { return nil }
        // Zola also uses config.toml; it spells the base URL "base_url" (Hugo: "baseURL").
        if config.range(of: #"(?m)^\s*base_url\s*="#, options: .regularExpression) != nil { return nil }

        func setting(_ key: String) -> String? {
            let pattern = #"(?mi)^\s*"# + key + #"\s*[=:]\s*["']?([^"'\n#]+?)["']?\s*$"#
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: config, range: NSRange(location: 0, length: (config as NSString).length))
            else { return nil }
            return (config as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        }
        let content = dir.appendingPathComponent(setting("contentDir") ?? "content")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: content.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        let staticDir = dir.appendingPathComponent(setting("staticDir") ?? "static")
        let assets = dir.appendingPathComponent(setting("assetDir") ?? "assets")

        let hookInConfig = config.range(of: #"(?is)renderHooks.{0,120}?link.{0,160}?(enableDefault\s*[=:]\s*true|useEmbedded\s*[=:]\s*["']?(always|fallback))"#,
                                        options: .regularExpression) != nil
        let hookTemplate = ["layouts/_markup/render-link.html", "layouts/_default/_markup/render-link.html"]
            .contains { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }

        var site = HugoSite(root: dir.standardizedFileURL, contentDir: content.standardizedFileURL,
                            staticDirs: [staticDir.standardizedFileURL], assetsDir: assets.standardizedFileURL,
                            hasLinkRenderHook: hookInConfig || hookTemplate,
                            detected: HugoConventions(style: .relref))
        site.baseURL = setting("baseURL")
        let langs = parseLanguages(config, root: dir.standardizedFileURL)
        site.languages = langs.codes
        site.languageContentDirs = langs.dirs
        site.defaultLanguage = setting("defaultContentLanguage") ?? langs.codes.first ?? "en"
        site.detected = site.detectConventions(fileManager: fm)
        return site
    }

    /// Languages and their content folders, from TOML `[languages.xx]` tables or a YAML
    /// `languages:` map.
    static func parseLanguages(_ config: String, root: URL) -> (codes: [String], dirs: [String: URL]) {
        var codes: [String] = []
        var dirs: [String: URL] = [:]
        let lines = config.components(separatedBy: .newlines)
        let tomlHeader = try! NSRegularExpression(pattern: #"^\s*\[\s*languages\.([A-Za-z0-9_-]+)\s*\]\s*$"#)
        let anyHeader = try! NSRegularExpression(pattern: #"^\s*\["#)
        let dirLine = try! NSRegularExpression(pattern: #"^\s*contentDir\s*[=:]\s*["']?([^"'\n#]+?)["']?\s*$"#)
        func first(_ re: NSRegularExpression, _ l: String) -> String? {
            guard let m = re.firstMatch(in: l, range: NSRange(location: 0, length: (l as NSString).length)) else { return nil }
            return m.numberOfRanges > 1 ? (l as NSString).substring(with: m.range(at: 1)) : ""
        }
        // TOML
        var current: String? = nil
        for l in lines {
            if let code = first(tomlHeader, l) {
                current = code
                if !codes.contains(code) { codes.append(code) }
            } else if first(anyHeader, l) != nil {
                current = nil
            } else if let code = current, let d = first(dirLine, l) {
                dirs[code] = root.appendingPathComponent(d).standardizedFileURL
            }
        }
        if !codes.isEmpty { return (codes, dirs) }
        // YAML
        var inLanguages = false
        var keyIndent: Int? = nil
        current = nil
        for l in lines {
            let indent = l.prefix(while: { $0 == " " }).count
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            if indent == 0 {
                inLanguages = t == "languages:"
                keyIndent = nil
                continue
            }
            guard inLanguages else { continue }
            if keyIndent == nil { keyIndent = indent }
            if indent == keyIndent, t.hasSuffix(":") {
                let code = String(t.dropLast())
                current = code
                if !codes.contains(code) { codes.append(code) }
            } else if indent > (keyIndent ?? 0), let code = current, let d = first(dirLine, l) {
                dirs[code] = root.appendingPathComponent(d).standardizedFileURL
            }
        }
        return (codes, dirs)
    }

    // MARK: - Conventions used by the project

    private static let relrefRE = try! NSRegularExpression(pattern: #"\]\(\s*\{\{([<%])\s*(rel)?ref\s+"([^"\n]*)""#)
    private static let relativeMdRE = try! NSRegularExpression(pattern: #"(?<!!)\]\((?![a-zA-Z][a-zA-Z0-9+.-]*:|#|/|\{)([^)\s]+\.md)(#[^)\s]*)?\)"#)
    private static let logicalRE = try! NSRegularExpression(pattern: #"(?<!!)\]\((/[^)\s.]*(?:#[^)\s]*)?)\)"#)

    func detectConventions(fileManager fm: FileManager) -> HugoConventions {
        var counts: [HugoLinkStyle: Int] = [:]
        var percent = 0, angle = 0, refFiles = 0, refLogical = 0
        var toml = 0, yaml = 0

        if let archetype = fm.contents(atPath: root.appendingPathComponent("archetypes/default.md").path) {
            let s = String(decoding: archetype, as: UTF8.self)
            if s.hasPrefix("+++") { toml += 100 } else if s.hasPrefix("---") { yaml += 100 }
        }

        var files = 0
        if let en = fm.enumerator(at: contentDir, includingPropertiesForKeys: nil,
                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            while let url = en.nextObject() as? URL, files < 400 {
                guard url.pathExtension.lowercased() == "md", let data = fm.contents(atPath: url.path) else { continue }
                files += 1
                let text = String(decoding: data.prefix(200_000), as: UTF8.self)
                if text.hasPrefix("+++") { toml += 1 } else if text.hasPrefix("---") { yaml += 1 }
                let ns = text as NSString
                let all = NSRange(location: 0, length: ns.length)
                for m in Self.relrefRE.matches(in: text, range: all) {
                    counts[m.range(at: 2).location == NSNotFound ? .ref : .relref, default: 0] += 1
                    if ns.substring(with: m.range(at: 1)) == "%" { percent += 1 } else { angle += 1 }
                    if ns.substring(with: m.range(at: 3)).lowercased().hasSuffix(".md") { refFiles += 1 } else { refLogical += 1 }
                }
                counts[.relativeFile, default: 0] += Self.relativeMdRE.numberOfMatches(in: text, range: all)
                counts[.logicalPath, default: 0] += Self.logicalRE.numberOfMatches(in: text, range: all)
            }
        }

        let fallback: HugoLinkStyle = hasLinkRenderHook ? .logicalPath : .relref
        let best = counts.max { a, b in a.value != b.value ? a.value < b.value : a.key != fallback }
        let style = (best?.value ?? 0) > 0 ? best!.key : fallback
        return HugoConventions(style: style, shortcodeDelimiter: angle > percent ? "<" : "%",
                               refUsesFiles: refFiles > refLogical, tomlFrontMatter: toml >= yaml)
    }

    // MARK: - Paths

    /// `content/posts/foo.md` → `/posts/foo`; bundles (`foo/index.md`, `_index.md`) → their folder.
    public func logicalPath(of file: URL) -> String {
        var rel = relative(file.standardizedFileURL, to: contentRoot(for: file))
        rel = (rel as NSString).deletingPathExtension
        // Translations by file name share the path: post.tr.md → /post
        let dir = (rel as NSString).deletingLastPathComponent
        let stem = stripLanguage((rel as NSString).lastPathComponent)
        rel = dir.isEmpty ? stem : dir + "/" + stem
        let last = (rel as NSString).lastPathComponent
        if last == "index" || last == "_index" { rel = (rel as NSString).deletingLastPathComponent }
        return "/" + rel
    }

    func relative(_ file: URL, to dir: URL) -> String {
        let p = file.path, d = dir.path.hasSuffix("/") ? dir.path : dir.path + "/"
        return p.hasPrefix(d) ? String(p.dropFirst(d.count)) : p
    }

    // MARK: - Resolving

    /// A page link destination (logical path, file path, ref argument, permalink) → file.
    public func resolvePage(_ rawTarget: String, from document: URL, fileManager fm: FileManager = .default) -> URL? {
        var t = rawTarget.trimmingCharacters(in: .whitespaces)
        if let hash = t.firstIndex(of: "#") { t = String(t[..<hash]) }
        if let q = t.firstIndex(of: "?") { t = String(t[..<q]) }
        guard !t.isEmpty, !LinkResolver.isExternal(t) else { return nil }
        while t.count > 1 && t.hasSuffix("/") { t.removeLast() }

        func isFile(_ u: URL) -> Bool {
            var d: ObjCBool = false
            return fm.fileExists(atPath: u.path, isDirectory: &d) && !d.boolValue
        }
        // In a multilingual site, the page in the note's own language comes first.
        let lang: String? = isMultilingual ? language(of: document) : nil
        func candidates(_ p: String) -> [String] {
            if (p as NSString).pathExtension.lowercased() == "md" { return [p] }
            var c: [String] = []
            if let lang { c += [p + ".\(lang).md", p + "/index.\(lang).md", p + "/_index.\(lang).md"] }
            return c + [p + ".md", p + "/index.md", p + "/_index.md", p]
        }
        let docDir = document.deletingLastPathComponent()
        let root = contentRoot(for: document)
        let bases: [URL]
        var path = t
        if t.hasPrefix("/") {
            path = String(t.dropFirst())
            bases = [root] + contentDirs.filter { $0 != root }
        } else {
            bases = [docDir, docDir.deletingLastPathComponent(), root]
        }
        if path.isEmpty {
            let home = ((lang.map { ["_index.\($0).md"] } ?? []) + ["_index.md"]).map { root.appendingPathComponent($0) }
            return home.first(where: isFile)
        }
        for base in bases {
            for c in candidates(path) {
                let u = base.appendingPathComponent(c).standardizedFileURL
                if isFile(u) { return u }
            }
        }
        // By name anywhere in the content folder
        for c in candidates(path) {
            if let u = LinkResolver.resolve(target: c, relativeTo: root, fileManager: fm) { return u }
        }
        return nil
    }

    /// An image / resource destination → file: page bundle first, then static and assets.
    public func resolveResource(_ rawTarget: String, from document: URL, fileManager fm: FileManager = .default) -> URL? {
        let t = rawTarget.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !LinkResolver.isExternal(t) else { return nil }
        if t.hasPrefix("/") {
            let rel = String(t.dropFirst())
            for dir in staticDirs + [assetsDir, contentDir] {
                let u = dir.appendingPathComponent(rel).standardizedFileURL
                if fm.fileExists(atPath: u.path) { return u }
            }
            return nil
        }
        return LinkResolver.resolve(target: t, relativeTo: document.deletingLastPathComponent(), fileManager: fm)
    }

    // MARK: - Writing links

    /// Destination text for a link from `document` to the page `file`.
    public func destination(for file: URL, from document: URL, conventions c: HugoConventions) -> String {
        switch c.style {
        case .logicalPath:
            return encode(logicalPath(of: file))
        case .relativeFile:
            return encode(LinkResolver.relativePath(from: document.deletingLastPathComponent(), to: file))
        case .relref, .ref:
            let arg = c.refUsesFiles ? "/" + relative(file.standardizedFileURL, to: contentRoot(for: file)) : logicalPath(of: file)
            return shortcode(c.style, arg, c)
        }
    }

    /// Argument of a ref/relref shortcode for `file` (used when rewriting an existing one).
    public func refArgument(for file: URL, conventions c: HugoConventions) -> String {
        c.refUsesFiles ? "/" + relative(file.standardizedFileURL, to: contentRoot(for: file)) : logicalPath(of: file)
    }

    public func shortcode(_ style: HugoLinkStyle, _ arg: String, _ c: HugoConventions) -> String {
        let name = style == .ref ? "ref" : "relref"
        let (open, close) = c.shortcodeDelimiter == "<" ? ("{{<", ">}}") : ("{{%", "%}}")
        return "\(open) \(name) \"\(arg)\" \(close)"
    }

    /// Destination for an image: relative inside the page's folder, site-absolute in
    /// static/ or assets/.
    public func imageDestination(for file: URL, from document: URL) -> String {
        let f = file.standardizedFileURL
        for dir in staticDirs + [assetsDir] where f.path.hasPrefix(dir.path + "/") {
            return encode("/" + relative(f, to: dir))
        }
        return encode(LinkResolver.relativePath(from: document.deletingLastPathComponent(), to: f))
    }

    private func encode(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    // MARK: - Page URLs from `hugo list all`

    /// Minimal RFC 4180 CSV parser (quoted fields, doubled quotes, newlines in quotes).
    public static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(text)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == "," {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" {
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else if c != "\r" {
                field.append(c)
            }
            i += 1
        }
        return rows
    }

    /// Output of `hugo list all` → [absolute file path: path below the site's base URL],
    /// e.g. "/…/content/posts/first.md" → "posts/first/".
    public func pagePaths(fromListOutput text: String) -> [String: String] {
        let rows = Self.parseCSV(text)
        guard let header = rows.first,
              let pathCol = header.firstIndex(of: "path"),
              let linkCol = header.firstIndex(of: "permalink") else { return [:] }
        let basePath = baseURL.flatMap { URL(string: $0)?.path } ?? "/"
        var result: [String: String] = [:]
        for row in rows.dropFirst() where row.count > max(pathCol, linkCol) {
            let file = root.appendingPathComponent(row[pathCol]).standardizedFileURL.path
            let link = row[linkCol]
            var path: String
            if let base = baseURL, link.hasPrefix(base) {
                path = String(link.dropFirst(base.count))
            } else {
                path = URL(string: link)?.path ?? link
                if path.hasPrefix(basePath) { path = String(path.dropFirst(basePath.count)) }
                if link.hasSuffix("/") && !path.hasSuffix("/") { path += "/" }
            }
            result[file] = String(path.drop(while: { $0 == "/" }))
        }
        return result
    }

    // MARK: - New pages

    /// Where a missing page link would be created.
    public func newPageURL(for rawTarget: String, from document: URL) -> URL {
        var t = rawTarget.trimmingCharacters(in: .whitespaces)
        if let hash = t.firstIndex(of: "#") { t = String(t[..<hash]) }
        while t.count > 1 && t.hasSuffix("/") { t.removeLast() }
        // A translation by file name (post.tr.md) links to pages in the same language.
        let suffix = languageSuffix(document.deletingPathExtension().lastPathComponent).map { ".\($0)" } ?? ""
        let name = (t as NSString).pathExtension.lowercased() == "md" ? t : t + suffix + ".md"
        if name.hasPrefix("/") { return contentRoot(for: document).appendingPathComponent(String(name.dropFirst())).standardizedFileURL }
        return document.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
    }

    /// Front matter for a new page: title from the file name, now as date, draft.
    public static func frontMatter(for file: URL, toml: Bool, date: Date = Date()) -> String {
        var base = file.deletingPathExtension().lastPathComponent
        if base == "index" || base == "_index" { base = file.deletingLastPathComponent().lastPathComponent }
        let title = base.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            .split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        let d = f.string(from: date)
        if toml {
            return "+++\ntitle = '\(title.replacingOccurrences(of: "'", with: "’"))'\ndate = \(d)\ndraft = true\n+++\n\n"
        }
        return "---\ntitle: \"\(title.replacingOccurrences(of: "\"", with: "\\\""))\"\ndate: \(d)\ndraft: true\n---\n\n"
    }

    /// Page title from front matter (TOML or YAML), if any.
    public static func title(ofPageText text: String) -> String? {
        let re = try! NSRegularExpression(pattern: #"(?m)^title\s*[=:]\s*["']?(.*?)["']?\s*$"#)
        let ns = text as NSString
        let head = ns.substring(to: min(ns.length, 4000))
        guard head.hasPrefix("+++") || head.hasPrefix("---"),
              let m = re.firstMatch(in: head, range: NSRange(location: 0, length: (head as NSString).length))
        else { return nil }
        let t = (head as NSString).substring(with: m.range(at: 1))
        return t.isEmpty ? nil : t
    }
}
