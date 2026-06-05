//
//  NoteListView.swift
//  HuskyNotes
//
//  The middle column: a list of notes filtered by the selected `SmartList`.
//  A "+" toolbar button inserts a new note and selects it.
//
//  • iOS/iPadOS: tap a row to open it; swipe / long-press for per-note actions.
//  • macOS: native multi-selection (⌘/⇧-click) with batch actions — move to
//    folder, pin, archive, trash — via the context menu, toolbar, and ⌫.
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

    /// Set to a note's id when it is freshly created, so the editor auto-focuses
    /// it (and raises the keyboard on iOS). Shared with the editor column.
    @Binding var autoFocusNoteID: UUID?

    /// Live search text (composable `#tag text` query).
    @State private var searchText: String = ""

    /// macOS multi-selection of notes (by id) for batch actions.
    @State private var multiSelection = Set<UUID>()

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

    /// User-created folders, for the "Move to Folder" menu.
    @Query(sort: \Folder.createdAt, order: .forward) private var folders: [Folder]

    var body: some View {
        listContent
            .scrollContentBackground(.hidden)
            .background(theme.background.swiftUIColor)
            .tint(theme.accent.swiftUIColor)
            .navigationTitle(filter.title)
            .toolbar { toolbarContent }
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
            #if os(macOS)
            // Keep the list highlight in step with the open note (e.g. a new
            // note created from the toolbar).
            .onAppear { if let selection { multiSelection = [selection.id] } }
            .onChange(of: selection) { _, note in
                if let note, multiSelection != [note.id] { multiSelection = [note.id] }
            }
            #endif
    }

    /// The platform list: native multi-select on macOS, tap-to-open on iOS.
    @ViewBuilder
    private var listContent: some View {
        #if os(macOS)
        macList
        #else
        iosList
        #endif
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        if !multiSelection.isEmpty {
            ToolbarItem {
                Menu {
                    folderAssignButtons(for: selectedNotes)
                } label: {
                    Label("Move to Folder", systemImage: "folder")
                }
            }
            ToolbarItem {
                Button(role: .destructive) {
                    trashNotes(selectedNotes)
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
            }
        }
        #endif
        ToolbarItem {
            Button(action: addNote) {
                Label("New Note", systemImage: "square.and.pencil")
            }
            .tint(theme.accent.swiftUIColor)
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    // MARK: iOS list

    #if !os(macOS)
    private var iosList: some View {
        List {
            ForEach(filteredNotes) { note in
                Button {
                    selection = note
                } label: {
                    NoteRow(note: note)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    selection == note
                        ? theme.accent.swiftUIColor.opacity(0.18)
                        : theme.surface.swiftUIColor
                )
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
                    folderMenu(note)
                    Divider()
                    trashButton(note)
                }
            }
        }
    }
    #endif

    // MARK: macOS list (multi-select + batch actions)

    #if os(macOS)
    private var macList: some View {
        List(selection: $multiSelection) {
            ForEach(filteredNotes) { note in
                NoteRow(note: note)
                    .tag(note.id)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            batchMenu(for: ids)
        } primaryAction: { ids in
            if let id = ids.first, let note = note(for: id) { selection = note }
        }
        // Single-click opens in the editor; multi-select leaves the editor as-is.
        .onChange(of: multiSelection) { _, ids in
            if ids.count == 1, let id = ids.first, let note = note(for: id), note.id != selection?.id {
                selection = note
            }
        }
        .onDeleteCommand {
            if filter == .trash { deletePermanently(selectedNotes) } else { trashNotes(selectedNotes) }
        }
    }

    /// Notes currently multi-selected.
    private var selectedNotes: [Note] { notes(for: multiSelection) }

    private func note(for id: UUID) -> Note? { allNotes.first { $0.id == id } }
    private func notes(for ids: Set<UUID>) -> [Note] { allNotes.filter { ids.contains($0.id) } }

    /// The right-click batch menu for the selected rows (or the row under the
    /// cursor); empty space offers a New Note action.
    @ViewBuilder
    private func batchMenu(for ids: Set<UUID>) -> some View {
        let targets = notes(for: ids)
        if targets.isEmpty {
            Button { addNote() } label: { Label("New Note", systemImage: "square.and.pencil") }
        } else {
            Menu {
                folderAssignButtons(for: targets)
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }
            Button { setPinned(targets, to: true) } label: { Label("Pin", systemImage: "pin") }
            Button { setPinned(targets, to: false) } label: { Label("Unpin", systemImage: "pin.slash") }
            Button { setArchived(targets, to: true) } label: { Label("Archive", systemImage: "archivebox") }
            Divider()
            if filter == .trash {
                Button { setTrashed(targets, to: false) } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                Button(role: .destructive) { deletePermanently(targets) } label: {
                    Label(targets.count > 1 ? "Delete \(targets.count) Notes Permanently" : "Delete Permanently",
                          systemImage: "trash")
                }
            } else {
                Button(role: .destructive) { trashNotes(targets) } label: {
                    Label(targets.count > 1 ? "Move \(targets.count) Notes to Trash" : "Move to Trash",
                          systemImage: "trash")
                }
            }
        }
    }

    /// Folder targets shared by the toolbar menu and the context menu.
    @ViewBuilder
    private func folderAssignButtons(for targets: [Note]) -> some View {
        Button("None") { targets.forEach { assign($0, to: nil) } }
        if !folders.isEmpty { Divider() }
        ForEach(folders) { folder in
            Button(folder.name.isEmpty ? "Untitled Folder" : folder.name) {
                targets.forEach { assign($0, to: folder) }
            }
        }
    }

    // MARK: macOS batch mutations

    private func setPinned(_ notes: [Note], to value: Bool) {
        notes.forEach { $0.isPinned = value; $0.modifiedAt = Date() }
    }

    private func setArchived(_ notes: [Note], to value: Bool) {
        notes.forEach { $0.isArchived = value; $0.modifiedAt = Date() }
        multiSelection.removeAll()
    }

    private func setTrashed(_ notes: [Note], to value: Bool) {
        for note in notes {
            note.isTrashed = value
            note.trashedAt = value ? Date() : nil
            note.modifiedAt = Date()
            if value, selection?.id == note.id { selection = nil }
        }
        multiSelection.removeAll()
    }

    private func trashNotes(_ notes: [Note]) { setTrashed(notes, to: true) }

    private func deletePermanently(_ notes: [Note]) {
        for note in notes {
            if selection?.id == note.id { selection = nil }
            modelContext.delete(note)
        }
        multiSelection.removeAll()
    }
    #endif

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
        case .todo:
            // Quick to-dos are a standalone list, not notes — selecting `.todo`
            // shows `TodoListView`, so no note ever matches here. (Kept for an
            // exhaustive switch.)
            return false
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
        case .folder(let folder):
            return !note.isArchived && !note.isTrashed
                && note.folder?.id == folder.id
        }
    }

    // MARK: Actions

    /// Inserts a fresh note pre-seeded with an empty H1 header (so every new
    /// note starts as a titled heading, Bear-style) and selects it for editing.
    private func addNote() {
        let note = Note(body: "# ")
        note.recomputeTitle()
        modelContext.insert(note)
        autoFocusNoteID = note.id   // mark as newly created so the editor focuses it
        selection = note
    }

    /// Files (or unfiles) a note into a folder and stamps its modified date.
    private func assign(_ note: Note, to folder: Folder?) {
        note.folder = folder
        note.modifiedAt = Date()
    }

    // MARK: Per-note actions (iOS swipe / context menu)

    #if !os(macOS)
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

    /// A submenu to file the note into a folder (or remove it from one). A
    /// checkmark marks the note's current folder.
    @ViewBuilder
    private func folderMenu(_ note: Note) -> some View {
        Menu {
            Button { assign(note, to: nil) } label: {
                Label("None", systemImage: note.folder == nil ? "checkmark" : "tray")
            }
            if !folders.isEmpty { Divider() }
            ForEach(folders) { folder in
                Button { assign(note, to: folder) } label: {
                    Label(folder.name.isEmpty ? "Untitled Folder" : folder.name,
                          systemImage: note.folder?.id == folder.id ? "checkmark" : "folder")
                }
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
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
    #endif
}
