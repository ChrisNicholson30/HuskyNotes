---
title: HuskyNotes — App Store Submission Plan
created: 2026-06-06
type: project
tags:
  - huskynotes
  - app-store
  - ios
  - macos
status: active
project: HuskyNotes
---

# HuskyNotes — App Store Submission Plan

> [!summary]
> HuskyNotes is one Swift/SwiftUI codebase shipping to iOS, iPadOS, and macOS. That means **one App Store Connect record** with a separate build uploaded per platform. The flow is: make the project review-ready, create the record, upload builds from Xcode, fill in metadata, submit. First submissions fail in preparation, not at the submit button — the privacy manifest and placeholder content are the two things most likely to bite.

## Background

This is a first submission following the recently resolved Apple Developer enrolment. HuskyNotes is the polar opposite of the webview-wrapper apps Apple rejects in 2026: native SwiftUI with Vision OCR, VisionKit scanning, PencilKit, Speech transcription, and on-device AI. The review notes and screenshots should lead with that native depth — it is exactly the kind of app Apple wants on the platform.

Two unknowns — **now confirmed against the codebase (2026-06-06):**

- **`UserDefaults`: yes** (app settings, theme store, sync flag, *and* App-Group sharing for the widgets/share extension). **File timestamps: not actually used** — the only `resourceValues` reads are `.contentTypeKey`/`.fileSizeKey`, and there's no disk-space or boot-time API usage. The privacy manifest declares UserDefaults (own + app-group reasons) and File Timestamp as a safe "when in doubt" inclusion. ✅ **Manifest is wired (see below).**
- **Pricing: free, no IAP** (a core project principle — no tiers/StoreKit). So tax/banking forms are **not required**; you only need to **accept the agreements** (Phase 2).

## Phase 1 — Make the project review-ready

This is where the real work is. Do not touch App Store Connect until these are done.

> [!warning] The 2026 gotcha: privacy manifest
> Since May 2024, Apple rejects any app using "Required Reason APIs" without a `PrivacyInfo.xcprivacy` file declaring them. HuskyNotes almost certainly triggers at least two. A *missing* declaration is a hard block; declaring one you don't actually use is harmless. When in doubt, declare it.

Add a `PrivacyInfo.xcprivacy` to each target and declare the reason codes that apply:

| Required Reason API | Why HuskyNotes uses it | Reason code |
| --- | --- | --- |
| File Timestamp | Sorting and displaying note created/modified dates | `C617.1` |
| UserDefaults | App settings and preferences | `CA92.1` |
| Disk Space | Only if read anywhere (storage checks) | `E174.1` |
| System Boot Time | Only if `systemUptime` / `mach_absolute_time()` used | `35F9.1` |

The only third-party package is `apple/swift-markdown` (a parser — no Required Reason APIs / no manifest needed).

Remaining Phase 1 tasks:

