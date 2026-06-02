//
//  MarkdownExporter.swift
//  HuskyNotes
//
//  One-shot export of notes to a folder of plain `.md` files — the "your data
//  is never trapped" guarantee. Each file is YAML frontmatter (see
//  `Frontmatter`) followed by the note's body, preserved **verbatim** so an
//  export round-trips losslessly and can be re-imported (matched by `id`).
//
//  Layout produced:
//
//      <folder>/
//        <tag-path>/<safe-title>.md      (notes filed under their first tag)
//        <safe-title>.md                 (untagged notes at the root)
//        _attachments/<filename>         (attachment binaries)
//
//  v0.1/v0.4 ships the one-shot export below. The opt-in *continuous mirror*
//  (store → files, file-coordination safe) is a later milestone — see TODO.
//

import Foundation

/// Exports notes to a folder of CommonMark `.md` files with YAML frontmatter.
struct MarkdownExporter {

    /// Errors thrown during export.
    enum ExportError: Error {
        /// The destination could not be created or written to.
        case cannotWrite(URL, underlying: Error)
    }

    /// The file manager used for all I/O (injectable for testing).
    private let fileManager: FileManager

    /// Creates an exporter.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Exports the given notes into `folder`.
    ///
    /// Trashed notes are skipped. Notes are filed into a subfolder derived from
    /// their first tag's name (a tag like `work/clients` becomes nested
    /// folders); untagged notes are written at the root. Filenames are
    /// sanitised and de-duplicated so two notes that share a title don't clash.
    ///
    /// - Parameters:
    ///   - notes: the notes to export.
    ///   - folder: the destination directory (created if needed).
    func export(_ notes: [Note], to folder: URL) throws {
        try ensureDirectory(folder)

        // Track used filenames per directory to de-duplicate clashes.
        var usedNames: [String: Set<String>] = [:]

        for note in notes where !note.isTrashed {
            let directory = try directory(for: note, in: folder)
            let dirKey = directory.path

            let baseName = Self.sanitise(note.title.isEmpty ? "Untitled" : note.title)
            var taken = usedNames[dirKey] ?? []
            let fileName = Self.uniqueName(baseName, in: taken)
            taken.insert(fileName.lowercased())
            usedNames[dirKey] = taken

            let fileURL = directory.appendingPathComponent(fileName).appendingPathExtension("md")
            let contents = frontmatter(for: note) + "\n\n" + note.body

            do {
                try contents.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                throw ExportError.cannotWrite(fileURL, underlying: error)
            }

            try exportAttachments(of: note, to: folder)
        }
    }

    // MARK: - Attachments

    /// Writes a note's attachment binaries into `<folder>/_attachments/`.
    private func exportAttachments(of note: Note, to folder: URL) throws {
        let attachments = (note.attachments ?? []).filter { $0.data != nil }
        guard !attachments.isEmpty else { return }

        let dir = folder.appendingPathComponent("_attachments", isDirectory: true)
        try ensureDirectory(dir)

        var taken = (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
        for attachment in attachments {
            guard let data = attachment.data else { continue }
            let base = Self.sanitise(
                (attachment.filename as NSString).deletingPathExtension.isEmpty
                    ? attachment.id.uuidString
                    : (attachment.filename as NSString).deletingPathExtension
            )
            let ext = (attachment.filename as NSString).pathExtension
            let unique = Self.uniqueName(base, in: Set(taken.map { $0.lowercased() }))
            let name = ext.isEmpty ? unique : "\(unique).\(ext)"
            taken.append(name)

            let url = dir.appendingPathComponent(name)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw ExportError.cannotWrite(url, underlying: error)
            }
        }
    }

    // TODO: Continuous mirror (opt-in): observe the store and keep `folder` in
    // sync (store → files), using NSFileCoordinator so it's safe in iCloud
    // Drive. Two-way mirror is post-1.0. See resources/BUILD_PLAN.md §5 v0.4.

    // MARK: - Paths

    /// The directory a note should be written into, creating it if needed.
    private func directory(for note: Note, in root: URL) throws -> URL {
        guard let firstTag = (note.tags ?? []).first?.name, !firstTag.isEmpty else {
            return root
        }
        // A tag like "work/clients" becomes nested folders; sanitise each part.
        let components = firstTag
            .split(separator: "/")
            .map { Self.sanitise(String($0)) }
            .filter { !$0.isEmpty }

        var dir = root
        for component in components {
            dir.appendPathComponent(component, isDirectory: true)
        }
        try ensureDirectory(dir)
        return dir
    }

    /// Creates a directory (and intermediates) if it doesn't already exist.
    private func ensureDirectory(_ url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw ExportError.cannotWrite(url, underlying: error)
        }
    }

    // MARK: - Filename hygiene

    /// Characters not allowed (or unwise) in a cross-platform filename.
    private static let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")

    /// Produces a safe, trimmed filename base from arbitrary text.
    static func sanitise(_ raw: String) -> String {
        let cleaned = raw
            .components(separatedBy: illegal).joined(separator: "-")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let result = String(cleaned.prefix(120))
        return result.isEmpty ? "Untitled" : result
    }

    /// Returns `base`, or `base 2`, `base 3`, … so it doesn't collide with an
    /// already-used name (case-insensitive) in the same directory.
    static func uniqueName(_ base: String, in taken: Set<String>) -> String {
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}
