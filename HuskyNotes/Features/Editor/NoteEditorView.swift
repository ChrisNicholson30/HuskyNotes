//
//  NoteEditorView.swift
//  HuskyNotes
//
//  The detail column: hosts the TextKit 2 `MarkdownEditor` bound to the note's
//  Markdown body. On every edit it stamps `modifiedAt` and recomputes the
//  denormalised title. Background and chrome come from the active theme.
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI            // PhotosPicker is available on iOS 16+ and macOS 13+
#if os(macOS)
import AppKit
#endif

/// Edits a single ``Note`` using the themed TextKit 2 ``MarkdownEditor``.
///
/// The note's ``Note/body`` is the canonical source of truth; this view writes
/// straight into it (SwiftData autosaves), then keeps the denormalised
/// ``Note/title`` and ``Note/modifiedAt`` in sync via ``Note/recomputeTitle()``.
struct NoteEditorView: View {

    /// The note being edited. `@Bindable` so edits flow back into SwiftData.
    @Bindable var note: Note

    /// Active theme for the editor's surface and chrome.
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    /// SwiftData context, used to reconcile `#tags` from the body into the
    /// note's `Tag` relationship as the user types.
    @Environment(\.modelContext) private var modelContext

    /// Used to widen the editor only on regular-width devices (iPad/Mac).
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Debounce handle so we reconcile tags shortly after typing stops rather
    /// than on every keystroke (which would create tags for partial input).
    @State private var reconcileTask: Task<Void, Never>?

    /// Handle to the live editor, so imports can insert a reference at the caret.
    @State private var editorController = EditorController()

    /// Distraction-free focus mode, owned by ``RootView`` (which collapses the
    /// sidebar and list columns). The toolbar button toggles it.
    @Binding var isFocusMode: Bool

    /// The id of a freshly-created note to auto-focus. When it matches this
    /// note, the editor focuses and (on iOS) raises the keyboard, then clears it
    /// so re-opening the note later doesn't pop the keyboard again.
    @Binding var autoFocusNoteID: UUID?

    /// Whether the user has authenticated to view this locked note this session.
    @State private var isUnlocked = false

    /// Whether the note is shown as a rendered, read-only view (tables, etc.).
    @State private var isReading = false

    /// The attachment being previewed from an inline tap in reading mode.
    @State private var previewingAttachment: Attachment?

    /// Drives the Photos picker for inserting images (both platforms). PHPicker is
    /// out-of-process, so it needs no photo-library permission prompt.
    @State private var isPickingPhoto = false
    /// The photo chosen from the library, pending import.
    @State private var pickedPhoto: PhotosPickerItem?

    #if os(iOS)
    /// Whether the document scanner (camera) is presented (iOS only).
    @State private var isScanning = false
    #endif

    /// Whether the file importer (PDFs / other documents) is presented.
    @State private var isImportingFile = false

    #if os(iOS)
    /// The `.md` file currently being shared via the system share sheet.
    @State private var shareFile: ShareFile?
    #endif

    var body: some View {
        Group {
            if note.isLocked && !isUnlocked {
                lockedView
            } else {
                editor
            }
        }
        // Re-lock when switching to a different note or leaving the editor.
        .onChange(of: note.id) { _, _ in
            isUnlocked = false
            focusIfNewlyCreated()
        }
    }

    /// Focuses the editor (and raises the keyboard on iOS) only for a note that
    /// was *just created* — matched by ``autoFocusNoteID`` — then clears the flag
    /// so re-opening the note later won't pop the keyboard. Opening existing
    /// notes never auto-focuses.
    private func focusIfNewlyCreated() {
        guard !note.isLocked, autoFocusNoteID == note.id else { return }
        autoFocusNoteID = nil
        DispatchQueue.main.async { editorController.focus() }
    }

