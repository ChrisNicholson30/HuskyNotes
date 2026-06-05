# Husky Notes — Feature Upgrade Plan (post‑1.0 roadmap)

> Companion to [`FEATURE_PLAN.md`](FEATURE_PLAN.md) and [`BUILD_PLAN.md`](BUILD_PLAN.md).
> Turns the competitive gap analysis (below, §1) into a sequenced, principle‑safe
> implementation plan. **Status: planning.** Last updated: 2026‑06‑06.
>
> **Scope note:** this is the roadmap *after* the imminent v1.0 download release.
> Nothing here blocks that launch. Effort key: **S** ≈ days · **M** ≈ 1–2 wks ·
> **L** ≈ 3–4 wks · **XL** ≈ multi‑month / flagship.

---

## 0. Guiding constraints (carried from the core principles)

Every upgrade must hold the project's non‑negotiables (see `CLAUDE.md`):

1. **`.md` stays canonical.** `Note.body` is always plain CommonMark/GFM. Structured
   data lives in **YAML frontmatter** (we already have `Frontmatter.swift`); rich
   rendering is presentation‑only; derived indexes (OCR text, embeddings) are
   **local caches**, never the source.
2. **Round‑trips losslessly.** Export → Obsidian → re‑import must survive. New syntax
   must be portable (frontmatter, `![[embeds]]`, `^block-ids`), never proprietary blobs.
3. **Native, not web** (for the *editor*). A Safari web‑clipper extension and
   LinkPresentation cards are fine — that rule is about the editing surface.
4. **No server.** Sync is the user's own CloudKit **private** DB. Collaboration must
   ride **CloudKit sharing** (`CKShare`), not a central service.
5. **Local‑first & private.** On‑device AI/OCR/transcription only. No content leaves
   the device except (a) the user's own iCloud and (b) explicit, opt‑in network calls
   (link previews, web fetch) — never for locked notes.
6. **Completely free.** No tiers/IAP. Every feature ships to everyone, so cost‑bearing
   server features are out unless they're zero‑marginal‑cost (on‑device / user's iCloud).
7. **Reliability over cleverness.** Rich/interactive surfaces land in **Read mode**
   first; in‑editor inline widgets (`NSTextAttachmentViewProvider`) are an explicit,
   later, device‑iterated phase (the shared "Phase ✦" from `FEATURE_PLAN.md`).

### Three hard tensions, decided up front
- **Email‑to‑note needs a server** → conflicts with #4/#6. **Decision:** ship it as a
  *Mail share‑extension / Shortcut* (forward via the OS, zero infra), not a hosted
  address. A hosted relay is out unless the project ever takes funding. (§3.5)
- **Binary inputs (ink, audio, scans) aren't Markdown** → they become **attachments**
  (like images today); their *recognized text/transcript* is written into the body as
  Markdown. The canonical note stays plain text. (§3.1, §3.3, §6.3)
- **Apple‑Intelligence LLM (Foundation Models) is iOS 26 / macOS 26 + Apple‑Silicon
  only**, but our floor is iOS 18 / macOS 15. **Decision:** gate the LLM features by
  `availability` + a runtime capability check, and provide **NaturalLanguage** /
  extractive fallbacks so older devices degrade gracefully rather than lose the feature. (§5)

---

## 1. Gap analysis (source)

*(Preserved from the original brief.)*

**Where Bear and Obsidian fall short.** Bear is beautiful but shallow: no real
database/structured data, weak web clipping, no built‑in OCR, limited collaboration, no
API. Obsidian is powerful but bare: no native OCR, clunky mobile capture, no first‑class
web clipper, no built‑in audio transcription, bolted‑on collaboration, and structured
data means wrestling with Dataview. The gaps cluster around **capture, structure,
intelligence, and collaboration.**

- **From Evernote:** best‑in‑class OCR in images/PDFs; document scanner with edge
  detection; a real web clipper (article/simplified/full‑page); email‑to‑note.
- **From Notion:** databases / structured properties with table/board/calendar/gallery
  views; synced blocks / transclusion; slash‑command palette; relations & rollups.
- **The real opportunity (neither has):** on‑device AI on Apple Silicon (summarize,
  semantic search, "ask your notes", auto‑tag); audio capture + on‑device transcription;
  semantic/vector search; handwriting + Apple Pencil with searchable ink; Live
  Activities / widgets / App Intents + Shortcuts; smart AI‑suggested backlinks.

---

