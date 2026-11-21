// SPDX-License-Identifier: GPL-3.0-or-later
//
// Runs `hugo server` for a site (one per site, started on demand, stopped on quit)
// and opens pages in the browser.

#if canImport(AppKit)
import AppKit
import SlopdownCore

final class HugoPreview {
    static let shared = HugoPreview()

    private final class Server {
        let process: Process
        var url: URL?
        var output = ""
        var waiters: [(URL?, String) -> Void] = []
        init(process: Process) { self.process = process }
    }

    private var servers: [String: Server] = [:]

    /// URL of the running server for `site`, starting it if needed. Completion runs on
    /// the main thread with nil and the server's output when it could not start.
    func baseURL(for site: HugoSite, completion: @escaping (URL?, String) -> Void) {
        let key = site.root.path
        if let s = servers[key], s.process.isRunning {
            if let url = s.url { completion(url, s.output) } else { s.waiters.append(completion) }
            return
        }
        let p = Process()
        // A login shell finds Homebrew's hugo (GUI apps don't get the shell's PATH).
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "exec hugo server --buildDrafts --bind 127.0.0.1"]
        p.currentDirectoryURL = site.root
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let server = Server(process: p)
        server.waiters.append(completion)
        servers[key] = server

        let re = try! NSRegularExpression(pattern: #"Web Server is available at (http://\S+)"#)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                server.output += text
                guard server.url == nil else { return }
                let ns = server.output as NSString
                if let m = re.firstMatch(in: server.output, range: NSRange(location: 0, length: ns.length)),
                   let url = URL(string: ns.substring(with: m.range(at: 1))) {
                    server.url = url
                    let w = server.waiters
                    server.waiters = []
                    w.forEach { $0(url, server.output) }
                }
            }
        }
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                let w = server.waiters
                server.waiters = []
                w.forEach { $0(nil, server.output) }
            }
        }
        do {
            try p.run()
        } catch {
            servers[key] = nil
            completion(nil, error.localizedDescription)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            guard server.url == nil, !server.waiters.isEmpty else { return }
            let w = server.waiters
            server.waiters = []
            w.forEach { $0(nil, server.output + "\n(timed out waiting for hugo server)") }
        }
    }

    // MARK: - Page paths (`hugo list all`)

    private var pagePaths: [String: (paths: [String: String], time: Date)] = [:]

    /// Path of a page below the site's base URL, as Hugo publishes it (slug, url and
    /// permalinks settings included), from `hugo list all`; falls back to a guess.
    func pagePath(_ page: URL, site: HugoSite, completion: @escaping (String) -> Void) {
        let key = site.root.path
        let file = page.standardizedFileURL.path
        if let cached = pagePaths[key], let p = cached.paths[file], Date().timeIntervalSince(cached.time) < 30 {
            completion(p)
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "exec hugo list all"]
        p.currentDirectoryURL = site.root
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { completion(Self.guessedPath(page, site: site)); return }
        DispatchQueue.global(qos: .userInitiated).async {
            // Read before waiting: a large listing would otherwise fill the pipe and block.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let paths = site.pagePaths(fromListOutput: String(decoding: data, as: UTF8.self))
            DispatchQueue.main.async {
                if !paths.isEmpty { self.pagePaths[key] = (paths, Date()) }
                completion(paths[file] ?? Self.guessedPath(page, site: site))
            }
        }
    }

    static func guessedPath(_ page: URL, site: HugoSite) -> String {
        var path = site.logicalPath(of: page).lowercased().replacingOccurrences(of: " ", with: "-")
        path = String(path.drop(while: { $0 == "/" }))
        if !path.isEmpty { path += "/" }
        return path
    }

    /// Browser URL of a page on the running server (guessed path; see `pagePath`).
    static func pageURL(_ page: URL, site: HugoSite, base: URL) -> URL? {
        pageURL(path: guessedPath(page, site: site), base: base)
    }

    static func pageURL(path: String, base: URL) -> URL? {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let b = base.absoluteString.hasSuffix("/") ? base : base.appendingPathComponent("")
        return URL(string: encoded, relativeTo: b)?.absoluteURL
    }

    /// Server URL of `page`: starts the server if needed, then asks Hugo for the path.
    func url(of page: URL, in site: HugoSite, completion: @escaping (URL?, String) -> Void) {
        baseURL(for: site) { base, output in
            guard let base else { completion(nil, output); return }
            self.pagePath(page, site: site) { path in
                completion(Self.pageURL(path: path, base: base), output)
            }
        }
    }

    func preview(_ page: URL, in site: HugoSite, window: NSWindow?) {
        url(of: page, in: site) { url, output in
            guard let url else {
                Self.showFailure(output, window: window)
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    static func failureMessage(_ output: String) -> (title: String, detail: String) {
        if output.contains("command not found") || output.contains("not found: hugo") {
            return ("Hugo isn’t installed", "Install it with Homebrew:\n\nbrew install hugo")
        }
        return ("hugo server didn’t start", String(output.suffix(1200)))
    }

    static func showFailure(_ output: String, window: NSWindow?) {
        let alert = NSAlert()
        let m = failureMessage(output)
        alert.messageText = m.title
        alert.informativeText = m.detail
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    func stop(_ site: HugoSite) {
        let key = site.root.path
        if let s = servers[key], s.process.isRunning { s.process.terminate() }
        servers[key] = nil
        pagePaths[key] = nil
    }

    func stopAll() {
        for s in servers.values where s.process.isRunning { s.process.terminate() }
        servers.removeAll()
    }
}
#endif