    /// The editor itself, plus the attachments strip and toolbar.
    private var editor: some View {
        VStack(spacing: 0) {
            if isReading {
                ScrollView {
                    MarkdownReadingView(
                        markdown: note.body,
                        theme: theme,
                        attachments: note.attachments ?? [],
                        onOpenAttachment: { previewingAttachment = $0 }
                    )
                        .padding()
                        .frame(maxWidth: readableWidth, alignment: .leading)
                        // Hug the leading edge (a small document gutter) rather
                        // than centring the column in the middle of a wide window.
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                MarkdownEditor(text: bodyBinding, theme: theme, controller: editorController)
                    // Cap the text column to a comfortable reading width on large
                    // (iPad/Mac) windows; fill edge-to-edge on compact iPhones.
                    // Left-aligned so the text starts near the leading edge, not
                    // floating in the centre of a wide pane.
                    .frame(maxWidth: readableWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !(note.attachments ?? []).isEmpty {
                    AttachmentsBar(note: note)
                }
            }
        }
        .background(theme.background.swiftUIColor)
        .navigationTitle(note.title.isEmpty ? "New Note" : note.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            // Hidden in focus mode for a distraction-free surface.
            if !isFocusMode {
                ToolbarItem {
                    Menu {
                        #if os(iOS)
                        Button { shareFile = ShareExport.makeMarkdownFile(for: note) } label: {
                            Label("Share as Markdown", systemImage: "doc.plaintext")
                        }
                        #endif
                        Button { exportPDF() } label: {
                            Label("Export as PDF…", systemImage: "doc.richtext")
                        }
                        Button { printNote() } label: {
                            Label("Print…", systemImage: "printer")
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(theme.accent.swiftUIColor)
                }
                ToolbarItem {
                    Button { isPickingPhoto = true } label: {
                        Label("Insert Image", systemImage: "photo.badge.plus")
                    }
                    .tint(theme.accent.swiftUIColor)
                }
                ToolbarItem {
                    Button { isImportingFile = true } label: {
                        Label("Insert File", systemImage: "doc.badge.plus")
                    }
                    .tint(theme.accent.swiftUIColor)
                }
                #if os(iOS)
                ToolbarItem {
                    Button { isScanning = true } label: {
                        Label("Scan Document", systemImage: "doc.viewfinder")
                    }
                    .tint(theme.accent.swiftUIColor)
                }
                #endif
                ToolbarItem {
                    Button { toggleLock() } label: {
                        Label(note.isLocked ? "Remove Lock" : "Lock Note",
                              systemImage: note.isLocked ? "lock.fill" : "lock.open")
                    }
                    .tint(theme.accent.swiftUIColor)
                }
            }
            ToolbarItem {
                Button {
                    isReading.toggle()
                } label: {
                    Label(isReading ? "Edit" : "Read",
                          systemImage: isReading ? "pencil" : "book")
                }
                .tint(theme.accent.swiftUIColor)
            }
            ToolbarItem {
                Button {
                    isFocusMode.toggle()
                } label: {
                    Label(isFocusMode ? "Exit Focus" : "Focus Mode",
                          systemImage: isFocusMode
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right")
                }
                .tint(theme.accent.swiftUIColor)
            }
        }
        // Images come from the Photos library on both platforms. PHPicker is
        // out-of-process, so it needs no photo-library permission prompt.
        .photosPicker(isPresented: $isPickingPhoto, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            importPhoto(item)
        }
        // The file importer covers PDFs / other documents (images use the picker).
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.pdf, .data]) { result in
            if case .success(let url) = result { importAttachment(at: url) }
        }
        #if os(iOS)
        .sheet(item: $shareFile) { file in
            ActivityView(url: file.url)
        }
        .fullScreenCover(isPresented: $isScanning) {
            DocumentScannerView { data in handleScan(data) }
                .ignoresSafeArea()
        }
        #endif
        // Tapping an inline image/PDF/file in reading mode opens the full viewer.
        .sheet(item: $previewingAttachment) { attachment in
            AttachmentViewer(attachment: attachment)
                .environment(themeStore)
        }
        .onChange(of: note.body) { _, _ in scheduleTagReconcile() }
        #if os(macOS)
        // File ▸ Print (⌘P) routes here so it prints the open note rather than
        // hitting AppKit's unhandled-print alert. Locked, un-viewed notes are
        // skipped so content can't be printed without unlocking.
        .onReceive(NotificationCenter.default.publisher(for: .huskyPrintNote)) { _ in
            guard !(note.isLocked && !isUnlocked) else { return }
            printNote()
        }
        #endif
        .onAppear { focusIfNewlyCreated() }
        .onDisappear {
            flushTagReconcile()
            isUnlocked = false
        }
    }

    /// Shown in place of the editor when the note is locked and not yet unlocked.
    private var lockedView: some View {
        ContentUnavailableView {
            Label("Locked Note", systemImage: "lock.fill")
        } description: {
            Text("Unlock with \(BiometricAuth.biometryName) to view this note.")
        } actions: {
            Button("Unlock") { unlock() }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent.swiftUIColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.swiftUIColor)
    }

    /// The editor's maximum content width. Capped on regular-width devices
    /// (iPad/Mac) for readability; unbounded on compact iPhones.
    private var readableWidth: CGFloat {
        #if os(macOS)
        return 760
        #else
        return horizontalSizeClass == .regular ? 760 : .infinity
        #endif
    }

    // MARK: Locking

    /// Toggles the note's lock. Locking is immediate; removing a lock from an
    /// already-unlocked, visible note needs no re-auth.
    private func toggleLock() {
        note.isLocked.toggle()
        note.modifiedAt = Date()
        if !note.isLocked { isUnlocked = false }
    }

    /// Authenticates to reveal a locked note. If biometrics are unavailable
    /// (e.g. an un-enrolled simulator), the note is shown rather than trapping
    /// the user.
    private func unlock() {
        BiometricAuth.authenticate(reason: "Unlock this note") { outcome in
            if outcome == .success || outcome == .unavailable {
                isUnlocked = true
            }
        }
    }

    // MARK: Export & print

    /// Exports the note's rendered Markdown as a PDF (matching Read mode). On iOS
    /// it routes the file through the share sheet; on macOS it shows a save panel.
    private func exportPDF() {
        #if os(iOS)
        guard let url = PDFRenderer.pdfFile(for: note, theme: theme) else { return }
        shareFile = ShareFile(url: url)
        #else
        guard let data = PDFRenderer.pdfData(for: note, theme: theme) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let base = MarkdownExporter.sanitise(note.title.isEmpty ? "Untitled" : note.title)
        panel.nameFieldStringValue = "\(base).pdf"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url, options: .atomic)
        }
        #endif
    }

    /// Opens the system print dialog for the note's rendered Markdown.
    private func printNote() {
        PrintService.print(note: note, theme: theme)
    }

    // MARK: Attachments

    /// Imports a photo chosen from the Photos library (both platforms). The picker
    /// hands back opaque `Data`; we stage it in a temp file (so the UTI/extension
    /// resolve) and run it through the shared attachment path — which inserts the
    /// embed at the caret, same as any other attachment.
    private func importPhoto(_ item: PhotosPickerItem) {
        Task { @MainActor in
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let name = "Photo-\(Int(Date().timeIntervalSince1970)).\(ext)"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            guard (try? data.write(to: url)) != nil else { return }
            importAttachment(at: url)
            try? FileManager.default.removeItem(at: url)
        }
    }

    #if os(iOS)
    /// Handles a finished document scan: writes the assembled PDF to a temp file
    /// and runs it through the shared attachment path (which embeds it and OCRs it).
    private func handleScan(_ data: Data?) {
        guard let data else { return }
        let name = "Scan-\(Int(Date().timeIntervalSince1970)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? data.write(to: url)) != nil else { return }
        importAttachment(at: url)
        try? FileManager.default.removeItem(at: url)
    }
    #endif

    /// Imports any file (image, PDF, document, …) as an `Attachment` owned by
    /// this note, recording its UTI and size for correct preview routing and
    /// display. The bytes live in SwiftData external storage.
    private func importAttachment(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }

        // Resolve the UTI from the file when possible, falling back to the
        // extension, so the viewer can route PDFs to PDFKit and the rest to
        // Quick Look.
        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier
            ?? UTType(filenameExtension: url.pathExtension)?.identifier

        let attachment = Attachment(
            filename: url.lastPathComponent,
            data: data,
            contentType: contentType,
            byteCount: data.count
        )
        attachment.note = note
        modelContext.insert(attachment)
        var current = note.attachments ?? []
        current.append(attachment)
        note.attachments = current
        note.modifiedAt = Date()

        // Recognize text on-device (OCR) so the attachment's content is searchable.
        AttachmentOCR.recognizeIfNeeded(attachment)

        // Drop a portable reference into the body at the caret (not the bottom),
        // resolving to the exported `_attachments/` folder. Images embed; other
        // files link.
        let name = url.lastPathComponent
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let path = "_attachments/\(encoded)"
        let isImage = contentType.flatMap { UTType($0)?.conforms(to: .image) } ?? false
        let snippet = isImage ? "![\(name)](\(path))" : "[📄 \(name)](\(path))"
        editorController.insert(snippet)
    }

    // MARK: Tag reconciliation

    /// Schedules a debounced reconcile of the note's `#tags` (~0.6s after the
    /// last edit), cancelling any pending one.
    private func scheduleTagReconcile() {
        reconcileTask?.cancel()
        reconcileTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            TagReconciler.reconcile(note, in: modelContext)
            MirrorService.mirrorIfEnabled(context: modelContext)
        }
    }

    /// Reconciles immediately (e.g. when leaving the note) and cancels any
    /// pending debounce, then mirrors to `.md` if the mirror is on.
    private func flushTagReconcile() {
        reconcileTask?.cancel()
        reconcileTask = nil
        TagReconciler.reconcile(note, in: modelContext)
        MirrorService.mirrorIfEnabled(context: modelContext)
    }

    /// A binding to ``Note/body`` that, on write, refreshes the denormalised
    /// title and modification date so lists stay accurate as the user types.
    private var bodyBinding: Binding<String> {
        Binding(
            get: { note.body },
            set: { newValue in
                guard newValue != note.body else { return }
                note.body = newValue
                note.modifiedAt = Date()
                note.recomputeTitle()
            }
        )
    }
}
