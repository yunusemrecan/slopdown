# Slopdown

A small, native macOS markdown editor with Obsidian-style live preview.

> [!WARNING]
> **Vibe-coded.** This app was written by an AI (Claude), not by a human programmer.
> Its owner directs and reviews it but did not write the code. Use at your own risk
> and keep backups of your notes. The same notice in other languages is below; the app
> shows it in your language in **Slopdown → About Slopdown**.

<details>
<summary>🌐 Vibe-coded notice in other languages</summary>

| | |
|---|---|
| **English** | This app is vibe-coded: it was written by an AI (Claude), not by a human programmer. Its owner directs and reviews it but did not write the code. Use it at your own risk and keep backups of your notes. |
| **Türkçe** | Bu uygulama vibe-coded'dur: kodunu bir insan programcı değil, bir yapay zekâ (Claude) yazdı. Sahibi yönlendiriyor ve gözden geçiriyor ama kodu kendisi yazmadı. Kullanım sorumluluğu size aittir; notlarınızın yedeğini alın. |
| **Deutsch** | Diese App ist „vibe-coded“: Sie wurde von einer KI (Claude) geschrieben, nicht von einem menschlichen Programmierer. Der Inhaber steuert und prüft sie, hat den Code aber nicht selbst geschrieben. Nutzung auf eigene Gefahr – sichern Sie Ihre Notizen. |
| **Français** | Cette application est « vibe-codée » : elle a été écrite par une IA (Claude), et non par un programmeur humain. Son propriétaire la dirige et la relit, mais n’a pas écrit le code. Utilisation à vos risques ; sauvegardez vos notes. |
| **Español** | Esta aplicación está hecha con «vibe coding»: la escribió una IA (Claude), no un programador humano. Su propietario la dirige y la revisa, pero no escribió el código. Úsala bajo tu propia responsabilidad y haz copias de seguridad de tus notas. |
| **Italiano** | Questa app è «vibe-coded»: è stata scritta da un’IA (Claude), non da un programmatore umano. Il proprietario la dirige e la revisiona, ma non ha scritto il codice. Usala a tuo rischio e fai un backup delle tue note. |
| **Português** | Este app foi feito com “vibe coding”: foi escrito por uma IA (Claude), não por um programador humano. O dono o orienta e revisa, mas não escreveu o código. Use por sua conta e risco e faça backup das suas notas. |
| **Русский** | Это приложение создано в стиле «вайб-кодинга»: код написал ИИ (Claude), а не программист-человек. Владелец направляет и проверяет работу, но сам код не писал. Используйте на свой риск и делайте резервные копии заметок. |
| **العربية** | هذا التطبيق مبرمج بأسلوب «البرمجة بالإحساس» (vibe coding): كتبه ذكاء اصطناعي (Claude) وليس مبرمجًا بشريًا. يوجّهه مالكه ويراجعه، لكنه لم يكتب الشيفرة بنفسه. استخدمه على مسؤوليتك واحتفظ بنسخ احتياطية من ملاحظاتك. |
| **日本語** | このアプリは「バイブコーディング」で作られています。コードを書いたのは人間のプログラマーではなく AI（Claude）です。所有者は方向性を決めてレビューしていますが、コード自体は書いていません。自己責任でご使用のうえ、ノートのバックアップを取ってください。 |
| **中文** | 本应用是“氛围编程”（vibe coding）的产物：代码由 AI（Claude）编写，而非人类程序员。所有者负责指导和审阅，但没有亲自编写代码。使用风险自负，请备份你的笔记。 |
| **한국어** | 이 앱은 '바이브 코딩'으로 만들어졌습니다. 코드는 사람 프로그래머가 아니라 AI(Claude)가 작성했습니다. 소유자가 방향을 정하고 검토하지만 코드를 직접 작성하지는 않았습니다. 사용에 따른 책임은 본인에게 있으며, 노트는 꼭 백업하세요. |

</details>

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
