//
//  SharedInbox.swift
//  HuskyNotes  +  HuskyNotes-ShareExtension  (shared source)
//
//  A robust hand-off queue between the Share Extension and the app, stored in
//  the shared App Group container. The extension writes one self-contained file
//  per shared capture (text/URL plus any image/PDF/file attachments); the app
//  drains each into a real note and deletes it only once it succeeds.
//
//  Design for robustness:
//   • One JSON file per item (`inbox/<id>.json`) — no shared-array read-modify-
//     write, so concurrent captures can't clobber each other or corrupt state.
//   • Attachment bytes live as sibling blob files; the JSON is written *last*
//     (after its blobs), so the app never sees an item referencing missing data.
//   • The app removes an item only after the note is created — a crash mid-drain
//     loses nothing; the item is retried next launch.
//
//  Foundation-only so it compiles into both the app and the extension.
//

import Foundation

/// A durable hand-off queue from the Share Extension to the app.
enum SharedInbox {

    /// The App Group both targets are members of.
    static let appGroupID = "group.com.huskynotes.app"

    /// Skip attachments larger than this (keeps extension memory + sync sane).
    static let maxAttachmentBytes = 50_000_000

    /// A captured attachment (its bytes live in a sibling blob file).
    struct Attachment: Codable, Sendable {
        /// Original display name, e.g. `photo.jpg`.
        var filename: String
        /// The blob's file name within the inbox directory.
        var storedName: String
        /// The attachment's UTI, if known.
        var contentType: String?
        /// Whether to embed it as an image (vs. link it as a file) in the note.
        var isImage: Bool
    }

    /// One captured share: text/URL plus any attachments.
    struct Item: Codable, Identifiable, Sendable {
        var id = UUID()
        var title: String
        var urlString: String?
        var text: String?
        var date = Date()
        var attachments: [Attachment] = []

        /// Renders the captured share as a Markdown note body, embedding images
        /// and linking files into the exported `_attachments/` folder.
        var markdown: String {
            var lines = ["# \(title.isEmpty ? "Shared" : title)", ""]
            if let urlString, !urlString.isEmpty {
                lines.append("[\(urlString)](\(urlString))")
                lines.append("")
            }
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(text)
                lines.append("")
            }
            for attachment in attachments {
                let encoded = attachment.filename
                    .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? attachment.filename
                let path = "_attachments/\(encoded)"
                lines.append(attachment.isImage
                    ? "![\(attachment.filename)](\(path))"
                    : "[📄 \(attachment.filename)](\(path))")
                lines.append("")
            }
            lines.append("#clipped")
            return lines.joined(separator: "\n")
        }
    }

    // MARK: Paths

    private static var inboxDir: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("inbox", isDirectory: true)
    }

    /// The inbox directory, created if needed.
    private static func ensureInbox() -> URL? {
        guard let dir = inboxDir else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Write side (extension)

    /// Copies an attachment file into the inbox and returns its reference, or
    /// `nil` if it can't be stored (missing, too large, or a copy failure).
    static func storeAttachment(at source: URL, filename: String, contentType: String?, isImage: Bool) -> Attachment? {
        guard let dir = ensureInbox() else { return nil }

        // Guard against oversized captures (videos etc.).
        if let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxAttachmentBytes {
            return nil
        }

        let safeName = sanitize(filename)
        let storedName = "\(UUID().uuidString)-\(safeName)"
        let dest = dir.appendingPathComponent(storedName)
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: source, to: dest)
            return Attachment(filename: safeName, storedName: storedName, contentType: contentType, isImage: isImage)
        } catch {
            return nil
        }
    }

    /// Appends an item to the inbox (writes its JSON file last, after its blobs).
    static func append(_ item: Item) {
        guard let dir = ensureInbox(),
              let data = try? JSONEncoder().encode(item) else { return }
        let url = dir.appendingPathComponent("\(item.id.uuidString).json")
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Read side (app)

    /// All pending items, oldest first.
    static func pendingItems() -> [Item] {
        guard let dir = inboxDir,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Item.self, from: $0) } }
            .sorted { $0.date < $1.date }
    }

    /// The bytes for an attachment, if still present.
    static func attachmentData(for attachment: Attachment) -> Data? {
        guard let dir = inboxDir else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(attachment.storedName))
    }

    /// Removes an item and all its attachment blobs (after a successful drain).
    static func remove(_ item: Item) {
        guard let dir = inboxDir else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(item.id.uuidString).json"))
        for attachment in item.attachments {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(attachment.storedName))
        }
    }

    // MARK: Helpers

    /// A filesystem-safe version of a name (no slashes / control chars).
    private static func sanitize(_ name: String) -> String {
        let trimmed = name.isEmpty ? "file" : name
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = trimmed.components(separatedBy: illegal).joined(separator: "_")
        return String(cleaned.prefix(120))
    }
}
