//
//  NoteRow.swift
//  HuskyNotes
//
//  A single row in the note list: title, a one-line snippet derived from the
//  Markdown body, and a relative modified date. Fully themed.
//

import SwiftUI

/// A themed row summarising a `Note` for the note list.
struct NoteRow: View {

    /// The note to summarise.
    let note: Note

    /// Active theme for all colours.
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if note.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(theme.accent.swiftUIColor)
                    .padding(.top, 3)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(theme.textPrimary.swiftUIColor)

                if !snippet.isEmpty {
                    Text(snippet)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(theme.textSecondary.swiftUIColor)
                }

                Text(note.modifiedAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary.swiftUIColor)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .listRowBackground(theme.surface.swiftUIColor)
    }

    /// Title to display, falling back to a placeholder for blank notes.
    private var displayTitle: String {
        note.title.isEmpty ? "New Note" : note.title
    }

    /// A one-line snippet: the body with its first (title) line removed.
    private var snippet: String {
        let lines = note.body.split(separator: "\n", omittingEmptySubsequences: false)
        // Drop the first non-empty line (which becomes the title) and join the rest.
        var seenTitle = false
        let remainder = lines.drop { line in
            if seenTitle { return false }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return true }
            seenTitle = true
            return true
        }
        return remainder
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
