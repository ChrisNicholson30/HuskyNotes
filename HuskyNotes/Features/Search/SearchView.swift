//
//  SearchView.swift
//  HuskyNotes
//
//  A simple v0.1 search: a search field plus a `@Query`/`#Predicate` filter
//  over note title and body. Results reuse `NoteRow` and select into the
//  editor. Fully themed.
//
//  - TODO (v0.3): Replace this linear `contains` scan with a SQLite FTS5 index
//    (local, derived, rebuildable, NOT synced) for fast prefix/token search.
//

import SwiftUI
import SwiftData

/// Full-text-ish search over notes' titles and bodies (substring match, v0.1).
struct SearchView: View {

    /// The selected result, shared with the editor column.
    @Binding var selection: Note?

    /// The live query text.
    @State private var query: String = ""

    /// All non-trashed notes, newest first. Filtered client-side by ``query``.
    @Query(
        filter: #Predicate<Note> { !$0.isTrashed },
        sort: \Note.modifiedAt,
        order: .reverse
    ) private var notes: [Note]

    /// Active theme for chrome colours.
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    var body: some View {
        List(selection: $selection) {
            ForEach(results) { note in
                NoteRow(note: note)
                    .tag(note)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background.swiftUIColor)
        .tint(theme.accent.swiftUIColor)
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Search notes — try #tag text")
        .overlay {
            if !query.isEmpty && results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .foregroundStyle(theme.textSecondary.swiftUIColor)
            }
        }
    }

    /// Notes matching the composable `#tag text` query.
    private var results: [Note] {
        NoteSearch.filter(notes, query)
    }
}
