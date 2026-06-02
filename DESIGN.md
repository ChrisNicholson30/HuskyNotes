# Husky Notes — Design & Architecture

> A native, open-source note-taking app for iOS, iPadOS, and macOS.
> Markdown at heart, beautiful themeable rendering, reliable iCloud sync.
>
> Status: **design draft** · Last updated: 2026-06-02

---

## 1. What we're building (and why)

Husky Notes is a love-letter to two apps:

- **Obsidian** — for the Markdown-first, plain-text, *own-your-data* philosophy. The
  thing we want to keep is that a note is just Markdown; the thing we want to
  fix is that the app itself is closed-source.
- **Bear** — for the *craft*. Bear feels effortless: sync just works, search is
  instant, the editor is a joy. The reason it "just works" is an architectural
  choice (CloudKit, not iCloud Drive files) that we are deliberately copying.

**Husky Notes = Obsidian's openness + Bear's reliability, fully open-source,
with a signature Blue Husky theme.**

### Product principles

1. **Markdown is the source of truth for content.** Every note's body is plain
   Markdown (CommonMark + a small set of extensions). We never invent a binary
   note format. The "opaque store" is only about *how it syncs*, not *what a note is*.
2. **Your data is never trapped.** Open-source app + first-class, lossless
   **Export / Mirror to `.md` files**. This is the explicit answer to "but it's
   not files on disk like Obsidian." It is a headline feature, not an afterthought.
3. **Reliability over cleverness.** Sync correctness beats every other feature.
   A note app you can't trust is worthless.
4. **Native and fast.** SwiftUI across all three Apple platforms. No Electron,
   no web view for the editor.
5. **Beautiful and themeable.** Theming is a core feature, with Blue Husky as
   the flagship.

### Non-goals (for v1)

- Android / Windows / Web. (Apple-only keeps the quality bar high and the
  surface small.)
- End-to-end encrypted, zero-knowledge notes. (CloudKit private DB is already
  encrypted in transit and at rest under the user's account; true E2EE is a
  later, opt-in feature — see §9.)
