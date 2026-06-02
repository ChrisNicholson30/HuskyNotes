# Husky Notes — Intentional Build Plan

> The "how we actually build it" companion to [`PLAN_OF_ACTION.md`](PLAN_OF_ACTION.md)
> (what + order) and [`GETTING_STARTED.md`](GETTING_STARTED.md) (from zero).
> This doc is the **engineering build order**: concrete modules, the contracts
> between them, the themes, and the exit gate for every step.
>
> Status: **v0.1 scaffold in progress** · Last updated: 2026-06-02

---

## 0. One screen, the whole plan

```
            ┌─────────────────────────────────────────────────────────┐
            │  Native SwiftUI shell  (iOS 18 · iPadOS 18 · macOS 15)    │
            │                                                           │
 Sidebar ──▶│  NavigationSplitView (mac/iPad) · NavigationStack (iOS)   │
 NoteList ─▶│         │              │                 │                │
 Editor ───▶│   Features/        Theme engine     Markdown styler       │
            │   (Sidebar,        (6 themes,        (swift-markdown       │
            │    NoteList,        ThemeStore,       AST → styled         │
            │    Search,          env-injected)     AttributedString)    │
            │    Settings)             │                 │               │
            │                          ▼                 ▼               │
            │                    TextKit 2 editor  (UITextView /         │
            │                     NSTextView, live themed render)        │
            └──────────────────────────────┬────────────────────────────┘
                                            ▼
                       SwiftData @Model  (Note · Tag · Attachment)
                                            │
                v0.1: local SQLite only ────┤──── v0.2: + CloudKit .private
                                            ▼
                       Export / Mirror  →  .md + YAML frontmatter
```

Everything is native Swift. Three App Store-eligible products from **one
codebase**: iOS/iPadOS app (App Store), macOS app (App Store **and** notarised
`.dmg` from huskynotes.com). The editor is the heart — it gets proven first.

---

## 1. Build philosophy (how we sequence decisions)

1. **Prove the editor before anything else.** TextKit 2 live styling is the long
   pole and the product's soul. If it doesn't feel right, nothing else matters.
2. **Local before sync.** v0.1 ships a fully working local app. CloudKit is a
   one-line container change in v0.2 *because* the models were built to its rules
   from day one (every property defaulted, every relationship optional).
3. **Contracts first, then parallel work.** The module boundaries below are fixed
   contracts (type names + signatures). Once they're set, modules can be built
   independently without stepping on each other.
4. **Theme-from-day-one.** No view ever hard-codes a colour. Even the v0.1 spike
   reads Blue Husky from a `Theme` object, so adding the other five themes later
   is pure data, not refactoring.
5. **Markdown is canonical.** `Note.body` is the source of truth; `title` and
   `tags` are denormalised caches recomputed on save. Export must round-trip the
   body **verbatim**.

---

## 2. Module map & contracts

The scaffold is organised exactly as `DESIGN.md §5`. Each module owns a small set
of files and exposes a stable contract the others depend on.

| Module        | Path                     | Owns / exposes |
|---------------|--------------------------|----------------|
| **Models**    | `HuskyNotes/Models/`     | `Note`, `Tag`, `Attachment` (`@Model`, CloudKit-ready). `Note.recomputeTitle()`. |
| **Theme**     | `HuskyNotes/Theme/`      | `Theme`, `HexColor`, `ThemeStore` (`@Observable`), `BuiltInThemes` (loads 6 JSONs). |
| **Markdown**  | `HuskyNotes/Markdown/`   | `MarkdownStyler.attributedString(for:theme:)` — swift-markdown AST → `NSAttributedString`. |
| **Editor**    | `HuskyNotes/Editor/`     | `MarkdownEditor` (`UI/NSViewRepresentable`) over a TextKit 2 text view; platform typealiases. |
| **App**       | `HuskyNotes/App/`        | `@main HuskyNotesApp`, `PersistenceController` (ModelContainer), `RootView` (navigation). |
| **Features**  | `HuskyNotes/Features/`   | `SidebarView`, `NoteListView`, `NoteEditorView`, `SearchView`, `ThemeSettingsView`, `SmartList`. |
| **Export**    | `HuskyNotes/Export/`     | `Frontmatter`, `MarkdownExporter.export(_:to:)`. |
| **Resources** | `HuskyNotes/Resources/`  | `Themes/*.json` (6), `SampleNotes/welcome.md`, assets, app icon. |

