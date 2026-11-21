// SPDX-License-Identifier: GPL-3.0-or-later
//
// Opening things a note points at, with the LinkSafety rules: link text can hide the
// real target, so anything that could run code is confirmed or refused.

#if canImport(AppKit)
import AppKit
import SlopdownCore
import UniformTypeIdentifiers

extension EditorWindowController {

    func confirm(title: String, detail: String, button: String, alternate: (String, () -> Void)? = nil,
                 perform: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: button)
        if let alternate { alert.addButton(withTitle: alternate.0) }
        alert.addButton(withTitle: "Cancel")
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn { perform() }
            else if response == .alertSecondButtonReturn, let alternate { alternate.1() }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
    }

    /// http(s) and mailto open; other schemes (other apps' handlers, file:, ssh: …) are
    /// confirmed with the full address shown.
    func openExternal(_ string: String) {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespaces)) else { NSSound.beep(); return }
        if LinkSafety.action(forURL: url.absoluteString) == .open {
            NSWorkspace.shared.open(url)
            return
        }
        let app = NSWorkspace.shared.urlForApplication(toOpen: url).map { $0.deletingPathExtension().lastPathComponent }
        confirm(title: "Open this link\(app.map { " in \($0)" } ?? "")?",
                detail: "It is not a web link. It will be passed to another app:\n\n\(url.absoluteString)",
                button: "Open") { NSWorkspace.shared.open(url) }
    }

    /// Images, PDFs and media open; other documents are confirmed; apps, scripts,
    /// installers and folders are only shown in Finder.
    func openLocalFile(_ url: URL) {
        var action = LinkSafety.action(forFile: url)
        if action != .revealOnly,
           let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType,
           [UTType.application, .executable, .script, .shellScript, .package, .bundle,
            .unixExecutable, .applicationBundle].contains(where: { type.conforms(to: $0) }) {
            action = .revealOnly
        }
        let shown = (url.path as NSString).abbreviatingWithTildeInPath
        let reveal = { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        switch action {
        case .open:
            NSWorkspace.shared.open(url)
        case .confirm:
            let app = NSWorkspace.shared.urlForApplication(toOpen: url).map { $0.deletingPathExtension().lastPathComponent }
            confirm(title: "Open “\(url.lastPathComponent)”\(app.map { " in \($0)" } ?? "")?",
                    detail: shown, button: "Open", alternate: ("Show in Finder", reveal)) {
                NSWorkspace.shared.open(url)
            }
        case .revealOnly:
            let alert = NSAlert()
            alert.messageText = "“\(url.lastPathComponent)” was not opened"
            alert.informativeText = "Opening it could run code (an app, a script or an installer), so Slopdown only shows it in Finder.\n\n\(shown)"
            alert.addButton(withTitle: "Show in Finder")
            alert.addButton(withTitle: "Cancel")
            let handle: (NSApplication.ModalResponse) -> Void = { if $0 == .alertFirstButtonReturn { reveal() } }
            if let window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
        }
    }

    // MARK: - Trusting a Hugo site

    static func trustKey(_ site: HugoSite) -> String { "HugoTrusted:" + site.root.path }

    static func isTrusted(_ site: HugoSite) -> Bool { UserDefaults.standard.bool(forKey: trustKey(site)) }

    static func setTrusted(_ site: HugoSite) { UserDefaults.standard.set(true, forKey: trustKey(site)) }

    /// `hugo server` builds the site, and a site's build can run its own code
    /// (PostCSS/Babel config, Hugo modules, external tools it allows). Ask once per site.
    func askToTrust(_ site: HugoSite, then: @escaping () -> Void) {
        confirm(title: "Run this Hugo site’s build?",
                detail: "Preview runs “hugo server” in:\n\(( site.root.path as NSString).abbreviatingWithTildeInPath)\n\n"
                    + "Building a site can run code that comes with the site (PostCSS or Babel settings, Hugo modules, "
                    + "external tools the site allows). Continue only for sites you trust. Slopdown remembers your answer for this site.",
                button: "Run Hugo") {
            Self.setTrusted(site)
            then()
        }
    }
}
#endif