- Real-time collaborative editing.
- Plugin ecosystem. (Obsidian's plugins are great but a huge surface; defer.)
- Publishing / web sharing.

---

## 2. Platform & stack

| Concern              | Choice                                              | Why |
|----------------------|-----------------------------------------------------|-----|
| Language / UI        | **Swift 6 + SwiftUI**                               | One codebase, three Apple platforms; best text editing, native feel |
| Min OS               | iOS/iPadOS 18, macOS 15                             | Lets us use the modern SwiftData + CloudKit stack cleanly |
| Persistence + sync   | **SwiftData backed by CloudKit (private DB)**       | Record-level sync with automatic conflict handling — the "Bear model" |
| Markdown parsing     | **swift-markdown** (apple/swift-markdown, GFM)      | Apple-maintained CommonMark/GFM parser → AST we render ourselves |
| Editor rendering     | **TextKit 2** (`NSTextView`/`UITextView` bridged)   | Live, themed inline rendering; far more control than `TextEditor` |
| Theming              | Custom `Theme` model + environment injection        | Storage-independent; pure presentation layer |
| Search               | SwiftData predicates + an FTS index (see §6)        | Instant full-text search at scale |
| Distribution         | App Store (paid up-front or free + one-time unlock) | Solo-friendly; open-source repo, paid binary is fine |

### Why not the alternatives

- **Not plain `.md` in iCloud Drive (the pure Obsidian model).** iCloud Drive's
  document sync is genuinely unreliable with *many small files* — this is the #1
  Obsidian-on-iPhone complaint (conflict copies, partial syncs, lag). We get the
  same openness via the export feature without inheriting the sync pain.
- **Not Core Data directly.** SwiftData is the modern, less-boilerplate layer over
  the same engine and has first-class CloudKit mirroring via `ModelConfiguration`.
- **Not React Native / Flutter / Electron.** The editor *is* the app. A native
  text engine (TextKit 2) is non-negotiable for feel and performance.

> Note: this is a **separate project** from Fleetlix (which is a Vite/React PWA).
> Nothing here shares code or stack with the rest of this repo; it lives under
> `HuskyNotes/` only because that's where this design conversation started.

---

## 3. Storage & sync model (the core decision)

**Decision: notes are SwiftData records synced via the CloudKit private database;
note *content* is Markdown text; an Export/Mirror feature writes real `.md` files.**

```
┌─────────────────────────────────────────────────────────────┐
│  Device (iPhone / iPad / Mac)                                 │
│                                                              │
│   SwiftUI views ──▶ ViewModels ──▶ SwiftData ModelContext    │
│                                        │                     │
│                                        ▼                     │
│                          Local SQLite store (SwiftData)      │
│                                        │                     │
│                          NSPersistentCloudKitContainer        │
│                                        │  (automatic)        │
└────────────────────────────────────────┼─────────────────────┘
                                          ▼
                          ┌───────────────────────────┐
                          │  iCloud — CloudKit          │
                          │  private database           │
                          │  (per-Apple-ID, encrypted)  │
                          └───────────────────────────┘
                                          │
                  ┌───────────────────────┴───────────────────────┐
                  ▼                                               ▼
            other devices                              Export / Mirror job
            (same flow)                                writes .md + assets to
                                                       a user-chosen folder
                                                       (Files / iCloud Drive /
                                                        local disk / Finder)
```

Key points:

- **CloudKit does the hard part.** `NSPersistentCloudKitContainer` (which SwiftData
  uses under the hood when `cloudKitDatabase:` is set) handles record-level merge,
  conflict resolution, partial sync, and offline queueing. We don't hand-roll a
  sync engine.
- **Sync is silent and account-scoped.** Notes live in the user's *private*
  CloudKit DB. No server of ours, no accounts to manage, no per-seat costs. If
  the user is signed into iCloud, it works; if not, the app still works fully
  offline against the local store.
- **Content stays Markdown.** A `Note.body` is a `String` of Markdown. We are not
  locking content into a proprietary blob — the "opaqueness" is purely that the
  sync container isn't a user-browsable folder of files.
- **Export answers "but I want files."** See §7. One toggle turns on continuous
  mirroring to a `.md` folder; a menu item does a one-shot export. This is the
  open-data guarantee.

### Why this beats both reference apps on its own terms

- vs **Obsidian**: same Markdown content, same export-to-folder option, but the
  *default* sync path is the reliable one and the app is open-source.
- vs **Bear**: same reliability (same underlying tech), but content is openly
  Markdown and the user can mirror to files whenever they like.

---

## 4. Data model

SwiftData `@Model` classes. All synced via CloudKit, so every relationship is
optional and every property has a default (CloudKit mirroring requirements).

```swift
@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""              // derived from first H1/line, editable
    var body: String = ""              // Markdown source — the source of truth
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var isPinned: Bool = false
    var isArchived: Bool = false
    var isTrashed: Bool = false        // soft-delete; purged after N days
    var trashedAt: Date? = nil

    // Tags are parsed from #inline-tags in the body AND stored relationally
    // for fast filtering. Body remains canonical; this is a denormalised index.
    @Relationship(deleteRule: .nullify, inverse: \Tag.notes)
    var tags: [Tag]? = []

    @Relationship(deleteRule: .cascade, inverse: \Attachment.note)
    var attachments: [Attachment]? = []
}

@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""              // normalised, e.g. "work/clients"
    var colorHex: String? = nil
    var notes: [Note]? = []
}

@Model
final class Attachment {
    var id: UUID = UUID()
    var filename: String = ""
    // Binary stored as a CloudKit asset via SwiftData external storage,
    // NOT inline in the record (keeps records small, sync fast).
    @Attribute(.externalStorage) var data: Data? = nil
    var note: Note? = nil
    var createdAt: Date = Date()
}
```

Settings/themes are **not** synced via CloudKit by default (device-local in
`UserDefaults`/app group), with an *optional* "sync my settings" toggle using
`NSUbiquitousKeyValueStore`. Rationale: a broken theme shouldn't propagate to
every device, and theme files are small.

### Snapshot / denormalisation notes

- `title` is denormalised from the body so list views never parse Markdown.
  Recomputed on save.
- `tags` relationship is a denormalised index of `#tags` found in the body. The
  body is canonical; on save we re-extract and reconcile the relationship.

---

## 5. App structure & navigation

Per-platform-idiomatic but shared SwiftUI:

- **macOS / iPadOS**: three-column `NavigationSplitView`
  `Sidebar (tags / smart lists)` → `Note list` → `Editor`.
- **iOS**: stacked `NavigationStack`, list → editor; sidebar as a slide-over.

Smart lists (computed, not stored): All Notes, Pinned, Today, Untagged,
Archived, Trash, plus one per Tag.

```
HuskyNotes/
├── App/                     # @main, app delegate adaptor, ModelContainer setup
├── Models/                  # SwiftData @Model types (§4)
├── Sync/                    # CloudKit container config, status, conflict UI
├── Editor/                  # TextKit 2 view, Markdown live-render, toolbar
├── Markdown/                # swift-markdown wrappers, AST → AttributedString
├── Theme/                   # Theme model, ThemeStore, built-in themes (§8)
├── Features/
│   ├── NoteList/
│   ├── Sidebar/
│   ├── Search/
│   └── Settings/
├── Export/                  # .md mirror + one-shot export (§7)
└── Resources/               # Assets, app icon, bundled themes, sample notes
```

---

## 6. Search

- Primary: SwiftData `#Predicate` over `title`/`body` for small libraries.
- At scale: maintain a lightweight **SQLite FTS5** index (separate, local-only,
  rebuildable) keyed by note `id`, updated on save. Search hits FTS, then loads
  notes by id. FTS index is *not* synced — it's a derived cache.
- Tag filter + text query compose (e.g. `#work invoice`).

---

## 7. Export & "own your files" (the openness guarantee)

Two modes, both producing standard Markdown:

1. **One-shot Export** — menu command. Writes every note to
   `<chosen folder>/<tag-path>/<title>.md`, attachments to `_attachments/`,
   tags preserved as `#inline` + YAML frontmatter. Produces a folder you could
   drop straight into Obsidian.
2. **Continuous Mirror** (opt-in toggle) — a background task keeps a chosen
   folder in sync with the store (one-way: store → files by default; optional
   two-way later). Uses file coordination so it's safe in iCloud Drive.

Frontmatter format per note:

```markdown
---
id: 3F2A...           # stable UUID, lets re-import match
created: 2026-06-02T09:14:00Z
modified: 2026-06-02T10:01:00Z
tags: [work/clients, invoices]
pinned: false
---

# Note title

Body in Markdown…
```

This is the contract that makes "open-source + your data is yours" true in
practice, not just in spirit.

---

## 8. Theming

Theming is a pure presentation concern, fully decoupled from storage.

```swift
struct Theme: Codable, Identifiable {
    let id: String
    let name: String
    let isDark: Bool

    // Core palette
    let background: HexColor
    let surface: HexColor
    let textPrimary: HexColor
    let textSecondary: HexColor
    let accent: HexColor

    // Markdown element styling
    let heading: HexColor
    let link: HexColor
    let codeBackground: HexColor
    let codeText: HexColor
    let quoteBar: HexColor
    let selection: HexColor

    // Typography
    let bodyFont: String        // PostScript name or "system"
    let monoFont: String
    let bodySize: Double
    let lineSpacing: Double
}
```

- A `ThemeStore` (Observable) holds the active theme; injected via
  `.environment`. The editor's TextKit rendering and all SwiftUI chrome read
  from it.
- Built-in themes ship in `Resources/Themes/*.json`. Users can duplicate + edit
  in-app; custom themes are device-local (optionally KV-synced).
- **Blue Husky** is the flagship (see §10).

---

## 9. Privacy & security

- Notes live in the **CloudKit private database**: encrypted in transit and at
  rest, scoped to the user's Apple ID. We (the developer) never see note data —
  there is no Husky Notes server.
- **Local privacy**: optional Face ID / Touch ID app lock; optionally lock
  individual notes.
- **Future: opt-in E2EE.** CloudKit private DB is already encrypted under the
  user's account, but for true zero-knowledge (Apple can't decrypt) we could
  add a user passphrase + client-side encryption of `body` before it hits
  SwiftData. Deferred — adds real complexity (key management, search-over-
  ciphertext, recovery). Flagged as a v2+ decision.

