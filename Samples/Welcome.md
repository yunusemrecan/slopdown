---
title: Welcome to Slopdown
tags: [demo]
---
# Welcome to Slopdown

Move the caret around: markdown syntax only shows up for the element you are on. **Bold**, *italic*, ***both***, ~~strikethrough~~ and `inline code` all render in place.

## Links

- Wiki link to a note in a subfolder: [[Second Note]]
- With an alias: [[Second Note|the second note]]
- To a heading: [[Second Note#Details]]
- Markdown link: [the second note](notes/Second%20Note.md)
- Missing note (⌘-click to create or choose one): [[Not Written Yet]]
- Web: https://github.com

⌘-click a link to open it in a new window.

## Tasks

- [ ] Click the box to tick it
- [x] Already done

## Quote and rule

> Form governs meaning.

---

## Images

![[inkwell.png|320]]

Inline images sit in the text: ![[inkwell.png|48]] like this, ![dot|24](attachments/inkwell.png) or this.

## Table

| Drug | Dose | Route |
|:--|:-:|--:|
| **Paracetamol** | 15 mg/kg | PO |
| Mannitol | 0.5–1 g/kg | IV |
| `code` and [[Second Note\|links]] | — | — |

## Embeds

A whole note:

![[Second Note]]

One section of it:

![[Second Note#Details]]

## Code

```swift
let answer = 42 // **not bold** in here
```

1. Ordered lists keep their numbers
2. Second item
