# Husky Notes — Code Review & Marketing Alignment

> Status review of the v0.1 scaffold against the design docs and the marketing
> site (**huskynotes.com**). Reviewed: 2026-06-04.
> Scope: `HuskyNotes/` source, `README.md`, `DESIGN.md`, `resources/*`.

---

## TL;DR

The v0.1 scaffold is well-built and principled. Separation of concerns is clean,
the theming-decoupled-from-storage rule is honoured everywhere (every view reads
`theme.*`; nothing is hard-coded), the SwiftData models follow the CloudKit
mirroring rules, and the TextKit 2 live-source styler — the real centrepiece — is
solid.

The gap is **wiring, not architecture.** Several headline features have their
engine written but no wire connecting it to the running app, so they are inert in
the binary even though the files exist. One feature (tags) is an actual bug rather
than a missing wire.

- **1 marketed feature is fully real:** Markdown editor.
- **2 are legitimately future work:** CloudKit sync, custom theme editor.
- **3 have the engine but the claim/wire doesn't match:** Tags (broken), Search
  (unreachable + under-spec), `.md` mirror (oversold vs the one-shot export that
  actually exists).

---

## Marketing site → code reality

The site's "Why Husky" section makes six feature claims plus a stat bar. Mapped
against the code:

| Site card / claim | State | Detail |
|---|---|---|
| **Markdown at heart** — "real native text engine, no web view, no lag" | ✅ Real | `Markdown/MarkdownStyler.swift` + `Editor/MarkdownEditor.swift` (TextKit 2, `UITextView`/`NSTextView`). Live source styling that round-trips byte-for-byte. The strongest part of the codebase. |
| **Sync that just works** — "record-level CloudKit, silent, conflict-aware, offline" | ❌ Not built | Local-only in v0.1. The CloudKit switch is staged and commented in `App/PersistenceController.swift:43`. This is the site's hero line ("Sync you can trust") and is the single biggest unbuilt pillar. |
| **Beautiful themes** — "Blue Husky, Husky Day, and more — or **craft your own palette and type**" | ⚠️ Partial | Six themes ship and the picker works (`Features/Settings/ThemeSettingsView.swift`). But there is **no theme editor** — "craft your own" is not implemented. |
| **Tags & smart lists** — "Drop `#inline` tags anywhere… builds smart lists automatically… **with zero setup**" | ⚠️ Broken | The Tag model, sidebar Tags section, and Untagged/per-tag lists all exist, but **nothing ever parses `#tags` from the body.** See "Critical" below. |
| **Instant search** — "**full-text index**… snappy at thousands… **compose tag filters and text** (`#work invoice`)" | ⚠️ Triple gap | `Features/Search/SearchView.swift` is **never referenced** anywhere (unreachable in the app); it is a linear substring scan, not an FTS index; and it cannot compose `#tag` + text. |
| **Your data is never trapped** — "**One toggle mirrors every note** to real `.md`… drop into Obsidian" | ⚠️ Oversold | The site sells the **continuous mirror**. The code has only **one-shot export** (`Export/MarkdownExporter.swift`; mirror is a `TODO`), and even that export is **not wired to any UI** (no menu/toolbar/`fileExporter`). |

Stat bar: Built natively in SwiftUI ✅ · iCloud private sync ❌ (staged) ·
CommonMark + GFM ✅ (but no table/footnote styling yet) · No account required ✅ ·
100% open source ✅ (no StoreKit/entitlement gating anywhere — consistent with the
"completely free" principle).

**Site-level honesty flag:** the homepage offers "Download for Mac" and
"App Store · iOS" buttons. The app is a pre-1.0, local-only scaffold — there are
no shippable binaries behind those buttons yet.

---

## Needed now (makes the scaffold internally honest)

These are not big features — they connect things that are already written, plus
one real bug fix.

### 1. Tag extraction is missing — **the one real bug** (Critical)

Everything tag-related assumes `Note.tags` is populated, but no code ever fills
it:

- `Models/Tag.swift:6` documents "Tags are derived from `#hashtags`… recomputed
  on save."
- `Features/Editor/NoteEditorView.swift:55` calls only `recomputeTitle()` on edit
  — there is no `recomputeTags()` anywhere in the codebase.