---

## 10. Branding — "Blue Husky"

- **Name**: Husky Notes. Wordmark in a rounded geometric sans (e.g. a custom
  cut or SF Rounded).
- **Mascot/logo**: a stylised Husky head, ¾ or front-facing, built from clean
  geometric shapes — works as a 1024px App Store icon *and* a 16px favicon /
  menu-bar glyph. Distinctive husky cues: pricked ears, eye mask, the
  characteristic facial markings, ice-blue eyes.
- **Blue Husky palette** (starting point — refine in design):

  | Token        | Hex       | Use |
  |--------------|-----------|-----|
  | Background   | `#0B1622` | deep slate-navy (dark base) |
  | Surface      | `#13202E` | cards, sidebar |
  | Text primary | `#E6EEF5` | body text |
  | Text 2nd     | `#8FA6B8` | metadata |
  | Accent       | `#3DA9FC` | husky ice-blue — links, selection, active |
  | Heading      | `#7FD0FF` | |
  | Code bg      | `#0E1B27` | |
  | Quote bar    | `#2C6E9B` | |

  A light "Husky Day" variant inverts to a clean snow-white base with the same
  ice-blue accent.

- Logo assets to produce: App icon (all sizes), monochrome menu-bar template
  (macOS), in-app mark, marketing hero. Could be vector (SVG → asset catalog).

