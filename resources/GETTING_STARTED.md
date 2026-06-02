# Husky Notes — Getting Started & Resources

> Your kickoff guide: what to get, what to learn, and the exact first steps.
> Companion to [`PLAN_OF_ACTION.md`](PLAN_OF_ACTION.md) (which sequences the
> *features*) — this doc is about **starting from zero**.
> Last updated: 2026-06-02

---

## TL;DR — where to start

1. **Enrol in the Apple Developer Program** (needed for CloudKit + App Store).
2. **Install Xcode 16+** on a Mac (gives Swift 6, SwiftData, iOS 18 / macOS 15 SDKs).
3. **Create the multiplatform Xcode project** and commit the empty scaffold.
4. **Add `swift-markdown`** via Swift Package Manager.
5. **Build the v0.1 editor spike** — a TextKit 2 view bridged into SwiftUI,
   rendering Markdown live, local-only (no sync yet).

Everything else (sync, tags, export, theming) comes after the editor *feels
right*. The editor is the heart of the app; prove it first.

---

## 1. Resources you'll need

### Accounts & services

| Resource | Required for | Cost | Notes |
|----------|--------------|------|-------|
| **Apple Developer Program** | CloudKit, app capabilities, TestFlight, App Store | **£79 / $99 per year** | A *free* Apple ID can build to the simulator and your own device, but **CloudKit sync needs the paid membership**. |
| **iCloud account(s)** | Testing CloudKit sync | Free | You'll want at least two signed-in devices (or a 2nd Apple ID) to verify cross-device sync. |
| **GitHub repo** | Source control, CI | Free | Already set up (`chrisnicholson30/huskynotes`). |

### Hardware

| Resource | Required? | Notes |
|----------|-----------|-------|
| **Mac (Apple Silicon)** | **Yes** | Xcode only runs on macOS. Needs macOS 15+ to build the macOS 15 target. |
| **iPhone on iOS 18** | Strongly recommended | Simulator can't fully test CloudKit sync or Face ID / Touch ID. |
| **iPad on iPadOS 18** | Recommended | Validates the three-platform promise (split view, pointer/keyboard). |
| **A 2nd device or 2nd simulator** | For sync testing (v0.2+) | Two endpoints signed into the same iCloud account proves sync. |

### Software / tooling

| Tool | Purpose | Notes |
|------|---------|-------|
| **Xcode 16+** | IDE, build, SDKs, simulators | Free from the Mac App Store. Brings Swift 6, SwiftData, iOS 18 / macOS 15. |
| **swift-markdown** | CommonMark + GFM → AST | SPM dependency: `https://github.com/apple/swift-markdown`. |
| **SwiftLint** *(optional)* | Linting | Add early so style is consistent from day one. |
| **SwiftFormat** *(optional)* | Auto-formatting | Pairs well with SwiftLint. |
| **SF Symbols app** | Icon glyphs | Free from Apple; for sidebar/toolbar icons. |
| **CloudKit Dashboard** | Inspect synced records | Web tool at `icloud.developer.apple.com` (needs the paid account). |

### Dependencies (Swift Package Manager)

For v0.1 you need exactly **one** package:

```
apple/swift-markdown   // CommonMark + GFM parser → AST
```

Everything else (SwiftData, CloudKit, TextKit 2, SwiftUI) is **built into the
SDK** — no third-party packages required. Keeping the dependency surface tiny is
deliberate (reliability over cleverness).

---

## 2. Skills / learning resources

The stack is mostly first-party Apple frameworks. The one genuinely hard part is
**TextKit 2** — budget the most learning time there.

| Topic | Why it matters | Where to learn |
|-------|----------------|----------------|
| **SwiftUI** | The whole UI layer | Apple's *SwiftUI Tutorials* + the SwiftUI docs. |
| **SwiftData** | Persistence + the CloudKit bridge | WWDC: "Meet SwiftData", "Model your schema with SwiftData", "What's new in SwiftData". |
| **SwiftData + CloudKit** | Sync with zero hand-rolled engine | Apple docs on `ModelConfiguration(cloudKitDatabase:)` / `NSPersistentCloudKitContainer`. |
| **TextKit 2** ⭐ | The live themed editor — the app's core | WWDC: "Meet TextKit 2"; docs on `NSTextLayoutManager`, bridging `UITextView`/`NSTextView`. |
| **Bridging UIKit/AppKit into SwiftUI** | TextKit views aren't native SwiftUI | `UIViewRepresentable` / `NSViewRepresentable` docs. |
| **swift-markdown** | Parsing notes to an AST you render | The package README + DocC docs on the repo. |
| **CloudKit basics** | Mental model for the sync layer | Apple's CloudKit docs + the CloudKit Dashboard. |

