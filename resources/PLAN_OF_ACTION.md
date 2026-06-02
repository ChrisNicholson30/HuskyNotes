# Husky Notes — Plan of Action

> Derived from [`README.md`](../README.md) and [`DESIGN.md`](../DESIGN.md).
> Status: **planning** · Last updated: 2026-06-02

This document turns the vision in the README into a concrete, sequenced plan of
work. It is the "what we build, in what order, and how we know it's done"
companion to the design doc.

---

## 1. Goal in one sentence

Ship a native SwiftUI Markdown note-taking app for iPhone, iPad and Mac that
pairs **Obsidian's openness** (plain `.md`, open source, your data is never
trapped) with **Bear's reliability** (CloudKit private-DB sync that just works),
fronted by a beautiful, themeable TextKit 2 editor.

---

## 2. Guiding principles (non-negotiable)

These are the lens for every decision below — if a feature breaks one, it loses.

1. **Notes are plain Markdown.** CommonMark + GFM; the on-disk truth is portable.
2. **Native, not web.** Live inline rendering via TextKit 2 — no web view.
3. **No server.** Sync runs on the user's private iCloud (CloudKit) database.
4. **Theming is decoupled from storage.** Presentation only; zero data risk.
5. **Data is never trapped.** First-class `.md` export with YAML frontmatter.
6. **Reliability over cleverness.** Sync correctness beats every other feature.

---

## 3. Workstreams

The build splits into seven workstreams. Each maps to part of the architecture
in `DESIGN.md` and to entries on the README feature checklist.

| # | Workstream        | Owns                                                        | Design ref |
|---|-------------------|-------------------------------------------------------------|------------|
| A | Foundations       | Xcode project, SwiftUI shell, SwiftData container, CI       | §2, §5     |
| B | Editor            | TextKit 2 view, live Markdown render, swift-markdown AST     | §2, §5     |
| C | Data & sync       | `Note`/`Tag`/`Attachment` models, CloudKit private DB sync  | §3, §4     |
| D | Organisation      | Tags, smart lists, sidebar, full-text search (predicate+FTS)| §5, §6     |
| E | Openness / export | `.md` export + continuous mirror, YAML frontmatter, import  | §7         |
| F | Theming           | `Theme` model, `ThemeStore`, built-in themes, theme editor  | §8, §10    |
| G | Privacy & polish  | App lock (Face ID / Touch ID), per-note lock, platform polish| §9         |

---

## 4. Phased roadmap (sequenced)

Mirrors the roadmap in `DESIGN.md §11`, expanded into actionable milestones with
exit criteria.

### v0.1 — Editor spike  *(Workstreams A, B)*
- [ ] Xcode 16 project, Swift 6, SwiftUI shell targeting iOS 18 / macOS 15.
- [ ] SwiftData `ModelContainer` (local only — **no sync yet**).
- [ ] TextKit 2 editor bridged into SwiftUI (`UITextView`/`NSTextView`).
- [ ] `swift-markdown` AST → `AttributedString` live inline rendering.
- [ ] One hard-coded theme (Blue Husky) to prove rendering.
- **Exit:** typing a heading / list / code block renders live and feels good.

### v0.2 — Sync  *(Workstream C)*
- [ ] Define `Note`, `Tag`, `Attachment` `@Model` types (all properties defaulted,
      relationships optional — CloudKit mirroring rules).
- [ ] Switch container to `cloudKitDatabase: .private`.
- [ ] Multi-device test (iPhone ↔ Mac), offline-first behaviour.
- [ ] Sync-status + conflict-resolution UI.
- **Exit:** create on one device, appears on another; survives offline edits.

### v0.3 — Organisation  *(Workstream D)*
- [ ] Inline `#tag` parsing → denormalised `Tag` relationship reconciled on save.
- [ ] Sidebar with smart lists: All, Pinned, Today, Untagged, Archived, Trash,
      plus one per tag.
