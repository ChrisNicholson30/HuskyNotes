# Husky Notes — Feature Plan: Tables, File/PDF Viewer, Link-with-Thumbnail

> Companion to [`BUILD_PLAN.md`](BUILD_PLAN.md). Scopes three richer-content
> features against the **current** codebase. Status: **planning** ·
> Last updated: 2026-06-05

---

## 0. Guiding constraints (carried from core principles)

Every feature below must hold the line on the project's non-negotiables:

1. **`.md` stays canonical.** `Note.body` is always plain CommonMark/GFM. Tables
   are standard GFM; files are markdown links/embeds resolving to `_attachments/`;
   links are plain URLs. **Rich rendering is presentation-only** — never stored in
   the body.
2. **Round-trips losslessly.** Export → Obsidian → re-import must survive. So the
   on-disk markdown for each feature uses portable syntax (no proprietary blobs in
   the text).
3. **Reliable over clever.** The live TextKit 2 editor can't dependably host
   complex inline widgets (we already hit this with checkbox image attachments).
   So **Read mode** (`MarkdownReadingView`) is the home for rich rendering;
   in-editor inline widgets are an explicit, later, higher-risk phase.
4. **Theme + cross-platform.** iOS/iPadOS + macOS, all colours from the active
   `Theme`.

### The shared architectural fork: inline widgets

All three features ultimately want an **inline widget inside the editor**
(Obsidian "Live Preview"). The native mechanism is TextKit 2's
`NSTextAttachmentViewProvider` (embed a UIView/NSView at a text position). It is
powerful but fiddly — sizing, the active-line "reveal source" behaviour, caret
math, and re-layout on every keystroke. **Recommendation:** ship each feature in
**Read mode first** (reliable, verifiable), then attempt the in-editor inline
widget as a dedicated, device-iterated follow-up. This doc marks those as
**Phase ✦ (stretch)**.

---

## 1. Tables

### Current state
- **Editor** (`MarkdownStyler.visitTable`): GFM table block rendered in the
  monospaced font so hand-padded pipes line up. Source stays `| a | b |`.
- **Read mode** (`MarkdownReadingView.tableView`): real SwiftUI `Grid` — bold
  header, themed surface. ✅ already a real grid.

### Goal / UX
Make tables pleasant to **author and edit**, and polish the rendered grid.

### Markdown representation
Standard **GFM tables** (already parsed by swift-markdown — `Markdown.Table`,
`.head`, `.body`, `.columnAlignments`). No new syntax, no model change.

### Phases
- **P1 — Insert + Read-mode polish** *(low risk)*
  - `MarkdownCommand.table` → inserts a starter skeleton:
    ```
    | Column | Column |
    | --- | --- |
    | | |
    ```
    Wire into the macOS **Format** menu and the iOS `FormatAccessoryView`.
  - Read-mode grid: honour `table.columnAlignments` (leading/center/trailing),
    add subtle row separators / zebra striping, and wrap the `Grid` in a
    horizontal `ScrollView` so wide tables don't clip on iPhone.
  - **Exit:** insert a table from the toolbar; it renders aligned + scrollable in
    Read mode across all three platforms.
