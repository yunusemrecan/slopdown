// SPDX-License-Identifier: GPL-3.0-or-later
//
// Safety rules for things a note can make the app do: open URLs and files, render
// files inline, create files. Notes can come from anyone, and link text can hide
// where a link really goes, so anything with side effects is either limited or
// confirmed with the full target shown.

import Foundation

public enum LinkSafety {

    public enum Action: Equatable {
        /// Safe to open directly.
        case open
        /// Show the full target and ask first.
        case confirm
        /// Never open (it could run code); only show it in Finder.
        case revealOnly
    }

    // MARK: - URLs

    static let directSchemes: Set<String> = ["http", "https", "mailto"]

    /// `http`, `https`, `mailto` open directly; any other scheme (another app's
    /// handler, `file:`, `ssh:` …) is confirmed.
    public static func action(forURL string: String) -> Action {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased() else { return .confirm }
        return directSchemes.contains(scheme) ? .open : .confirm
    }

    // MARK: - Local files

    /// Opening these could run code (apps, scripts, installers, shortcuts to commands).
    static let executableExtensions: Set<String> = [
        "app", "command", "tool", "terminal", "workflow", "action", "scpt", "scptd", "applescript",
        "pkg", "mpkg", "sh", "bash", "zsh", "csh", "ksh", "fish", "py", "rb", "pl", "php", "js",
        "jar", "osascript", "shortcut", "fileloc", "webloc", "inetloc", "dylib", "bundle", "plugin",
        "kext", "prefpane", "saver", "qlgenerator", "mobileconfig", "dmg", "iso", "exe", "bat",
    ]

    /// Documents that only display (opened in Preview, QuickTime, …).
    static let viewableExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "svg", "avif",
        "pdf", "mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "mp4", "m4v", "mov", "webm", "mkv",
    ]

    /// What ⌘-clicking a link to a local, non-markdown file may do.
    public static func action(forFile url: URL, fileManager fm: FileManager = .default) -> Action {
        let ext = url.pathExtension.lowercased()
        if executableExtensions.contains(ext) { return .revealOnly }
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return .revealOnly }
        if fm.isExecutableFile(atPath: url.path) && !viewableExtensions.contains(ext) { return .revealOnly }
        return viewableExtensions.contains(ext) ? .open : .confirm
    }

    // MARK: - Rendering

    /// Folders whose files are never rendered into a note (images, embeds), even if a
    /// link points there: hidden folders (~/.ssh, .git …), Library and system folders,
    /// other users' home folders.
    public static func isRenderable(_ url: URL, home: String = NSHomeDirectory()) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let parts = path.split(separator: "/")
        if parts.contains(where: { $0.hasPrefix(".") }) { return false }
        let homePath = URL(fileURLWithPath: home).standardizedFileURL.resolvingSymlinksInPath().path
        if path.hasPrefix(homePath + "/") {
            let inside = path.dropFirst(homePath.count + 1)
            return !inside.hasPrefix("Library/")
        }
        for blocked in ["/etc/", "/private/", "/System/", "/Library/", "/usr/", "/bin/", "/sbin/",
                        "/var/", "/dev/", "/opt/", "/cores/", "/Users/", "/home/", "/root/"] {
            if path.hasPrefix(blocked) { return false }
        }
        return true
    }

    // MARK: - Creating files

    /// True when `url` is inside `folder` (or is the folder).
    public static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let p = url.standardizedFileURL.path
        let f = folder.standardizedFileURL.path
        return p == f || p.hasPrefix(f.hasSuffix("/") ? f : f + "/")
    }

    // MARK: - Parsing limits

    /// Lines longer than this (UTF-16 units) get no inline styling: regex work on a
    /// single huge line would make every keystroke slow.
    public static let maxStyledLineLength = 10_000
}