- [ ] Search: SwiftData `#Predicate` + SQLite FTS5 index (local-only, rebuildable).
- [ ] Composable tag + text queries (e.g. `#work invoice`).
- **Exit:** instant search at scale; smart lists update as notes/tags change.

### v0.4 — Openness  *(Workstream E)*
- [ ] One-shot `.md` export: `<folder>/<tag-path>/<title>.md` + `_attachments/`.
- [ ] YAML frontmatter (`id`, `created`, `modified`, `tags`, `pinned`).
- [ ] Continuous mirror (opt-in, store→files, file-coordination safe).
- [ ] Import from Obsidian / Bear; frontmatter round-trip (re-import matches by `id`).
- **Exit:** export a vault, drop into Obsidian, re-import without dupes.

### v0.5 — Theming & polish  *(Workstreams F, G)*
- [ ] `Theme` model + `ThemeStore` (Observable, environment-injected).
- [ ] Built-in themes shipped as `Resources/Themes/*.json`:
      Blue Husky, Husky Day, Pine, Ember.
- [ ] In-app theme editor (duplicate + edit; device-local, optional KV-sync).
- [ ] App icon (all sizes) + macOS menu-bar template glyph.
- [ ] Face ID / Touch ID app lock; optional per-note lock.
- **Exit:** switching themes is instant and never touches stored data.

### v1.0 — Ship
- [ ] Attachments & image handling (CloudKit assets via external storage).
- [ ] iPad pointer/keyboard polish; macOS menu commands.
- [ ] Distraction-free focus mode.
- [ ] App Store submission (one-time unlock — Free vs Pro tiers per README).
- **Exit:** App Store build passes review; Free/Pro gating works.

### Post-1.0
- Opt-in E2EE, two-way mirror, plugins, web clipper, publishing.

---

## 5. Tier gating (Free vs Pro)

Per the README monetisation table — bake the gate in from v0.5 so Pro features
are flagged as they land, not retrofitted.

| Capability                      | Free | Pro |
|---------------------------------|:----:|:---:|
| Editor, iCloud sync, search     |  ✅  | ✅  |
| Tags / smart lists              |  ✅  | ✅  |
| `.md` export (one-shot)         |  ✅  | ✅  |
| Blue Husky + Husky Day themes   |  ✅  | ✅  |
| Continuous two-way `.md` mirror |  —   | ✅  |
| Full theme editor / custom      |  —   | ✅  |
| Per-note locking                |  —   | ✅  |
| Attachments & image handling    |  —   | ✅  |
| Advanced export                 |  —   | ✅  |

---

## 6. Open decisions to resolve (blocking later phases)

Carried from `DESIGN.md §12` — each needs a call before the phase it gates.

- [ ] **Pricing / licensing** — open-source repo + paid binary, or free + unlock?
      *(blocks v1.0)*
- [ ] **Min OS floor** — iOS 18 (all-in SwiftData) vs iOS 17 (Core Data fallback).
      *(blocks v0.1 — leaning iOS 18)*
- [ ] **Two-way mirror in v1?** — currently store→files only. *(blocks v0.4)*
- [ ] **E2EE** — commit to a zero-knowledge story at all? *(post-1.0)*
- [ ] **Wiki-links / backlinks** — `[[links]]` in scope? Affects model + editor.
      *(blocks v0.3 if yes)*

---

## 7. Definition of done (per feature)

A checklist item is "done" only when:

1. It works across **all three** platforms (or is explicitly platform-scoped).
2. It survives an **offline → online** sync cycle without data loss.
3. It has at least a smoke test (and unit tests for parsing/sync logic).
4. It respects the active theme (no hard-coded colours).
5. Exported `.md` round-trips losslessly where the feature touches content.

---

## 8. Immediate next steps

1. Lock the **min OS floor** decision (iOS 18 vs 17).
2. Scaffold the Xcode project + SwiftUI shell (v0.1, Workstream A).
3. Stand up the TextKit 2 editor spike (v0.1, Workstream B).
4. Keep this plan and `CLAUDE.md` updated as milestones land.
