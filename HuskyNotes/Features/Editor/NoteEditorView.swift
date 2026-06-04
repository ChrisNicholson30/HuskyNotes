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

    /// Debounce handle so we reconcile tags shortly after typing stops rather
    /// than on every keystroke (which would create tags for partial input).
    @State private var reconcileTask: Task<Void, Never>?

    /// Focus-mode placeholder: when enabled, surrounding chrome is dimmed.
    /// - TODO: Wire this to real distraction-free behaviour (hide sidebar /
    ///   list columns, centre the text column) in a later milestone.
    @State private var isFocusMode = false

    /// Whether the user has authenticated to view this locked note this session.
    @State private var isUnlocked = false

    /// Whether the image importer is presented.
    @State private var isImportingImage = false

    var body: some View {
        Group {
            if note.isLocked && !isUnlocked {
                lockedView
            } else {
                editor
            }
        }
        // Re-lock when switching to a different note or leaving the editor.
        .onChange(of: note.id) { _, _ in isUnlocked = false }
    }

    /// The editor itself, plus the attachments strip and toolbar.
    private var editor: some View {
        VStack(spacing: 0) {
            MarkdownEditor(text: bodyBinding, theme: theme)
            if !(note.attachments ?? []).isEmpty {
                AttachmentsBar(note: note)
            }
        }
        .background(theme.background.swiftUIColor)
        .navigationTitle(note.title.isEmpty ? "New Note" : note.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button { isImportingImage = true } label: {
                    Label("Insert Image", systemImage: "photo.badge.plus")
                }
                .tint(theme.accent.swiftUIColor)
            }
            ToolbarItem {
                Button { toggleLock() } label: {
                    Label(note.isLocked ? "Remove Lock" : "Lock Note",
                          systemImage: note.isLocked ? "lock.fill" : "lock.open")
                }
                .tint(theme.accent.swiftUIColor)
            }
            ToolbarItem {
                Button {
                    isFocusMode.toggle()
                } label: {
                    Label("Focus Mode",
                          systemImage: isFocusMode
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right")
                }
                .tint(theme.accent.swiftUIColor)
            }
        }
        .fileImporter(isPresented: $isImportingImage, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { importImage(at: url) }
        }
        .onChange(of: note.body) { _, _ in scheduleTagReconcile() }
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

    // MARK: Attachments

    /// Imports an image file as an `Attachment` owned by this note.
    private func importImage(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }

        let attachment = Attachment(filename: url.lastPathComponent, data: data)
        attachment.note = note
        modelContext.insert(attachment)
        var current = note.attachments ?? []
        current.append(attachment)
        note.attachments = current
        note.modifiedAt = Date()
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
