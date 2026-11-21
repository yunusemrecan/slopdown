// SPDX-License-Identifier: GPL-3.0-or-later
//
// Side pane showing the page as the Hugo site renders it (its own theme), served by
// `hugo server`. The note is saved shortly after each edit; Hugo rebuilds and its live
// reload refreshes the pane. The pane follows the editor's scroll position.

#if canImport(AppKit)
import AppKit
import WebKit

final class PreviewPane: NSView, WKNavigationDelegate {
    let webView: WKWebView
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private var scrollFraction: CGFloat = 0
    private(set) var loadedURL: URL?
    /// Called when a page finished loading (used by the self-test).
    var onLoad: (() -> Void)?

    override init(frame: NSRect) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
        super.init(frame: frame)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        addSubview(webView)

        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)
        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
    }

    func showMessage(_ text: String) {
        messageLabel.stringValue = text
        messageLabel.isHidden = false
        webView.isHidden = true
    }

    func show(_ url: URL) {
        messageLabel.isHidden = true
        webView.isHidden = false
        if loadedURL == url, webView.url != nil { return }
        loadedURL = url
        webView.load(URLRequest(url: url))
    }

    /// Scroll the page to the same relative position as the editor (0…1).
    func scroll(toFraction f: CGFloat) {
        scrollFraction = max(0, min(1, f))
        let js = "window.scrollTo(0, \(scrollFraction) * Math.max(0, document.documentElement.scrollHeight - window.innerHeight));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        scroll(toFraction: scrollFraction)   // also after live reloads
        onLoad?()
    }

    /// The pane only ever shows the local hugo server. A page (or a script in it) can't
    /// take the pane anywhere else; a link the user clicks to another site opens in the
    /// browser, and only for http(s).
    static func isLocalServer(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "http" else { return false }
        return url.host == "localhost" || url.host == "127.0.0.1"
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        // Frames inside the page (e.g. embedded videos) stay inside the page.
        if let frame = action.targetFrame, !frame.isMainFrame {
            decisionHandler(.allow)
            return
        }
        if Self.isLocalServer(url) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if action.navigationType == .linkActivated, let url,
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showMessage("Couldn’t load the preview.\n\(error.localizedDescription)")
    }
}
#endif
