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
                let path = file.standardizedFileURL.path
                return path.hasPrefix(site.contentDir.path + "/") ? site : nil
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
        site.detected = site.detectConventions(fileManager: fm)
        return site
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
        var rel = relative(file.standardizedFileURL, to: contentDir)
        rel = (rel as NSString).deletingPathExtension
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
        func candidates(_ p: String) -> [String] {
            if (p as NSString).pathExtension.lowercased() == "md" { return [p] }
            return [p + ".md", p + "/index.md", p + "/_index.md", p]
        }
        let docDir = document.deletingLastPathComponent()
        let bases: [URL]
        var path = t
        if t.hasPrefix("/") {
            path = String(t.dropFirst())
            bases = [contentDir]
        } else {
            bases = [docDir, docDir.deletingLastPathComponent(), contentDir]
        }
        if path.isEmpty { return isFile(contentDir.appendingPathComponent("_index.md")) ? contentDir.appendingPathComponent("_index.md") : nil }
        for base in bases {
            for c in candidates(path) {
                let u = base.appendingPathComponent(c).standardizedFileURL
                if isFile(u) { return u }
            }
        }
        // By name anywhere in the content folder
        for c in candidates(path) {
            if let u = LinkResolver.resolve(target: c, relativeTo: contentDir, fileManager: fm) { return u }
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
            let arg = c.refUsesFiles ? "/" + relative(file.standardizedFileURL, to: contentDir) : logicalPath(of: file)
            return shortcode(c.style, arg, c)
        }
    }

    /// Argument of a ref/relref shortcode for `file` (used when rewriting an existing one).
    public func refArgument(for file: URL, conventions c: HugoConventions) -> String {
        c.refUsesFiles ? "/" + relative(file.standardizedFileURL, to: contentDir) : logicalPath(of: file)
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

    // MARK: - New pages

    /// Where a missing page link would be created.
    public func newPageURL(for rawTarget: String, from document: URL) -> URL {
        var t = rawTarget.trimmingCharacters(in: .whitespaces)
        if let hash = t.firstIndex(of: "#") { t = String(t[..<hash]) }
        while t.count > 1 && t.hasSuffix("/") { t.removeLast() }
        let name = (t as NSString).pathExtension.lowercased() == "md" ? t : t + ".md"
        if name.hasPrefix("/") { return contentDir.appendingPathComponent(String(name.dropFirst())).standardizedFileURL }
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