- Consequence: the sidebar "Tags" section is always empty, the **Untagged** smart
  list contains every note, per-tag lists never appear, and the export's
  "file note under its first tag" branch (`MarkdownExporter.swift:118`) is dead.
- The seeded sample even claims "Tag things inline like `#welcome` and they
  become smart lists" (`PersistenceController.swift:101`) — which never happens.

**Fix:** add a tag parser (scan body for `#tag` tokens, normalise, support
`work/clients` nesting per the export logic) and call it alongside
`recomputeTitle()` in the body binding; reconcile the `Note.tags` relationship,
creating/reusing `Tag` records and pruning orphans.

### 2. Search is unreachable

`SearchView` is fully written but referenced by nothing (confirmed: only its own
file and `BUILD_PLAN.md` mention it). Wire it into navigation — a sidebar entry
or a top-level `.searchable` — so it can actually be opened. (FTS5 + `#tag`
composition can stay deferred; see Later.)

### 3. Export has no entry point

`MarkdownExporter` + `Frontmatter` are implemented and round-trip losslessly, but
nothing calls `.export(...)`. Add a macOS menu command and an iOS
toolbar/`fileExporter` so the "your data is never trapped" promise is reachable.

### 4. Doc drift in `README.md`

- Data-model table lists `updatedAt` and `isLocked`; the actual `Note` uses
  `modifiedAt` and has no `isLocked` (`Models/Note.swift`).
- Themes are described as four (Blue Husky, Husky Day, Pine, Ember) but the app
  ships **six** (adds Glacier, Aurora — `Theme/BuiltInThemes.swift:16`).
- GFM checklist promises tables and footnotes; the styler has no special handling
  for either yet (they render as plain body text).

---

## Bring in later (genuinely planned — deferring is correct)

| Item | Where it stands | Notes |
|---|---|---|
| **CloudKit sync** (v0.2) | Staged one-line flip in `PersistenceController.swift`; models are CloudKit-ready | The marketing centrepiece; needs Apple Developer account + container. |
| **Continuous two-way `.md` mirror** | `TODO` in `MarkdownExporter.swift:111` | Site markets "one toggle"; one-shot export is the right first step. Two-way is post-1.0. |
| **Custom theme editor** | Picker only today | "Craft your own palette and type" — duplicate + edit flow over the existing `Theme` JSON. |
| **FTS5 search index + `#tag` composition** | Substring scan today (fine for v0.1) | `SearchView.swift:9` already flags this for v0.3. |
| **Per-note locking / Face ID** | Not in model | On site & README (`isLocked`); add field + biometric gate later. |
| **Attachments UI** | Model + export support exist; no capture UI | Image/file insert flow. |
| **GFM tables & footnotes styling** | Not handled in styler | Add visitor cases in `StylingVisitor`. |
| **Focus mode behaviour** | Placeholder toggle does nothing (`NoteEditorView.swift:29`) | Wire to hide sidebar/list and centre the column. |
| **macOS "New Note" command** | Posts `.huskyNewNote` that nothing observes (`HuskyNotesApp.swift:34`) | Connect to `NoteListView`'s insert. |
| **Import from Obsidian/Bear** | Not started | `Frontmatter.parseDocument` already supports the round-trip read side. |

---

## What's genuinely good (keep doing this)

- **Theming discipline:** every surface reads the active theme; the hard-coded
  `Theme.blueHusky` fallback means the app is never themeless.
- **Lossless Markdown:** the styler only ever *decorates* the original string, so
  `result.string == markdown`; export writes the body verbatim. The
  "data is never trapped" promise is structurally sound.
- **CloudKit-ready models:** defaulted properties + optional relationships
  throughout, so the v0.2 sync flip really is one line.
- **Correct caret handling** in the editor (selection clamped/preserved across
  restyle) and UTF-8 source-range mapping with grapheme-boundary fallback.

---

## Suggested sequence

1. Tag extraction (`recomputeTags`) — fixes the only real bug and lights up the
   sidebar, smart lists, and tag-based export filing at once.
2. Wire Search into navigation.
3. Add an export entry point (menu + `fileExporter`).
4. README doc-drift fixes.
5. Then resume the roadmap at v0.2 (CloudKit).
