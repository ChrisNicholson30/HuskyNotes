//
//  RootView.swift
//  HuskyNotes
//
//  The top-level navigation. A three-column `NavigationSplitView`
//  (Sidebar → Note list → Editor) on macOS and iPadOS; the same structure
//  automatically collapses to a stacked, drill-in navigation on iPhone.
//
//  All surfaces read their colours from the active `Theme` — nothing here is
//  hard-coded.
//

import SwiftUI

/// The root scene content: sidebar, note list and editor wired together.
struct RootView: View {

    /// The selected smart list (sidebar → note-list column).
    @State private var selectedList: SmartList? = .all

    /// The selected note (note-list → editor column).
    @State private var selectedNote: Note?

    /// Sidebar column visibility, so the split view starts fully expanded.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// Distraction-free focus mode: collapses the sidebar/list columns to leave
    /// only the editor. Owned here because it drives `columnVisibility`.
    @State private var isFocusMode = false

    /// Active theme supplies every colour.
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selectedList)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
                #endif
        } content: {
            NoteListView(filter: selectedList ?? .all, selection: $selectedNote)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
                #endif
        } detail: {
            if let selectedNote {
                NoteEditorView(note: selectedNote, isFocusMode: $isFocusMode)
            } else {
                emptyDetail
            }
        }
        .tint(theme.accent.swiftUIColor)
        // When the active list changes, clear a selection that no longer applies.
        .onChange(of: selectedList) { _, _ in selectedNote = nil }
        // Focus mode hides the sidebar + list columns; exiting restores them.
        .onChange(of: isFocusMode) { _, focused in
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = focused ? .detailOnly : .all
            }
        }
        // Leaving focus mode if no note is selected avoids a stuck collapsed state.
        .onChange(of: selectedNote) { _, note in
            if note == nil, isFocusMode { isFocusMode = false }
        }
    }

    /// Placeholder shown in the detail column when no note is selected.
    private var emptyDetail: some View {
        ContentUnavailableView {
            Label("No Note Selected", systemImage: "note.text")
        } description: {
            Text("Select a note from the list, or create a new one.")
        }
        .foregroundStyle(theme.textSecondary.swiftUIColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.swiftUIColor)
    }
}
