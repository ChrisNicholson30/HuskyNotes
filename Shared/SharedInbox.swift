//
//  SharedInbox.swift
//  HuskyNotes  +  HuskyNotes-ShareExtension  (shared source)
//
//  A tiny hand-off queue between the Share Extension and the main app, stored in
//  the shared App Group container. The extension appends captured web pages; the
//  app drains them into real notes on launch/foreground.
//
//  Kept deliberately dependency-free (Foundation only) so it compiles into both
//  the app and the extension. SwiftData is intentionally NOT used in the
//  extension — passing plain data through the App Group is far more robust.
//

import Foundation

/// A queue of shared items handed from the Share Extension to the app.
enum SharedInbox {

    /// The App Group both targets are members of.
    static let appGroupID = "group.com.huskynotes.app"

    /// One captured item from a browser share.
    struct Item: Codable, Identifiable {
        var id = UUID()
        /// The page title (or a fallback).
        var title: String
        /// The page URL, if any.
        var urlString: String?
        /// Selected text / page text, if any.
        var text: String?
        /// When it was captured.
        var date = Date()

        /// Renders the item as a Markdown note body.
        var markdown: String {
            var lines = ["# \(title.isEmpty ? "Shared Page" : title)", ""]
            if let urlString, !urlString.isEmpty {
                lines.append("[\(urlString)](\(urlString))")
                lines.append("")
            }
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(text)
            }
            lines.append("")
            lines.append("#clipped")
            return lines.joined(separator: "\n")
        }
    }

    /// The inbox file inside the App Group container.
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("inbox.json")
    }

    /// Appends an item to the inbox (called by the extension).
    static func append(_ item: Item) {
        guard let url = fileURL else { return }
        var items = load()
        items.append(item)
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Loads all pending items.
    static func load() -> [Item] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    /// Clears the inbox (called by the app after draining).
    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
