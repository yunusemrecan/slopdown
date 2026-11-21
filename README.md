# Slopdown

A small, native macOS markdown editor with Obsidian-style live preview.

> **Vibe-coded.** Slopdown is written by an AI (Claude) at the direction of its owner,
> who reviews and uses it but did not type the code. Expect rough edges.

Think *CotEditor, but for markdown*: one window per file, no vault, no sidebar, no plugins.
The page is rendered while you type, and markdown syntax appears only for the element under
the caret.

## Features (0.1)

- **Live preview** in a native `NSTextView` (TextKit 1). Syntax is hidden with null glyphs,
  so the file on disk is never touched by rendering.
  - Headings, **bold**, *italic*, ***both***, ~~strike~~, `inline code`
  - Bullet, numbered and task lists (click the checkbox to toggle it)
  - Block quotes, horizontal rules, fenced code blocks, YAML frontmatter
- **Obsidian links**: `[[Note]]`, `[[Note|alias]]`, `[[Note#Heading]]`, `![[Note]]`,
  plus `[text](path.md)` and bare URLs.
  - **⌘-click** follows a link and opens it in a new window.
  - Targets are looked up relative to the note's folder: first as a path, then by name
    in its subfolders. Parent folders need an explicit `../` path.
  - If the target doesn't exist, Slopdown offers to **create the file** (next to the
    note) or to **choose a file** (and rewrites the link to point to it).
- **Images**: `![[picture.png]]`, `![[picture.png|300]]`, `![alt|300x200](path.png)`.
  On their own line they render as a block; inside a sentence they render inline.
  Remote (http) images are never loaded.
- **Tables**: pipe tables with `:--`, `:-:`, `--:` alignment render as a grid; the raw
  markdown comes back while the caret is in the table. Tables wider than the text
  column stay raw.
- **Embeds**: `![[Note]]` and `![[Note#Heading]]` on their own line show that note (or
  section) in a box; ⌘-click the box to open the note.
- **Toolbar & Format menu**: heading level, bold (⌘B), italic (⌘I), strikethrough (⇧⌘X),
  code (⌥⌘C), link (⌘K), wiki link (⇧⌘K), embed (⇧⌘E), headings (⌘0–⌘3), bulleted /
  numbered / task lists and quotes. Each command toggles: using it again removes it.
- **Status bar**: file path (click to show in Finder), line and column, word / character /
  line counts, and counts for the selection.
- **Source mode** (View → Source Mode, ⌘E): plain monospaced markdown.
- macOS autosave, versions, rename / move, and reloading files changed on disk.

## Build

Requires macOS 14+ and Xcode (or the Swift toolchain).

```sh
scripts/build_app.sh            # → dist/Slopdown.app
open dist/Slopdown.app Samples/Welcome.md
```

`swift test` runs the parser / link-resolution tests (these also run on Linux).

CI also runs a visual self-test: `SLOPDOWN_AUTOTEST="/abs/note.md" SLOPDOWN_AUTOTEST_OUT=dir`
makes the app render each note at several scroll positions into PNG files and quit
(they are uploaded as the `screenshots` artifact).

Every push to `main` builds a **nightly** release on GitHub. The app is not signed:
right-click → Open the first time, or `xattr -dr com.apple.quarantine Slopdown.app`.

## Layout

| Path | What |
|---|---|
| `Sources/SlopdownCore` | Markdown / Obsidian parser and link resolver (Foundation only) |
| `Sources/Slopdown` | AppKit app: document, window, styling, drawing |
| `Tests/SlopdownCoreTests` | Parser and resolver tests |
| `Samples/` | Notes to try every feature |

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