**Key contracts (do not drift from these):**

- `Note`: `id, title, body, createdAt, modifiedAt, isPinned, isArchived, isTrashed, trashedAt, tags?, attachments?` — every property defaulted, relationships optional.
- `Theme`: `id, name, isDark` + palette (`background, surface, textPrimary, textSecondary, accent, heading, link, codeBackground, codeText, quoteBar, selection`) + typography (`bodyFont, monoFont, bodySize, lineSpacing`). `Codable`.
- `ThemeStore`: `@Observable`, `themes`, `activeThemeID` (persisted), `active`, `select(_:)`. Injected via `.environment`; read with `@Environment(ThemeStore.self)`.
- `MarkdownStyler`: pure function `(markdown, theme) -> NSAttributedString`, **live source styling** (syntax characters stay visible, no preview pane).
- `MarkdownEditor`: `@Binding var text`, `let theme`; restyles `textStorage` on edit while preserving selection.

---

## 3. The six themes

Four are taken **verbatim from huskynotes.com**; two (Glacier, Aurora) are new,
designed to round out the set with a second light option and a distinctive dark
one. All ship as `Resources/Themes/*.json` and load through `BuiltInThemes`.

| # | Theme         | Mode  | Background | Surface  | Accent   | Heading  | Role |
|---|---------------|-------|------------|----------|----------|----------|------|
| 1 | **Blue Husky**| dark  | `#0B1622`  | `#13202E`| `#3DA9FC`| `#7FD0FF`| **Flagship / default dark** |
| 2 | **Husky Day** | light | `#F7FAFC`  | `#E6EEF5`| `#2C82C9`| `#1E5F96`| **Default light** (the "snow" husky) |
| 3 | **Pine**      | dark  | `#0F1B17`  | `#16271F`| `#5BD6A0`| `#A7F3D0`| Calm forest green |
| 4 | **Ember**     | dark  | `#1A1212`  | `#271717`| `#F0883E`| `#FBC9A0`| Warm low-light |
| 5 | **Glacier** ✨| light | `#F4F9FD`  | `#E3EFF8`| `#1F8FB8`| `#15637E`| New — crisp icy light |
| 6 | **Aurora** ✨ | dark  | `#12101E`  | `#1C1830`| `#A78BFA`| `#7DE3D0`| New — northern-lights violet/teal |

> `blue-husky.json` is the single source of truth for the flagship palette, and
> the hard-coded `Theme.blueHusky` fallback mirrors it. Adding/editing themes
> never touches stored notes — theming is presentation only.

The in-app **theme editor** (v0.5) duplicates one of these JSONs into a
device-local custom theme. Custom themes are stored in `UserDefaults`/app group,
optionally KV-synced — never in CloudKit, so a broken theme can't propagate.

---

## 4. Capabilities — all free, all shipped

Husky Notes is **completely free**: no tiers, no IAP, no StoreKit, no feature
gates to build. Every capability below ships to everyone. The only thing that
changes across versions is *when it lands*, not *who gets it*.

| Capability                              | Lands in | Notes |
|-----------------------------------------|:--------:|-------|
| TextKit 2 live Markdown editor          | v0.1     | The core; CommonMark + GFM |
| Local SwiftData persistence             | v0.1     | Offline-first foundation |
| 6 built-in themes + theme engine        | v0.1→0.5 | Blue Husky proves it in v0.1; rest + editor in v0.5 |
| CloudKit private-DB sync                | v0.2     | Record-level, offline, conflict-aware |
| Inline `#tags` → smart lists            | v0.3     | Denormalised, reconciled on save |
| Full-text search (predicate + FTS5)     | v0.3     | Composable `#tag text` queries |
| `.md` export + YAML frontmatter         | v0.4     | Round-trips losslessly; Obsidian-ready |
| Import (Obsidian/Bear) + continuous mirror | v0.4  | Match by `id` on re-import |
| In-app theme editor / custom themes     | v0.5     | Device-local, optional KV-sync |
| Face ID / Touch ID app lock + per-note lock | v0.5 | Local privacy |
| Attachments & images                    | v1.0     | CloudKit assets via external storage |
| Distraction-free focus mode             | v1.0     | |

---

## 5. Phased build order (with exit gates)

This refines `PLAN_OF_ACTION §4` into the build order the scaffold follows.