- **P2 — In-editor authoring aids** *(medium)*
  - **Auto-format** a pipe table (compute per-column widths, re-pad cells) — run
    on a `Format → Tidy Table` command and on blur, **never per-keystroke**.
    Pure string transform; body stays canonical, just neater.
  - **Cell navigation:** Tab / Shift-Tab moves between cells; Return at the last
    row appends a new row (intercept key input in the text view's delegate).
  - **Exit:** Tab walks cells; Tidy Table aligns columns without changing content.
- **Phase ✦ — Inline live table widget** *(stretch)*
  - Replace the table source block with an interactive `NSTextAttachmentViewProvider`
    grid when the caret isn't in it (reveal source on entry). Needs device
    iteration.

### Risks
Key interception (Tab/Return) must not break normal typing; auto-align must never
corrupt cell content; very wide tables on compact width.

---

## 2. Insert a File / PDF Viewer

### Current state
- `Attachment` model: `id`, `filename`, `@Attribute(.externalStorage) data`,
  `note`, `createdAt`. Stored as a CloudKit asset (external storage).
- `AttachmentsBar`: shows image thumbnails; non-images get a generic `doc` glyph.
- Insert is **images only** (`.fileImporter(allowedContentTypes: [.image])`).
- `MarkdownExporter` writes attachments to `_attachments/`.

### Goal / UX
Attach **any file** (PDFs especially), see it in a **viewer**: PDFs in a real
PDF reader, other types via Quick Look.

### Markdown representation (round-trip)
Insert a portable reference into the body so an exported vault resolves it:
```
[📄 report.pdf](_attachments/report.pdf)
```
(Obsidian-compatible relative link.) The app additionally tracks the file
relationally via `note.attachments`, so the viewer doesn't depend on parsing the
body. Embeds (`![[report.pdf]]`) are a P2 nicety.

### Data model
Add to `Attachment` (CloudKit-safe — defaulted, optional):
- `var contentType: String? = nil` — the UTI (e.g. `com.adobe.pdf`) for correct
  preview routing and icons.
- (optional) `var byteCount: Int = 0` — for display.

### Technical approach
- **Insert:** broaden the importer to `[.pdf, .item]` (or `[.data]`); store
  `data`, `filename`, `contentType`. Add a distinct **"Insert File"** toolbar
  button (alongside "Insert Image").
- **Viewer** (tap an attachment chip):
  - **PDF →** PDFKit `PDFView` wrapped in `UIViewRepresentable`/`NSViewRepresentable`,
    presented in a sheet (iOS) / detail or window (macOS).
  - **Other →** Quick Look: `QLPreviewController` (iOS) / `QLPreviewPanel` (macOS).
    Quick Look needs a **file URL**, so write the attachment's `data` to a temp
    file first (cleaned up after).
- `PlatformImage`-style abstraction for the previewer; PDFKit is available on
  both platforms.

### Phases
- **P1 — Attach + view** *(medium)*: any-file import → `Attachment` with
  `contentType`; `AttachmentsBar` shows typed chips (PDF/file icon + name + size);
  tap → PDFKit (PDF) or Quick Look (other) via a temp file. Export already works.
  **Exit:** attach a PDF, open it in the in-app reader on iOS + macOS; it exports
  to `_attachments/` and round-trips.
- **P2 — Body embeds**: insert `[📄 name](_attachments/name)` (or `![[name]]`) at
  the caret; Read mode renders a tappable file chip; resolve by filename on import.
- **Phase ✦ — Inline preview**: first-page PDF thumbnail in the bar / inline file
  card in the editor.

### Risks / notes
- Large PDFs: external storage handles size, but watch CloudKit asset limits and
  sync time.
- Quick Look requires an on-disk URL (temp file); ensure cleanup and sandbox temp
  access (macOS sandbox already grants temp).
- Locked notes: exclude attachment previews when the note is locked (consistent
  with the mirror-exclusion rule).

---

## 3. Insert a Link with Thumbnail

### Current state
- `MarkdownCommand.link` wraps a selection as `[text](url)`.
- Links render as themed, underlined text in editor + Read mode. No preview card.

### Goal / UX
Turn a URL into a **rich preview card** (title, description, image, favicon) —
like Notes/iMessage — using Apple's **LinkPresentation** framework.

### Markdown representation (round-trip)
The body keeps a **plain markdown link / bare URL** (canonical, portable). The
card is **presentation-only**, rendered in Read mode. Nothing proprietary lands
in `.md`.

### Technical approach
- **Metadata:** `LPMetadataProvider.startFetchingMetadata(for:)` (async) →
  `LPLinkMetadata` (title, imageProvider, iconProvider).
- **Render:** `LPLinkView(metadata:)` wrapped in `UIViewRepresentable`/`NSViewRepresentable`;
  in Read mode, detect link-only paragraphs (and/or all links) and show the card.
- **Cache:** a `LinkMetadataCache` — `NSCache` in memory + on-disk cache keyed by a
  URL hash (`LPLinkMetadata` is `NSSecureCoding`). **Local-only, not synced** (a
  derived cache, like FTS). Avoids refetching and offline gaps.
- **Insert flow:** when the user inserts/pastes a URL, keep inserting the plain
  link; the card appears in Read mode. (Inline editor card = Phase ✦.)

### ⚠️ Privacy (important — affects the product's promise)
Fetching link metadata makes a **network request to the linked site**. The app
promises "no analytics on note content" and "we never see a word you write" —
this is still true (the request goes to the third-party site, not to us), but it
*does* contact external servers based on note content. Therefore:
- Add a Settings toggle **"Fetch link previews"** (Storage/Privacy), **default
  OFF** or first-run prompt, clearly explained.
- Never fetch for **locked** notes.
- Only fetch in Read mode / on explicit action, never silently in the background.

### Phases
- **P1 — Read-mode cards** *(medium)*: `LPLinkView` wrapper + a `LinkMetadataCache`
  (in-memory) + the privacy toggle. Render a card per link in Read mode with a
  graceful fallback (title/host text) when fetch fails or previews are off.
  **Exit:** a note with a URL shows a themed preview card in Read mode (when
  enabled), on iOS + macOS, with the privacy toggle respected.
- **P2 — Persistent cache + favicon fallback**: disk-cache metadata keyed by URL;
  show favicon + title if the rich image is unavailable.
- **Phase ✦ — Inline editor card**: render the card inline via
  `NSTextAttachmentViewProvider` on link-only lines (reveal raw URL on caret entry).

### Risks / notes
- Network + async + caching complexity; `LPLinkView` intrinsic sizing inside
  SwiftUI scroll views needs care.
- Many links in one note → fetch throttling / lazy load on scroll.
- Privacy framing is the real gating decision — get the toggle/UX right first.

---

## 4. Sequencing recommendation

Each feature's **P1 is independent and reliable** (all live in Read mode /
attachments + viewers, no fragile editor surgery). Suggested order:

1. **Tables P1** — smallest; insert command + Read-mode grid polish.
2. **File/PDF P1** — highest user value; needs the `Attachment.contentType`
   migration + PDFKit/Quick Look viewer.
3. **Link-with-thumbnail P1** — do the **privacy toggle** design first, then the
   `LPLinkView` cards.

Then revisit **Phase ✦ (inline editor widgets)** for all three as one focused,
device-iterated effort on `NSTextAttachmentViewProvider`, since they share that
machinery.

## 5. Definition of done (per feature, per the project bar)

A feature ships when it: works on **all three platforms** (or is explicitly
scoped), **respects the active theme**, keeps **`.md` canonical and
round-trippable**, excludes **locked notes** where content is exposed, has at
least a **smoke test** for any parsing/transform logic, and (for links) honours
the **privacy toggle**.
