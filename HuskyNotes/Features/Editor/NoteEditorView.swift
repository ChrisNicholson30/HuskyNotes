//
//  NoteEditorView.swift
//  HuskyNotes
//
//  The detail column: hosts the TextKit 2 `MarkdownEditor` bound to the note's
//  Markdown body. On every edit it stamps `modifiedAt` and recomputes the
//  denormalised title. Background and chrome come from the active theme.
//

import SwiftUI

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

    /// Focus-mode placeholder: when enabled, surrounding chrome is dimmed.
    /// - TODO: Wire this to real distraction-free behaviour (hide sidebar /
    ///   list columns, centre the text column) in a later milestone.
    @State private var isFocusMode = false

    var body: some View {
        MarkdownEditor(text: bodyBinding, theme: theme)
            .background(theme.background.swiftUIColor)
            .navigationTitle(note.title.isEmpty ? "New Note" : note.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
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
