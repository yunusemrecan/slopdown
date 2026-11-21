// SPDX-License-Identifier: GPL-3.0-or-later
//
// Keeping the Hugo preview at the same place as the editor: headings are matched by
// their visible text (Hugo's HTML headings carry the same words), and the position
// between two headings by the same fraction.

import Foundation

public struct HeadingInfo: Equatable {
    public var range: NSRange      // the heading line
    public var title: String       // normalized visible text (for matching)
    public var text: String        // visible text as shown
    public var level: Int
    /// Which heading with this title it is (0 = first), and how many there are.
    public var occurrence: Int
    public var count: Int
}

public enum HeadingSync {
    /// Headings of a note in order, with their visible text.
    public static func headings(_ elements: [MDElement], in text: NSString) -> [HeadingInfo] {
        var result: [HeadingInfo] = []
        var hiddenInline: [NSRange] = []
        for e in elements where !e.isBlock { hiddenInline.append(contentsOf: e.hidden) }
        hiddenInline.sort { $0.location < $1.location }

        for e in elements {
            guard case .heading(let level) = e.kind else { continue }
            var chars: [unichar] = []
            let c = e.content
            var k = c.location
            var h = hiddenInline.firstIndex { NSMaxRange($0) > c.location } ?? hiddenInline.count
            while k < NSMaxRange(c) {
                while h < hiddenInline.count, NSMaxRange(hiddenInline[h]) <= k { h += 1 }
                if h < hiddenInline.count, hiddenInline[h].containsIndex(k) {
                    k = NSMaxRange(hiddenInline[h])
                    continue
                }
                chars.append(text.character(at: k))
                k += 1
            }
            var title = String(utf16CodeUnits: chars, count: chars.count)
            // Closing hashes ("## Title ##") are not part of the title.
            title = title.replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
            let shown = title.trimmingCharacters(in: .whitespaces)
            title = normalize(title)
            result.append(HeadingInfo(range: e.range, title: title, text: shown, level: level, occurrence: 0, count: 0))
        }
        var counts: [String: Int] = [:]
        for i in result.indices {
            result[i].occurrence = counts[result[i].title, default: 0]
            counts[result[i].title, default: 0] += 1
        }
        for i in result.indices { result[i].count = counts[result[i].title] ?? 1 }
        return result
    }

    /// Whitespace collapsed, trimmed, lowercased — what the preview script compares.
    public static func normalize(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    /// The script the preview pane installs. `__slopdownSync(title, occurrence, count,
    /// fraction, before)` scrolls to `fraction` of the way from that heading to the next;
    /// with `before`, to `fraction` of the way from the page top to that heading.
    /// Themes often repeat the page title as a heading; extra matches are assumed to
    /// come before the content.
    public static let script = """
    window.__slopdownSync = function(title, occurrence, count, fraction, before) {
      const norm = s => s.replace(/\\s+/g, ' ').trim().toLowerCase();
      const all = Array.from(document.querySelectorAll('h1,h2,h3,h4,h5,h6'));
      const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
      const matches = all.filter(h => norm(h.textContent) === title);
      if (!matches.length) { window.scrollTo(0, fraction * max); return false; }
      const k = Math.min(matches.length - 1, occurrence + Math.max(0, matches.length - count));
      const h = matches[k];
      const top = h.getBoundingClientRect().top + window.scrollY;
      if (before) { window.scrollTo(0, Math.min(max, fraction * top)); return true; }
      const i = all.indexOf(h);
      const next = i + 1 < all.length ? all[i + 1].getBoundingClientRect().top + window.scrollY
                                      : document.documentElement.scrollHeight;
      window.scrollTo(0, Math.min(max, Math.max(0, top + fraction * (next - top) - 8)));
      return true;
    };
    """
}
