# Husky Notes

A native, open-source Markdown note-taking app for **iPhone, iPad and Mac**. Obsidian’s openness, Bear’s reliability, wrapped in a beautiful themeable editor. Every note is plain CommonMark — and always yours.

> Reliability over cleverness.

-----

## Status

> ⚠️ In development. This README is the engineering plan derived from the marketing site; sections marked *(planned)* aren’t built yet.

-----

## Principles

1. **Notes are plain Markdown.** CommonMark + GFM. The on-disk truth is portable `.md` — nothing proprietary.
1. **Native, not web.** Live inline rendering via TextKit 2. No web view, no preview pane to flip to, no lag.
1. **No server.** Sync runs on the user’s private iCloud (CloudKit) database. There is no Husky backend and no account.
1. **Theming is decoupled from storage.** Switching themes is pure presentation — zero risk to data.
1. **Data is never trapped.** First-class `.md` export with YAML frontmatter is a core, enforceable promise.

-----

## Platforms

|Platform|Minimum OS|
|--------|----------|
|iOS     |18        |
|iPadOS  |18        |
|macOS   |15        |

Single SwiftUI codebase across all three.

-----

## Tech stack

|Concern    |Technology                                |
|-----------|------------------------------------------|
|UI         |SwiftUI                                   |
|Text engine|TextKit 2 (live inline Markdown rendering)|
|Persistence|SwiftData (`ModelContainer`)              |
|Sync       |CloudKit private database (`.private`)    |
|Markdown   |CommonMark + GFM                          |
|Export     |`.md` files + YAML frontmatter            |

Reference sync setup:

```swift
let store = try ModelContainer(
  for: Note.self,
  configurations: ModelConfiguration(cloudKitDatabase: .private)
)
```

-----

## Architecture overview

```
SwiftUI views
   │
   ├── Editor (TextKit 2)        ← live themed rendering, clean .md underneath
   ├── Sidebar / smart lists     ← Pinned, Today, Archive, per-tag
   ├── Search                    ← full-text index over note bodies + tags
   └── Theme engine              ← presentation layer, decoupled from store
        │
SwiftData models (Note, Tag, …)
        │
CloudKit (.private) ─ silent, record-level, conflict-aware, offline-first
        │
.md mirror ─ two-way sync to real files w/ YAML frontmatter
```

-----

## Data model *(planned)*

|Model |Key fields                                                                        |Notes                                                            |
|------|----------------------------------------------------------------------------------|-----------------------------------------------------------------|
|`Note`|`id`, `title`, `body` (Markdown), `createdAt`, `updatedAt`, `isPinned`, `isLocked`|Body is the source of truth                                      |
|`Tag` |`name`                                                                            |Derived from inline `#tags` in body; smart lists built from these|

Smart lists (Pinned, Today, Untagged, per-tag) are **computed**, not stored — driven by note metadata and tag membership.

-----

## Feature checklist

- [ ] Markdown editor with live inline rendering (TextKit 2)
- [ ] CommonMark + GFM: headings, quotes, lists, code blocks, checklists, tables, footnotes
- [ ] Inline `#tags` with auto-built smart lists
- [ ] Full-text search with composable tag + text filters (`#work invoice`)
- [ ] CloudKit sync — record-level, offline-first, conflict handling
- [ ] Distraction-free focus mode
- [ ] Theme engine — Blue Husky, Husky Day, Pine, Ember
- [ ] `.md` export with YAML frontmatter
- [ ] PDF export & printing (per-note, rendered like Read mode)
- [ ] Continuous two-way `.md` mirror
- [ ] Full theme editor / custom themes
- [ ] Per-note locking (Face ID / Touch ID app lock)
- [ ] Attachments & image handling
- [ ] Advanced export

-----

## Privacy & security

- All notes live in the user’s **own** private iCloud database — encrypted in transit and at rest, scoped to their Apple ID.
- No tracking, no ads, no analytics on note content.
- Optional Face ID / Touch ID app lock.
- We never see a word the user writes.

-----

## Pricing

**Husky Notes is completely free.** No subscriptions, no one-time unlocks, no
tiers, no paywalled features. Every capability — including the two-way `.md`
mirror, full theme editor, per-note locking, attachments, and advanced export —
ships to everyone at no cost.

|Edition|Price|Includes                                                              |
|-------|-----|----------------------------------------------------------------------|
|Husky  |£0   |**Everything** — editor, iCloud sync, tags/smart lists/search, `.md` export & two-way mirror, all themes + theme editor, per-note locking, attachments, advanced export|

No ads, no tracking, no analytics on note content. Free as in price *and* free as
in open source (MIT).

-----

## Getting started *(planned)*

```bash
git clone https://github.com/chrisnicholson30/husky-notes.git
cd husky-notes
open HuskyNotes.xcodeproj   # Xcode 16+, requires an Apple Developer team for CloudKit
```

CloudKit requires:

- An Apple Developer account.
- iCloud + CloudKit capabilities enabled on the target.
- A configured CloudKit container (private database).

-----

## Licence

MIT — fully open source. Read the code, audit the sync, file an issue, or build it yourself.

- Designer: CN-DESIGN LTD
- Repo: <https://github.com/chrisnicholson30/husky-notes>
- Contact: [contact@huskynotes.com](mailto:contact@huskynotes.com)