## 2. Epics, effort & dependencies

| # | Epic | Flagship items | Effort | Depends on |
|---|------|----------------|--------|------------|
| A | **Capture** | OCR, scanner, audio+transcription, web clipper | M–L | FTS index (search) |
| B | **Structure** | Properties → Database views, slash palette, transclusion, relations | XL | Frontmatter, swift‑markdown |
| C | **Intelligence** (the wedge) | Semantic search, on‑device AI, AI backlinks | L–XL | Embeddings store; A (OCR text) |
| D | **Platform & input** | App Intents/Shortcuts, Live Activities, handwriting | M | Existing widgets/App Group |
| E | **Collaboration** | CloudKit sharing (`CKShare`) | L | **CloudKit sync (v0.2)** |

Two cross‑cutting prerequisites unlock most of the above and should be built early:
- **P0a — FTS5 search index** (already planned in `BUILD_PLAN`): a local, rebuildable,
  **not‑synced** full‑text index. OCR text and transcripts feed it; semantic search sits
  beside it.
- **P0b — Local "derived store" pattern**: one place/policy for non‑synced derived data
  (FTS rows, OCR text, embeddings, link‑metadata cache). Mirrors the existing
  "FTS is a derived cache" rule so none of it pollutes `.md` or CloudKit.

---

## 3. Capture epic

### 3.1 OCR inside images & PDFs  ·  Effort M  ·  Risk Low
- **Goal:** search text inside attached photos/scans/PDFs; optionally insert recognized
  text into the note.
- **Frameworks:** Vision — `VNRecognizeTextRequest` (`.accurate`, language‑correction,
  supports handwriting); PDFKit to rasterize PDF pages for OCR.
- **Representation / principles:** add `Attachment.recognizedText: String? = nil`
  (CloudKit‑safe default) — a **derived cache**, computed on import, fed into FTS. The
  `.md` is untouched unless the user taps **"Insert recognized text"** (then it's normal
  Markdown). OCR runs **on‑device**, off the main actor, debounced after import.
- **UI:** a progress chip on the attachment; recognized text appears in search hits;
  context action to copy/insert.
- **Phases:** P1 image OCR + search integration · P2 PDF page OCR · ✦ select‑text overlay
  on the image viewer.
- **Depends on:** P0a FTS.

### 3.2 Document scanner  ·  Effort S–M  ·  Risk Low
- **Goal:** camera → deskewed, cleaned multi‑page scan saved as a PDF attachment, auto‑OCR'd.
- **Frameworks:** `VNDocumentCameraViewController` (iOS/iPadOS) — does edge detection,
  deskew, multipage. macOS: "Continuity Camera" import or file import (no direct API).
- **Representation:** produces a PDF `Attachment` (reuses §3.1 OCR + the existing
  attachment/export pipeline → `_attachments/`). Body gets the standard
  `[📄 scan.pdf](_attachments/…)` reference.
- **UI:** "Scan Document" toolbar/Quick‑Capture action (iOS only; hidden on macOS).
- **Depends on:** §3.1 for the searchable text.

### 3.3 Audio capture + on‑device transcription  ·  Effort L  ·  Risk Med
- **Goal:** record a memo/meeting; get a **timestamped transcript linked to the audio**.
- **Frameworks:** `AVAudioRecorder` (capture); Speech — `SFSpeechRecognizer`
  with `requiresOnDeviceRecognition = true` (floor), and the newer **`SpeechAnalyzer` /
  `SpeechTranscriber`** (iOS 26+) for higher‑quality/long‑form, gated by availability.
- **Representation:** audio file → `Attachment` (m4a). Transcript written into the body as
  Markdown (e.g. a collapsible section or timestamped list `- [00:12] …`), with the audio
  linked via `_attachments/`. Tapping a timestamp seeks the player. Canonical = Markdown.
- **UI:** record control in Quick Capture + a player chip in the editor/Read mode.
- **Phases:** P1 record → attach → transcribe → insert transcript · P2 timestamp↔audio
  seek · ✦ speaker segmentation.
- **Risk:** mic permission UX; long recordings/memory; on‑device model availability per
  locale.

### 3.4 Web clipper (Safari extension)  ·  Effort L  ·  Risk Med
- **Goal:** clip a page as clean **Markdown** (article / simplified / full‑page / selection),
  not a dump.
