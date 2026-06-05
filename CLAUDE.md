# CLAUDE.md

Guidance for Claude Code (and other AI assistants) when working in this
repository. Keep this file updated as the project evolves.

---

## What this project is

**Husky Notes** — a native, open-source Markdown note-taking app for iPhone,
iPad and Mac. The pitch: Obsidian's openness + Bear's reliability, in a
beautiful themeable editor. Every note is plain CommonMark and always belongs to
the user.

- **Status:** in development / planning. Most features are *(planned)*.
- **Key docs:**
  - [`README.md`](README.md) — the public engineering plan / overview.
  - [`DESIGN.md`](DESIGN.md) — deep design & architecture (the source of truth
    for technical decisions).
  - [`resources/PLAN_OF_ACTION.md`](resources/PLAN_OF_ACTION.md) — sequenced,
    phased build plan with exit criteria.
  - [`resources/BUILD_PLAN.md`](resources/BUILD_PLAN.md) — the engineering build
    order: module contracts, the six themes, capabilities, per-version exit gates.
  - [`resources/FEATURE_PLAN.md`](resources/FEATURE_PLAN.md) — scoped plan for
    tables, file/PDF viewer, and link-with-thumbnail (phased, round-trip-safe).
  - [`resources/GETTING_STARTED.md`](resources/GETTING_STARTED.md) — kickoff
    guide: resources/accounts needed and the concrete first steps.

> Note: this is a **separate project** from anything else that might share the
> repo. Nothing here shares code or stack with other apps.

---

## Tech stack (planned)

| Concern        | Technology                                            |
|----------------|-------------------------------------------------------|
| Language / UI  | Swift 6 + SwiftUI (single codebase, 3 Apple platforms)|
| Min OS         | iOS / iPadOS 18, macOS 15 *(decision: leaning iOS 18)*|
| Text engine    | TextKit 2 (bridged `UITextView` / `NSTextView`)       |
| Markdown       | apple/swift-markdown (CommonMark + GFM) → AST          |
| Persistence    | SwiftData (`ModelContainer`)                          |
| Sync           | CloudKit private database (`.private`), offline-first |
| Search         | SwiftData `#Predicate` + SQLite FTS5 (local, derived) |
| Export         | `.md` files + YAML frontmatter                        |
| Theming        | Custom `Theme` model + environment injection          |

Reference sync setup:

```swift
let store = try ModelContainer(
  for: Note.self,
  configurations: ModelConfiguration(cloudKitDatabase: .private)
)
```

---

## Core principles (apply to every change)

1. **Notes are plain Markdown** — never invent a proprietary/binary note format.
2. **Native, not web** — no web view for the editor.
3. **No server** — sync is the user's own CloudKit private DB; no accounts.
4. **Theming is decoupled from storage** — never hard-code colours; read the
   active theme. Switching themes must never risk data.
5. **Data is never trapped** — `.md` export with frontmatter is a core promise;
   content changes must round-trip losslessly.
6. **Reliability over cleverness** — sync correctness beats every other feature.

---

## Architecture notes for contributors

- **CloudKit mirroring rules:** every `@Model` property must have a default and
  every relationship must be optional (SwiftData + CloudKit requirement).
- **Body is canonical.** `Note.body` (Markdown string) is the source of truth.
  `title` and the `tags` relationship are **denormalised** and recomputed on save.
- **FTS index is a derived cache** — local-only, rebuildable, **not** synced.
- **Settings/themes are device-local** by default (optional KV-store sync), so a
  broken theme can't propagate to every device.
- Planned source layout (see `DESIGN.md §5`): `App/`, `Models/`, `Sync/`,
  `Editor/`, `Markdown/`, `Theme/`, `Features/{NoteList,Sidebar,Search,Settings}/`,
  `Export/`, `Resources/`.

---

## Working in this repo

### Git / branching

- Develop on the assigned feature branch; create it locally if needed.
- Commit with clear, descriptive messages.
- Push with `git push -u origin <branch-name>`.
- **Do not** open a pull request unless explicitly asked.
- **Never** push to a different branch without explicit permission.

### Build & test

- The v0.1 source scaffold lives in `HuskyNotes/` (App, Models, Theme, Markdown,
  Editor, Features, Export, Resources). The Xcode project is **generated** from
  [`project.yml`](project.yml) with [XcodeGen](https://github.com/yonyz/XcodeGen)
  (the `.xcodeproj` is git-ignored — never hand-edit it):

  ```bash
  brew install xcodegen          # one-time
  xcodegen generate              # writes HuskyNotes.xcodeproj
  open HuskyNotes.xcodeproj      # Xcode 16+/26; schemes: HuskyNotes-iOS, HuskyNotes-macOS
  # CI-style build without signing:
  xcodebuild -scheme HuskyNotes-macOS CODE_SIGNING_ALLOWED=NO build
  ```

- Only dependency is `apple/swift-markdown` (SPM, declared in `project.yml`).
- CloudKit (v0.2) requires an Apple Developer account, iCloud + CloudKit
  capabilities on the target, and a configured private-database container. The
  switch is staged: `PersistenceController` has the `cloudKitDatabase: .private`
  line ready and commented.

### When adding a feature

- Check it against the six core principles above.
- A feature is "done" only when it: works across all three platforms (or is
  explicitly scoped), survives an offline→online sync cycle, has at least a smoke
  test, respects the active theme, and round-trips `.md` losslessly where
  relevant (see `resources/PLAN_OF_ACTION.md §7`).
- Update the README feature checklist and the plan of action as milestones land.

---

## Conventions

- Markdown content: CommonMark + GFM only.
- **The app is completely free** — no tiers, no in-app purchases, no paywalled
  features. Do **not** add entitlement/receipt/StoreKit gating; every feature
  ships to everyone.
- Keep docs in sync: a change to architecture should update `DESIGN.md`; a change
  to scope/sequence should update `resources/PLAN_OF_ACTION.md`.

---

## TODO for this file

Update as the project matures:

- [ ] Real build / run / test commands once the Xcode project exists.
- [ ] Lint / format tooling (e.g. SwiftFormat / SwiftLint) config.
- [ ] CI pipeline notes.
- [ ] Resolved open decisions (min OS, two-way mirror, E2EE, wiki-links).
      *(Pricing resolved: completely free, no tiers / IAP.)*