> Tip: you don't need to master CloudKit's low-level API — SwiftData wraps it.
> But you *do* need to internalise the **mirroring rules** (every `@Model`
> property defaulted, every relationship optional) before writing the models.

---

## 3. Day-zero environment setup

Concrete steps to go from "nothing" to "buildable empty app":

1. **Enrol** in the Apple Developer Program (approval can take 24–48h — start now).
2. **Install Xcode 16+** and its iOS 18 / macOS 15 simulators.
3. **Create the project**: Xcode → *New Project* → *Multiplatform App*.
   - Name: `HuskyNotes`. Storage: **SwiftData**. Host in CloudKit: leave **off**
     for v0.1 (turn on in v0.2).
   - Language: Swift. Interface: SwiftUI. Minimum deployments: iOS 18, macOS 15.
4. **Add capabilities** (Signing & Capabilities tab), even if unused until v0.2:
   iCloud → CloudKit, plus a CloudKit container (`iCloud.app.huskynotes`).
5. **Lay out the folder structure** to match `DESIGN.md §5`:
   `App/ Models/ Sync/ Editor/ Markdown/ Theme/ Features/ Export/ Resources/`.
6. **Add `swift-markdown`** via *File → Add Package Dependencies*.
7. **(Optional) Add SwiftLint + SwiftFormat** and a basic config.
8. **Commit** the scaffold to a feature branch and push.
9. **(Optional) CI**: a GitHub Actions workflow on macOS that runs
   `xcodebuild build` + `xcodebuild test`.

At the end of day zero you should have an empty multiplatform app that builds and
launches on the iOS and macOS simulators.

---

## 4. First sprint — v0.1 "Editor spike"

Goal: **prove the editor feels right.** Local-only, one theme, no sync. Maps to
`PLAN_OF_ACTION.md` v0.1.

Suggested order of work:

1. **App shell** — `@main`, a `ModelContainer` (local, no CloudKit yet), a
   `NavigationSplitView` placeholder.
2. **Minimal `Note` model** — just `id`, `title`, `body`, `createdAt`,
   `modifiedAt` for now (full model lands in v0.2). Defaults on every property.
3. **TextKit 2 editor view** — wrap a `UITextView`/`NSTextView` (backed by
   `NSTextLayoutManager`) in a `UIViewRepresentable`/`NSViewRepresentable`.
4. **Live Markdown rendering** — parse `body` with `swift-markdown`, walk the
   AST, apply styling to an `AttributedString` as the user types.
5. **One hard-coded theme** — Blue Husky palette from `DESIGN.md §10`, wired so
   the editor reads colours from a theme object (not literals) from day one.
6. **Smoke test** — typing a heading, list, and code block renders live.

**Exit criteria:** typing renders headings/lists/code blocks live and feels good;
no proprietary format, clean `.md` underneath.

> ⚠️ **Biggest risk:** TextKit 2 live styling-while-typing is fiddly (selection,
> performance on large docs, caret behaviour). If it fights you, prototype the
> editor *in isolation* first before wiring it to SwiftData.

---

## 5. Cost & time summary

| Item | One-off | Recurring |
|------|---------|-----------|
| Apple Developer Program | — | **£79 / $99 per year** |
| Xcode + SDKs + simulators | Free | — |
| swift-markdown (only dependency) | Free | — |
| Mac / iPhone / iPad | Hardware you supply | — |
| **Total software cost to start** | **£0** | **£79/yr** (only when you need CloudKit/App Store) |

You can build and test the **entire v0.1 editor spike for free** on the simulator
with a personal Apple ID — the £79/yr only becomes necessary at **v0.2 (sync)**.

---

## 6. Gotchas to know before you start

- **CloudKit ≠ free Apple ID.** Sync work (v0.2) is blocked until the paid
  membership is active — enrol early.
- **CloudKit mirroring constraints shape the data model.** Every `@Model`
  property needs a default; every relationship must be optional. Design the
  models with this baked in (see `DESIGN.md §4`) — retrofitting is painful.
- **Simulator can't prove sync or biometrics.** Plan on at least one real device.
- **TextKit 2 is the long pole.** It's where the app lives and dies; give it the
  most runway and a throwaway prototype if needed.
- **Keep dependencies near-zero.** Resist pulling in Markdown-UI / editor
  libraries — the native text engine *is* the product.

---

## 7. Your next three actions

1. **Today:** start the Apple Developer Program enrolment (it has a lead time).
2. **This week:** install Xcode 16, create the multiplatform project, push the
   scaffold.
3. **Next:** spike the TextKit 2 editor in isolation, then fold it into the app.