- **Mechanism:** a **Safari Web Extension** target (shares the App Group, like the existing
  Share Extension → `SharedInbox`). JS does Readability‑style article extraction in‑page;
  convert HTML→Markdown (Turndown‑style) in the extension; drop into the App‑Group inbox;
  the app drains it into a Note (reuses today's `drainSharedInbox()` path).
- **Representation:** pure Markdown + frontmatter (`source:` URL, `clipped:` date). Images
  optionally downloaded as attachments (opt‑in, since it's a network fetch).
- **Principles:** the extension is web tech but **outside the editor** — allowed. Network
  fetch only on the user's explicit clip action.
- **Phases:** P1 selection + article→Markdown via the inbox · P2 image capture +
  simplified/full‑page modes · ✦ iOS Share‑sheet parity polish.

### 3.5 Email‑to‑note (reframed)  ·  Effort S  ·  Risk Low (scope‑limited)
- **Decision (per §0):** **no hosted address** (would need a server, breaks #4/#6).
  Instead: Mail's **Share sheet → Husky Notes** (already supported via the Share
  Extension) and a **Shortcuts/App Intent** "Save Email to Husky" so a Mail rule or manual
  share forwards the message into the vault. Documents the limitation honestly.
- **Depends on:** §6.1 App Intents for the Shortcut path.

---

## 4. Structure epic — the biggest differentiator

This is where Husky beats both rivals *and* stays Markdown‑native. Build it bottom‑up:
**properties → views → relations → transclusion**, with the slash palette as the entry point.

### 4.1 Typed properties (frontmatter)  ·  Effort M  ·  Risk Med  ·  **foundation**
- **Goal:** notes carry typed fields — `status` (select), `due` (date), `priority`
  (number), `tags`, `relation` — editable in a properties panel.
- **Representation:** standard **YAML frontmatter** at the top of `Note.body` (Obsidian‑
  compatible). Extend `Frontmatter.swift` to read/write typed values; keep `Note.body`
  canonical (the panel is just a structured editor over the YAML). Denormalize a small,
  queryable subset into SwiftData (like `title`/`tags` today) for fast filtering — a
  derived index, recomputed on save.
- **UI:** a collapsible **Properties** panel above the editor (and in Read mode).
- **Risk:** YAML edge cases; keeping the denormalized index in sync; not corrupting bodies
  that already start with `---`.

### 4.2 Database views (table / board / calendar / gallery)  ·  Effort XL  ·  Risk Med
- **Goal:** Notion‑style views over a **query** (folder/tag/property filter) — the records
  *are notes*.
- **Representation:** a view is a saved definition — a special note or a SwiftData
  `SavedView` model holding `{ filter, sort, view-type, visible columns, group-by }`.
  Records remain plain‑`.md` notes; nothing is trapped. (This is the Obsidian "Bases" /
  Dataview idea, but first‑class and visual.)
- **UI:** new sidebar item type "Database"; SwiftUI `Table` (macOS/iPad), board (lanes by a
  select property — drag to change `status`), calendar (by date property), gallery (cards
  with cover image).
- **Phases:** P1 **Table view** over a filter + inline‑editable cells (writes back to
  frontmatter) · P2 Board (Kanban) · P3 Calendar + Gallery.
- **Depends on:** §4.1 properties.

### 4.3 Slash‑command palette  ·  Effort M  ·  Risk Med
- **Goal:** type `/` in the editor → fuzzy‑searchable menu to insert blocks (heading, list,
  todo, table, code, callout, date, link, embed…), keyboard‑driven.
- **Mechanism:** detect `/` at a word boundary in the text‑view delegate; present a SwiftUI
  popover anchored at the caret rect; selection runs an existing `MarkdownCommand` (reuses
  all current formatting logic) and removes the `/query`.
- **Risk:** caret‑rect anchoring across UIKit/AppKit; not interfering with a literal `/`.

### 4.4 Transclusion / synced blocks  ·  Effort L  ·  Risk Med
- **Goal:** embed another note or a block: `![[Note]]`, `![[Note#Heading]]`, `![[Note#^blockid]]`.
- **Representation:** Obsidian‑compatible embed syntax in the body (round‑trips). Block ids
  are `^id` markers appended to a line. **Read mode renders the resolved content inline**;
  the editor shows the reference (✦ inline live‑embed later). "Synced" = it's a *reference*,
  so editing the source updates every embed automatically.
- **Phases:** P1 read‑mode transclusion of whole notes/headings · P2 `^blockid` refs +
  autocomplete · ✦ editable inline embed.
- **Depends on:** a note/heading resolver (also needed for wiki‑links — see §10).

### 4.5 Relations & rollups  ·  Effort L  ·  Risk Med
- **Goal:** a `relation` property links notes as records; **rollups** aggregate across them
  (count, sum, latest) in a database view.
- **Representation:** relation stored in frontmatter as wiki‑links (`related: ["[[A]]","[[B]]"]`);
  rollups are computed in the view layer (not stored). Reuses §4.1/§4.2.
- **Depends on:** §4.1, §4.2, §4.4 resolver.

---

## 5. Intelligence epic — the on‑device wedge

All private, local, free. Provide graceful fallbacks (see §0 tension #3).

### 5.1 Semantic / vector search  ·  Effort L  ·  Risk Med  ·  **infra for the rest**
- **Goal:** "find notes about X" by meaning, not keywords; blends with FTS.
- **Frameworks:** NaturalLanguage `NLContextualEmbedding` (sentence embeddings, on‑device,
  iOS 17+) — no LLM required, so it works on the iOS‑18 floor.
- **Representation:** a local, **not‑synced** `Embedding` store (per note/chunk vector),
  rebuildable like FTS (P0b). Cosine‑similarity search; recompute on edit (debounced).
- **UI:** a "Related"/"semantic" toggle in Search; ranks alongside keyword hits.
- **Depends on:** P0a/P0b.

### 5.2 On‑device AI: summarize · ask‑your‑notes · auto‑tag  ·  Effort XL  ·  Risk High
- **Goal:** local summarization, Q&A over your notes (RAG), suggested tags — all offline.
- **Frameworks:** **Foundation Models** (Apple‑Intelligence on‑device LLM, iOS 26+/Apple
  Silicon) for generation; retrieval via §5.1 embeddings. **Fallback** on older OS:
  extractive summarization + keyword auto‑tag via NaturalLanguage (no generative text).
- **Representation:** outputs are **suggestions** the user accepts into Markdown (a summary
  block, tag chips) — never silently mutating the body. "Ask your notes" is a transient
  panel; answers cite source notes.
- **UI:** a per‑note "Summarize", a global "Ask", an auto‑tag suggestion row.
- **Gating:** `if #available` + `SystemLanguageModel.availability` capability check; hide or
  fall back where unsupported.
- **Risk:** model availability/perf; prompt quality; must be clearly **on‑device** in UX.

### 5.3 AI‑suggested backlinks  ·  Effort M  ·  Risk Med
- **Goal:** surface related notes you didn't link, from semantic similarity.
- **Mechanism:** reuse §5.1 embeddings to rank candidates; show a "You might link…" section
  in Read mode / a sidebar; one‑tap inserts a wiki‑link.
- **Depends on:** §5.1.

---

## 6. Platform & input epic — the Apple moat

### 6.1 App Intents / Shortcuts / Siri  ·  Effort M  ·  Risk Low
- **Goal:** "Create note", "Append to note", "Search notes", "Save email/clip" as Shortcuts
  + Siri phrases; donate intents for suggestions.
- **Frameworks:** App Intents (`AppIntent`, `AppShortcutsProvider`). Reuses the existing
  `QuickCapture`/App‑Group plumbing.
- **Payoff:** also unblocks §3.5 (email), Action‑button capture, automation.

### 6.2 Live Activities + expanded widgets  ·  Effort M  ·  Risk Low
- **Goal:** a recording/transcription Live Activity (Dynamic Island), and richer widgets
  (recent notes, a specific database view, quick‑capture variants).
- **Frameworks:** ActivityKit + WidgetKit (we already ship widgets).
- **Depends on:** §3.3 for the recording activity.

### 6.3 Handwriting + Apple Pencil (searchable ink)  ·  Effort L  ·  Risk Med
- **Goal:** sketch/handwrite on iPad; ink is **searchable** via recognition.
- **Frameworks:** PencilKit (`PKCanvasView`/`PKDrawing`); Vision handwriting recognition
  (or PencilKit's). macOS: view‑only (no pencil).
- **Representation (per §0 tension #2):** the `PKDrawing` is stored as an **attachment**
  (binary, like an image); the **recognized text** is indexed (FTS, §3.1) and optionally
  inserted into the body. The note stays Markdown; the sketch is an embedded image.
- **Phases:** P1 ink canvas → image attachment + recognition → search · ✦ inline editable
  ink region.

---

## 7. Collaboration epic

### 7.1 CloudKit sharing (`CKShare`)  ·  Effort L  ·  Risk High  ·  Depends on sync (v0.2)
- **Goal:** share a note/folder with another iCloud user, edit together — **no server**
  (rides the user's iCloud).
- **Mechanism:** move shared records into a shared CloudKit zone; `CKShare` +
  `UICloudSharingController`; SwiftData + CloudKit shared‑database support.
- **Hard prerequisite:** CloudKit **sync must land first** (currently v0.2, not yet
  shipped). Conflict handling and per‑record sharing are the real work.
- **Note:** this is the most complex epic and the furthest out; keep it explicitly post‑sync.

---

## 8. Recommended sequence (milestones)

Ordered by **value ÷ effort**, dependency‑correct, and principle‑safe:

- **v1.1 — Capture quick wins. ✅ shipped (build‑verified, both platforms).**
  - **OCR (3.1)** — `OCRService` (Vision, images + PDFs incl. embedded text layer) +
    `AttachmentOCR` writing to `Attachment.recognizedText` (the derived‑cache exemplar for
    P0b); recognized text is folded into `NoteSearch`, so search now finds words inside
    scans/photos/PDFs. OCR runs on‑device, off the main actor, on every attachment import
    (editor, photo picker, scanner, share‑extension inbox).
  - **Document scanner (3.2)** — `DocumentScannerView` (VisionKit `VNDocumentCameraViewController`,
    iOS‑only) → assembles pages into a PDF → imports + OCRs via the shared path; "Scan
    Document" toolbar button. Added `NSCameraUsageDescription`.
  - **App Intents/Shortcuts (6.1)** — `CreateNoteIntent`, `AppendToLastNoteIntent`,
    `HuskyNotesShortcuts` (Siri phrases). Write straight to the shared SwiftData container.
  - **P0a (FTS5) — deferred (intentional).** The functional unlock (searchable OCR/transcripts)
    is delivered via the existing engine extended to include `recognizedText`; the linear
    scan is fast enough for realistic libraries. A dedicated SQLite FTS5 backend remains a
    later, device‑verified perf optimisation (the `NoteSearch` grammar is unchanged, so it
    can slot in behind it).
  - **Needs on‑device QA** before release: camera scanner flow, OCR accuracy/perf, and the
    Siri/Shortcuts phrases (these can't be verified from a headless build).
- **v1.2 — Structure foundation.** **Properties (4.1)** + **Slash palette (4.3)** +
  **read‑mode Transclusion (4.4 P1)**. Sets up the differentiator.
- **v1.3 — Intelligence base.** **Semantic search (5.1)** + **AI backlinks (5.3)** (both
  work on the iOS‑18 floor via NaturalLanguage).
- **v1.4 — Audio & web.** **Audio + transcription (3.3)** + Live Activity (6.2) + **Web
  clipper (3.4)**.
- **v2.0 — Databases.** **Database views (4.2)** + **Relations/rollups (4.5)** — the
  flagship "Notion, but Markdown‑native" release.
- **v2.x — Generative AI & Pencil.** **Foundation‑Models features (5.2)** as devices adopt
  iOS 26+ · **Handwriting (6.3)**.
- **v3.0 — Collaboration.** **CloudKit sharing (7.1)**, once sync is mature.

(Each item still follows the per‑feature **P1 → P2 → ✦ stretch** ladder; ✦ inline‑editor
widgets for tables/files/links/embeds remain one shared, device‑iterated effort per
`FEATURE_PLAN.md`.)

---

## 9. Definition of done (per feature)

A feature ships when it: works on **all targeted platforms** (or is explicitly scoped — e.g.
scanner/Pencil are iOS‑only); **respects the active theme**; keeps **`.md` canonical and
round‑trippable** (structured data in frontmatter, derived data in local caches); runs
**on‑device / opt‑in for any network**; **excludes locked notes** wherever content is
exposed or sent; **degrades gracefully** where an OS capability is unavailable; and has at
least a **smoke test** for any parsing/transform/index logic.

---

## 10. Known gaps to close alongside this roadmap

These existing rough edges intersect the plan and are cheap to fix early:
- **Wiki‑links (`[[…]]`) and underline (`<u>`) render as literal text** today. A
  note/heading **resolver + wiki‑link rendering** is a prerequisite for Transclusion (4.4)
  and Relations (4.5) — do it there. Underline should either render or be removed from the
  tools.
- **Wide tables clip** in PDF/print — fold into Tables ✦ / export polish.