- [x] **Add and configure `PrivacyInfo.xcprivacy`** — added at `Shared/PrivacyInfo.xcprivacy`, bundled into **all four targets** (app + both `.appex`; build-verified on iOS & macOS). Declares `NSPrivacyTracking=false`, **no** collected data types, and Required Reason APIs: UserDefaults (`CA92.1` own + `1C8F.1` app-group) and File Timestamp (`C617.1`). Disk-space (`E174.1`) and boot-time (`35F9.1`) **omitted — not used**.
- [x] **Confirm the build uses Xcode 16+ and the latest SDKs** — building with Xcode 26 / macOS 15 SDK 26.5. ✅
- [x] **Resolve signing/entitlement warnings** — both platforms build with **zero warnings/errors**; signed build verified under team `Y769NRY4KQ` (CN-DESIGN LTD) with iCloud + push + print entitlements.
- [ ] Strip all placeholder content — no Lorem ipsum, no empty states; every screen shows final copy and realistic data *(the welcome/demo note is real content; `ContentUnavailableView` empty states are intentional, not placeholders — do a visual pass)*
- [ ] Test the full critical path on a **physical device**: create note → scan document → run OCR → transcribe audio → trigger on-device AI → sync across devices → delete note *(can't be done from a headless build)*

## Phase 2 — Unblock the release flow early

These have lead time (banking can take days), so start them in parallel with Phase 1.

- [ ] Accept current agreements in **Agreements, Tax & Banking** (required even for a free app)
- [x] ~~Complete tax and banking forms~~ — **not required: HuskyNotes is free with no IAP.**
- [ ] Publish the privacy policy at a public URL — `huskynotes.com/privacy`

> [!tip] The privacy policy writes itself
> HuskyNotes' whole architecture is the selling point: zero servers, on-device OCR/transcription/AI, iCloud sync inside the user's own container. The policy must still state plainly what data is collected, how it's used, and how a user requests deletion — and the URL must be publicly reachable, not behind a login.

## Phase 3 — Create the App Store Connect record

At `appstoreconnect.apple.com` → My Apps → **+**. This creates the empty "shell" that the build and metadata fill later.

- [ ] Set name (HuskyNotes), primary language, bundle ID (must match Xcode exactly), SKU
- [ ] Set category to Productivity

## Phase 4 — Upload builds from Xcode

Per platform: **Product → Archive**, then in Organizer **Distribute App → App Store Connect → Upload**. Builds take 15–60 min to process before they're selectable in the record.

- [ ] Enable automatic signing (Xcode → Settings → Accounts → Apple ID), unless deliberately signing manually
- [ ] Archive and upload the iOS build
- [ ] Archive and upload the iPadOS build (if a distinct target)
- [ ] Archive and upload the macOS build
- [ ] Push through **TestFlight** first and install on own iPhone/iPad/Mac to catch signing and entitlement issues before review

## Phase 5 — Metadata and assets

Current 2026 specifications:

- [ ] **Screenshots** per device class (iPhone, iPad, Mac) — PNG, RGB, no transparency, no rounded corners (Apple masks automatically), no pricing or competitor references
- [ ] **App icon** — must read clearly at sizes as small as 29×29px
- [ ] **Privacy nutrition labels** — declare data collection; near best-case since most data never leaves the device
- [ ] **AI content disclosure** — new in 2026; answer the on-device AI question accurately (summaries/rewrites)
- [ ] Age rating, keywords, description, support URL

## Phase 6 — Submit

- [ ] Choose **manual release** to control the go-live moment
- [ ] Submit for Review

> [!note] Timeline
> Roughly 90% of submissions get a decision within 24 hours and 98% within 48 hours. Expedited review can be requested for genuine critical fixes but isn't guaranteed.

## The rejection risk that does not apply

Apple is aggressive in 2026 about minimum functionality — pure webview wrappers get rejected. HuskyNotes is native SwiftUI with deep platform integration (Vision, VisionKit, PencilKit, Speech, App Intents, on-device AI), so this works in its favour. Make the native depth obvious in screenshots and review notes.

## Next actions

- [x] Confirm `UserDefaults` / file-timestamp usage and finalise the privacy manifest — **done** (`Shared/PrivacyInfo.xcprivacy`).
- [x] Decide pricing model — **free, no IAP.**
- [ ] Draft the privacy policy for `huskynotes.com/privacy`
- [ ] Create the **Apple Distribution** cert + App Store Connect app record, then archive/upload — tooling is ready: `scripts/archive-appstore.sh` + `Config/ExportOptions-AppStore.plist` (archive step verified). Full steps in `resources/DISTRIBUTION.md` and `resources/CLOUDKIT_SETUP.md`.

> [!important] Feature scope of the build you're submitting
> This plan lists audio transcription and on-device (generative) AI, but those are **roadmap items (see `FEATURE_UPGRADE_PLAN.md`), not yet in the app.** The shipping build's native depth is: **Vision OCR, VisionKit document scanning, App Intents/Shortcuts, themed Markdown editor + reading mode, iCloud sync, PDF export/print.** Lead screenshots/review notes with those — and don't claim transcription/AI until they ship.
> Knock-on: the **AI content disclosure** is "no generative AI in this version" (OCR/Vision is recognition, not generation), and the device critical-path test is: create note → scan → OCR (searchable) → sync → delete.

## Related

- [[HuskyNotes — Architecture]]
- [[HuskyNotes — Differentiator Analysis]]
