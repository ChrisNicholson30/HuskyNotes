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
                HStack(spacing: 4) {
                    if note.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(theme.textSecondary.swiftUIColor)
                    }
                    Text(displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(theme.textPrimary.swiftUIColor)
                }

                // Hide the body preview for locked notes (privacy).
                if note.isLocked {
                    Text("Locked")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary.swiftUIColor)
                } else if !snippet.isEmpty {
                    Text(snippet)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(theme.textSecondary.swiftUIColor)
                }

                HStack(spacing: 6) {
                    if let folder = note.folder {
                        HStack(spacing: 3) {
                            folderGlyph(folder)
                            Text(folder.name.isEmpty ? "Folder" : folder.name)
                                .lineLimit(1)
                        }
                        .font(.caption2)
                        .foregroundStyle(folderColor(folder))
                    }
                    Text(note.modifiedAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(theme.textSecondary.swiftUIColor)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// Title to display, with Markdown syntax stripped, falling back to a
    /// placeholder for blank notes.
    private var displayTitle: String {
        let clean = MarkdownPlainText.from(note.title).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "New Note" : clean
    }

    /// The folder's icon — its emoji if set, otherwise a colour-tinted glyph.
    @ViewBuilder
    private func folderGlyph(_ folder: Folder) -> some View {
        if let emoji = folder.icon, !emoji.isEmpty {
            Text(emoji)
        } else {
            Image(systemName: "folder.fill")
        }
    }

    /// The folder's colour, falling back to the theme accent.
    private func folderColor(_ folder: Folder) -> Color {
        folder.colorHex.map { HexColor($0).swiftUIColor } ?? theme.accent.swiftUIColor
    }

    /// A one-line snippet: the body with its first (title) line removed and the
    /// Markdown syntax stripped, so the preview reads as plain prose.
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
        let plain = MarkdownPlainText.from(remainder.joined(separator: "\n"))
        return plain
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Strips Markdown syntax to readable plain text — for note-list titles and
/// snippets, which should read as prose, not source.
enum MarkdownPlainText {
    static func from(_ markdown: String) -> String {
        var s = markdown
        func sub(_ pattern: String, _ replacement: String) {
            s = s.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        // HTML tags (e.g. <mark class="hl-pink">, </mark>, <u>).
        sub("<[^>]+>", "")
        // Images / links / wiki links → keep the visible text, drop the target.
        sub("!\\[([^\\]]*)\\]\\([^)]*\\)", "$1")
        sub("\\[([^\\]]*)\\]\\([^)]*\\)", "$1")
        sub("\\[\\[([^\\]]+)\\]\\]", "$1")
        // Leading block markers per line: heading #, quote >, bullets, task boxes,
        // ordered numbers.
        sub("(?m)^[ \\t]{0,3}(#{1,6}[ \\t]+|>[ \\t]?|[-*+][ \\t]+(\\[[ xX]\\][ \\t]+)?|\\d+[.)][ \\t]+)", "")
        // Inline emphasis / code / highlight delimiters.
        for marker in ["**", "__", "~~", "==", "`", "*"] {
            s = s.replacingOccurrences(of: marker, with: "")
        }
        return s
    }
}