---

## 11. Roadmap

**v0.1 — Editor spike**
- SwiftUI shell, TextKit 2 editor, swift-markdown live rendering, one theme.
- Local SwiftData only (no sync yet). Prove the editor feels right.

**v0.2 — Sync**
- Turn on CloudKit (`NSPersistentCloudKitContainer`). Multi-device test.
- Conflict + sync-status UI. Offline behaviour.

**v0.3 — Organisation**
- Tags, smart lists, sidebar, search (predicate + FTS).

**v0.4 — Openness**
- Export + Mirror to `.md`. Frontmatter round-trip. Import from Obsidian/Bear.

**v0.5 — Theming & polish**
- Theme editor, Blue Husky + light variant + 2–3 others. App icon. App lock.

**v1.0 — Ship**
- Attachments, iPad pointer/keyboard polish, macOS menu commands, App Store.

**Post-1.0**: opt-in E2EE, two-way mirror, plugins, web clipper, publishing.

---

## 12. Open decisions

- **Pricing / licensing model.** Open-source repo + paid App Store binary? Or
  free with a one-time "supporter" unlock? (Open-source ≠ free binary.)
- **Min OS floor.** iOS 18 lets us go all-in on SwiftData; dropping to iOS 17
  widens reach but adds Core Data fallbacks. Leaning iOS 18.
- **Two-way mirror in scope for v1?** Currently store→files only for v1;
  bidirectional is a known hazard (external edits, conflicts).
- **E2EE.** Whether to commit to a zero-knowledge story at all (marketing pull
  vs. real complexity and recovery risk).
- **Wiki-links / backlinks.** Obsidian's `[[links]]` are beloved. In scope?
  If so, they affect the data model (link graph) and editor.

---

## 13. Summary of the decision you made

> **Storage model: CloudKit + export.** Notes sync via the CloudKit private
> database (Bear-style reliability), content stays plain Markdown, and a
> first-class export/mirror-to-`.md` feature plus an open-source license is the
> answer to Obsidian-style "own your data." Best of both apps, neither's
> downside.