### v0.1 — Editor spike *(this scaffold)*
**Build:** App shell + local `ModelContainer` → minimal `Note` → `Theme`/`ThemeStore`
+ Blue Husky → `MarkdownStyler` → `MarkdownEditor` (TextKit 2) → wire into a
`NavigationSplitView`. Project generated via `project.yml` (XcodeGen), `swift-markdown`
the only dependency.
**Exit gate:** typing a heading / list / checklist / code block / quote restyles
live and *feels good*; the underlying string stays clean Markdown; one theme drives
every colour. → *prototype the editor in isolation first if TextKit fights you.*

### v0.2 — Sync
**Build:** finalise `Note`/`Tag`/`Attachment`; flip `PersistenceController` to
`ModelConfiguration(cloudKitDatabase: .private)` (the line is already present,
commented); add CloudKit + iCloud capability + container `iCloud.com.huskynotes.app`;
sync-status + conflict UI.
**Exit gate:** create on iPhone, appears on Mac; survives an offline→online edit
cycle with no data loss.

### v0.3 — Organisation
**Build:** inline `#tag` parser → reconcile `Tag` relationship on save; sidebar
smart lists (All, Pinned, Today, Untagged, Archived, Trash, per-tag); search via
`#Predicate`, then a local rebuildable **SQLite FTS5** index; composable tag+text
queries.
**Exit gate:** instant search at scale; smart lists update as notes/tags change.

### v0.4 — Openness
**Build:** one-shot export (`<folder>/<tag-path>/<title>.md` + `_attachments/`);
YAML frontmatter; opt-in continuous mirror (store→files, file-coordination safe);
import from Obsidian/Bear matching by `id`.
**Exit gate:** export a vault, open it in Obsidian, re-import without duplicates.

### v0.5 — Theming & polish
**Build:** ship all 6 themes; in-app theme editor (duplicate + edit, device-local);
app icon (all sizes) + macOS menu-bar template glyph; Face ID/Touch ID app lock +
optional per-note lock.
**Exit gate:** switching themes is instant and never touches stored data.

### v1.0 — Ship
**Build:** attachments & images (CloudKit assets, external storage); iPad
pointer/keyboard polish; macOS menu commands; focus mode; App Store submission
(**free, no IAP**); notarised `.dmg` for the website.
**Exit gate:** App Store review passes on iOS and macOS; the `.dmg` launches
notarised; every feature available to every user.

### Post-1.0
Opt-in E2EE, two-way mirror, wiki-links/backlinks, plugins, web clipper.

---

## 6. Distribution (three products, one codebase)

- **iOS / iPadOS** → App Store (single universal app).
- **macOS** → App Store build **and** a Developer-ID-signed, **notarised `.dmg`**
  downloadable from huskynotes.com (the open-source/own-your-binary story).
- CI (`/.github/workflows/ci.yml`) generates the project with XcodeGen and builds
  both schemes on every push. Release signing/notarisation is a separate, later
  release workflow (post-v0.1).

---

## 7. Definition of done (every feature)

A checklist item is done only when it:

1. works across **all three** platforms (or is explicitly platform-scoped),
2. survives an **offline → online** sync cycle without data loss,
3. has at least a smoke test (unit tests for parsing/sync/export logic),
4. respects the active theme (no hard-coded colours), and
5. round-trips exported `.md` losslessly where it touches content.

---

## 8. Open decisions still gating phases

| Decision | Gates | Current lean |
|----------|-------|--------------|
| Min OS floor | v0.1 | **iOS 18 / macOS 15** (all-in SwiftData) — used by this scaffold |
| Two-way mirror in v1? | v0.4 | store→files one-way for v1; two-way post-1.0 |
| E2EE | post-1.0 | defer; CloudKit private DB already encrypted under the user's account |
| Wiki-links `[[ ]]` | v0.3 (if yes) | defer to post-1.0 (affects model + editor) |
| ~~Pricing~~ | — | **Resolved: free, no tiers, MIT** |

---

## 9. What this scaffold delivers right now

The `HuskyNotes/` source tree (generated alongside this doc) contains the v0.1
skeleton: data models, the theme engine with all six themes, the swift-markdown
styler, the TextKit 2 editor bridge, the navigation shell, the feature views, the
export layer, and the `project.yml` + CI to open and build it in Xcode. Next
action: run `xcodegen generate`, open `HuskyNotes.xcodeproj`, and drive the v0.1
exit gate on the editor.
