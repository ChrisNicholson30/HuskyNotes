//
//  ShareSheet.swift
//  HuskyNotes
//
//  iOS/iPadOS sharing: writes a note to a temporary `.md` file and presents the
//  system share sheet so it can be sent anywhere as Markdown. (macOS exports via
//  the File menu instead.)
//

#if os(iOS)
import SwiftUI
import UIKit

/// An identifiable wrapper around a file URL, for `.sheet(item:)`.
struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Writes a note to a temp `.md` file (frontmatter + body) for sharing.
enum ShareExport {
    static func makeMarkdownFile(for note: Note) -> ShareFile? {
        let base = MarkdownExporter.sanitise(note.title.isEmpty ? "Untitled" : note.title)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(base).md")
        let contents = frontmatter(for: note) + "\n\n" + note.body
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return ShareFile(url: url)
        } catch {
            return nil
        }
    }
}

/// Hosts a `UIActivityViewController` for sharing a file URL.
struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
