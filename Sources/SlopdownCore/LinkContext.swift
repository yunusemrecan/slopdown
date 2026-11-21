// SPDX-License-Identifier: GPL-3.0-or-later
//
// Everything that depends on where a note lives: plain folder (Obsidian-style) or a
// Hugo site. The editor asks this one place to resolve, create and write links.

import Foundation

public struct LinkContext {
    public var document: URL?
    public var site: HugoSite?
    /// Effective conventions (the project's, or the user's override).
    public var conventions: HugoConventions?

    public init(document: URL? = nil, site: HugoSite? = nil, conventions: HugoConventions? = nil) {
        self.document = document
        self.site = site
        self.conventions = conventions ?? site?.detected
    }

    public var baseDirectory: URL? { document?.deletingLastPathComponent() }

    /// Path part of a link (markdown and Hugo links may carry a "#fragment").
    public static func fileTarget(of link: MDLink) -> String {
        guard link.style == .markdown, let hash = link.target.firstIndex(of: "#") else { return link.target }
        return String(link.target[..<hash])
    }

    public static func heading(of link: MDLink) -> String? {
        if link.style == .markdown, let hash = link.target.firstIndex(of: "#") {
            let h = String(link.target[link.target.index(after: hash)...])
            return h.isEmpty ? nil : h
        }
        return link.heading
    }

    public func isExternal(_ link: MDLink) -> Bool {
        link.style == .bareURL || LinkResolver.isExternal(Self.fileTarget(of: link))
    }

    // MARK: - Resolving

    public func resolve(_ link: MDLink, fileManager fm: FileManager = .default) -> URL? {
        guard let doc = document, let base = baseDirectory, !isExternal(link) else { return nil }
        let target = Self.fileTarget(of: link)
        guard !target.isEmpty else { return nil }
        if let site {
            switch link.style {
            case .hugoRef:
                return site.resolvePage(target, from: doc, fileManager: fm)
            case .markdown:
                return site.resolvePage(target, from: doc, fileManager: fm)
                    ?? site.resolveResource(target, from: doc, fileManager: fm)
            case .wiki, .embed:
                return LinkResolver.resolve(target: target, relativeTo: base, fileManager: fm)
                    ?? LinkResolver.resolve(target: target, relativeTo: site.contentDir, fileManager: fm)
            case .bareURL:
                return nil
            }
        }
        return LinkResolver.resolve(target: target, relativeTo: base, fileManager: fm)
    }

    public func resolveImage(_ img: MDImage, fileManager fm: FileManager = .default) -> URL? {
        guard let doc = document, let base = baseDirectory, !img.isRemote else { return nil }
        if let site, !img.isWiki { return site.resolveResource(img.source, from: doc, fileManager: fm) }
        return LinkResolver.resolve(target: img.source, relativeTo: base, fileManager: fm)
    }

    // MARK: - Creating a missing target

    public func newFileURL(for link: MDLink) -> URL? {
        guard let doc = document, let base = baseDirectory else { return nil }
        let target = Self.fileTarget(of: link)
        if let site, link.style == .markdown || link.style == .hugoRef {
            return site.newPageURL(for: target, from: doc)
        }
        return LinkResolver.newFileURL(for: target, relativeTo: base)
    }

    /// Initial text of a new file: front matter in a Hugo site, empty otherwise.
    public func newFileContents(for url: URL) -> String {
        guard site != nil, url.pathExtension.lowercased() == "md" else { return "" }
        return HugoSite.frontMatter(for: url, toml: conventions?.tomlFrontMatter ?? true)
    }

    // MARK: - Writing links

    /// New text for `link.targetRange` so the link points at `file` (fragment kept).
    public func retarget(_ link: MDLink, to file: URL) -> String? {
        guard let doc = document, let base = baseDirectory else { return nil }
        let fragment = Self.heading(of: link).map { "#" + $0 } ?? ""
        switch link.style {
        case .wiki, .embed:
            return LinkResolver.linkTarget(for: file, relativeTo: base, wikiStyle: true)
        case .hugoRef:
            guard let site, let c = conventions else { return nil }
            return site.refArgument(for: file, conventions: c) + fragment
        case .markdown:
            if let site, let c = conventions {
                var plain = c
                if plain.style == .relref || plain.style == .ref {
                    // A plain markdown link can't hold a shortcode; use page paths.
                    plain.style = site.hasLinkRenderHook ? .logicalPath : .relativeFile
                }
                return site.destination(for: file, from: doc, conventions: plain) + fragment
            }
            return LinkResolver.linkTarget(for: file, relativeTo: base, wikiStyle: false) + fragment
        case .bareURL:
            return nil
        }
    }

    /// A complete new link to a page, in the site's convention (wiki link outside Hugo).
    public func pageLink(text: String, to file: URL) -> String? {
        guard let doc = document, let base = baseDirectory else { return nil }
        if let site, let c = conventions {
            return "[\(text)](\(site.destination(for: file, from: doc, conventions: c)))"
        }
        let target = LinkResolver.linkTarget(for: file, relativeTo: base, wikiStyle: true)
        let name = NSString(string: target).lastPathComponent
        return text.isEmpty || text == name ? "[[\(target)]]" : "[[\(target)|\(text)]]"
    }

    /// A complete image reference in the site's convention.
    public func imageLink(to file: URL) -> String? {
        guard let doc = document, let base = baseDirectory else { return nil }
        if let site { return "![](\(site.imageDestination(for: file, from: doc)))" }
        return "![[\(LinkResolver.linkTarget(for: file, relativeTo: base, wikiStyle: false).removingPercentEncoding ?? file.lastPathComponent)]]"
    }

    /// Empty link skeleton for ⌘K: `[text]()` or `[text]({{% relref "" %}})`.
    /// Returns the text and where the caret goes (offset inside it).
    public func emptyLink(text: String) -> (String, caret: Int) {
        if let site, let c = conventions, c.style == .relref || c.style == .ref {
            let sc = site.shortcode(c.style, "", c)
            let s = "[\(text)](\(sc))"
            let quotes = (s as NSString).range(of: "\"\"")
            return (s, quotes.location + 1)
        }
        let s = "[\(text)]()"
        return (s, text.isEmpty ? 1 : (s as NSString).length - 1)
    }
}
