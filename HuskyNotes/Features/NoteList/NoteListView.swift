//
//  NoteListView.swift
//  HuskyNotes
//
//  The middle column: a list of notes filtered by the selected `SmartList`.
//  A "+" toolbar button inserts a new note and selects it. Rows expose pin /
//  archive / trash actions via swipe and context menu. Fully themed.
//
//  v0.1 filters client-side over a single `@Query`. When the note corpus grows
//  this should move to a `#Predicate`-backed query per filter (see TODO).
//

import SwiftUI
import SwiftData

/// Lists notes matching a ``SmartList`` filter and lets the user create,
/// pin, archive and trash notes.
struct NoteListView: View {

    /// The active filter that scopes which notes are shown.
    let filter: SmartList

    /// The selected note, shared with the editor (detail) column.
    @Binding var selection: Note?

    /// Live search text (composable `#tag text` query).
    @State private var searchText: String = ""

    /// SwiftData context for inserting / mutating notes.
    @Environment(\.modelContext) private var modelContext

    /// Active theme for chrome colours.
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    /// All notes, newest-modified first. Filtered client-side by ``filter``.
    ///
    /// - TODO: v0.1 fetches all notes and filters in-memory for simplicity.
    ///   Switch to per-filter `#Predicate` queries (and FTS5 for search in
    ///   v0.3) once the corpus is large enough to matter.
    @Query(sort: \Note.modifiedAt, order: .reverse) private var allNotes: [Note]

    var body: some View {
        List(selection: $selection) {
            ForEach(filteredNotes) { note in
                NoteRow(note: note)
                    .tag(note)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        pinButton(note)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        trashButton(note)
                        archiveButton(note)
                    }
                    .contextMenu {
                        pinButton(note)
                        archiveButton(note)
                        lockButton(note)
                        Divider()
                        trashButton(note)
                    }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background.swiftUIColor)
        .tint(theme.accent.swiftUIColor)
        .navigationTitle(filter.title)
        .toolbar {
            ToolbarItem {
                Button(action: addNote) {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .tint(theme.accent.swiftUIColor)
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        // Honour the macOS "New Note" menu command (⌘N).
        .onReceive(NotificationCenter.default.publisher(for: .huskyNewNote)) { _ in
            addNote()
        }
        .searchable(text: $searchText, prompt: "Search — try #tag text")
        .overlay {
            if filteredNotes.isEmpty {
                ContentUnavailableView {
                    Label("No Notes", systemImage: filter.systemImage)
                } description: {
                    Text("Tap the compose button to create your first note.")
                }
                .foregroundStyle(theme.textSecondary.swiftUIColor)
            }
        }
    }

    // MARK: Filtering

    /// Notes matching the active ``SmartList`` and the current search query.
    private var filteredNotes: [Note] {
        let scoped = allNotes.filter { matches($0) }
        return NoteSearch.filter(scoped, searchText)
    }

    /// Whether a note belongs in the current filter.
    private func matches(_ note: Note) -> Bool {
        switch filter {
        case .all:
            return !note.isArchived && !note.isTrashed
        case .pinned:
            return note.isPinned && !note.isArchived && !note.isTrashed
        case .today:
            return !note.isArchived && !note.isTrashed
                && Calendar.current.isDateInToday(note.modifiedAt)
        case .untagged:
            return !note.isArchived && !note.isTrashed
                && (note.tags?.isEmpty ?? true)
        case .archived:
            return note.isArchived && !note.isTrashed
        case .trash:
            return note.isTrashed
        case .tag(let tag):
            return !note.isArchived && !note.isTrashed
                && (note.tags?.contains { $0.id == tag.id } ?? false)
        }
    }

    // MARK: Actions

    /// Inserts a fresh note pre-seeded with an empty H1 header (so every new
    /// note starts as a titled heading, Bear-style) and selects it for editing.
    private func addNote() {
        let note = Note(body: "# ")
        note.recomputeTitle()
        modelContext.insert(note)
        selection = note
    }

    /// Toggles a note's pinned state.
    private func togglePin(_ note: Note) {
        note.isPinned.toggle()
        note.modifiedAt = Date()
    }

    /// Toggles a note's archived state.
    private func toggleArchive(_ note: Note) {
        note.isArchived.toggle()
        note.modifiedAt = Date()
    }

    /// Moves a note to/from the trash, stamping/clearing ``Note/trashedAt``.
    private func toggleTrash(_ note: Note) {
        note.isTrashed.toggle()
        note.trashedAt = note.isTrashed ? Date() : nil
        note.modifiedAt = Date()
        if note.isTrashed, selection?.id == note.id {
            selection = nil
        }
    }

    // MARK: Reusable buttons

    @ViewBuilder
    private func pinButton(_ note: Note) -> some View {
        Button {
            togglePin(note)
        } label: {
            Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
        }
        .tint(theme.accent.swiftUIColor)
    }

    @ViewBuilder
    private func lockButton(_ note: Note) -> some View {
        Button {
            note.isLocked.toggle()
            note.modifiedAt = Date()
        } label: {
            Label(note.isLocked ? "Remove Lock" : "Lock",
                  systemImage: note.isLocked ? "lock.open" : "lock")
        }
        .tint(theme.accent.swiftUIColor)
    }

    @ViewBuilder
    private func archiveButton(_ note: Note) -> some View {
        Button {
            toggleArchive(note)
        } label: {
            Label(note.isArchived ? "Unarchive" : "Archive",
                  systemImage: note.isArchived ? "tray.and.arrow.up" : "archivebox")
        }
        .tint(theme.quoteBar.swiftUIColor)
    }

    @ViewBuilder
    private func trashButton(_ note: Note) -> some View {
        Button(role: .destructive) {
            toggleTrash(note)
        } label: {
            Label(note.isTrashed ? "Restore" : "Trash",
                  systemImage: note.isTrashed ? "arrow.uturn.backward" : "trash")
        }
    }
}
