//
//  NoteSearch.swift
//  HuskyNotes
//
//  Composable note search. A query mixes free text with `#tag` filters, e.g.
//  `#work invoice` matches notes tagged `work` whose text contains "invoice".
//  Matching is case-insensitive; multiple tags/terms are ANDed.
//
//  This is the user-facing search used by the note list. For very large
//  libraries a derived SQLite FTS5 index (local, rebuildable, not synced) would
//  replace the linear scan — see the TODO at the bottom.
//

import Foundation

/// Parses and evaluates composable tag + text note queries.
enum NoteSearch {

    /// A parsed query: zero or more required tags and zero or more text terms.
    struct Query: Equatable {
        var tags: [String]   // lowercased, without leading '#'
        var terms: [String]  // lowercased free-text tokens

        /// Whether the query has no constraints (matches everything).
        var isEmpty: Bool { tags.isEmpty && terms.isEmpty }
    }

    /// Splits raw input into `#tag` filters and free-text terms.
    static func parse(_ raw: String) -> Query {
        var tags: [String] = []
        var terms: [String] = []
        for token in raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            if token.hasPrefix("#"), token.count > 1 {
                tags.append(token.dropFirst().lowercased())
            } else {
                terms.append(token.lowercased())
            }
        }
        return Query(tags: tags, terms: terms)
    }

    /// Whether a note satisfies every tag and term in the query.
    static func matches(_ note: Note, query: Query) -> Bool {
        if !query.tags.isEmpty {
            let noteTags = (note.tags ?? []).map { $0.name.lowercased() }
            for required in query.tags {
                // Match exact or nested-path prefix, e.g. `#work` matches
                // `work/clients`.
                let ok = noteTags.contains { $0 == required || $0.hasPrefix(required + "/") }
                if !ok { return false }
            }
        }
        if !query.terms.isEmpty {
            var haystack = (note.title + "\n" + note.body).lowercased()
            // Include text recognized in attachments (OCR) so a search finds words
            // inside scans, photos and PDFs — not just the typed body.
            let recognized = (note.attachments ?? [])
                .compactMap { $0.recognizedText }
                .joined(separator: "\n")
            if !recognized.isEmpty { haystack += "\n" + recognized.lowercased() }
            for term in query.terms where !haystack.contains(term) {
                return false
            }
        }
        return true
    }

    /// Filters and returns the notes matching `raw` (unchanged order).
    static func filter(_ notes: [Note], _ raw: String) -> [Note] {
        let query = parse(raw)
        guard !query.isEmpty else { return notes }
        return notes.filter { matches($0, query: query) }
    }

    // TODO (perf): back this with a SQLite FTS5 index keyed by note id —
    // local-only, rebuildable, and NOT synced — so search stays instant on
    // very large libraries. The query grammar above stays the same.
}
