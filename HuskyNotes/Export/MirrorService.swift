//
//  MirrorService.swift
//  HuskyNotes
//
//  Continuous `.md` mirror: when enabled and pointed at a folder, the store is
//  written out to real Markdown files (store → files) so the user's notes always
//  exist as portable `.md` on disk — the openness guarantee. The chosen folder
//  is remembered across launches via a security-scoped bookmark.
//
//  Direction: store → files (one-way) for v1. A safe two-way mirror (external
//  edits flowing back in, with conflict handling) is a deliberate later step —
//  see the TODO. The website lists "two-way"; this ships the reliable half first.
//

import Foundation
import SwiftData

/// Manages the opt-in continuous Markdown mirror and its destination folder.
@MainActor
enum MirrorService {

    private static let enabledKey = "huskynotes.mirrorEnabled"
    private static let bookmarkKey = "huskynotes.mirrorBookmark"

    private static let defaults = UserDefaults.standard

    /// Whether continuous mirroring is switched on.
    static var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    /// A display path for the chosen folder, if any (for settings UI).
    static var folderDisplayPath: String? {
        resolveFolder()?.path(percentEncoded: false)
    }

    /// Records the user's chosen destination folder as a security-scoped
    /// bookmark so it survives relaunches and the sandbox.
    static func setFolder(_ url: URL) {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        let didScope = url.startAccessingSecurityScopedResource()
        defer { if didScope { url.stopAccessingSecurityScopedResource() } }
        if let data = try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(data, forKey: bookmarkKey)
        }
    }

    /// Clears the saved destination folder.
    static func clearFolder() {
        defaults.removeObject(forKey: bookmarkKey)
    }

    /// Mirrors notes to the chosen folder, if mirroring is on and a folder is
    /// set. **Locked notes are excluded** so their plaintext never lands in the
    /// mirror folder. Safe to call frequently (e.g. after edits). Returns
    /// silently if disabled or unconfigured.
    ///
    /// - Note: A note locked *after* it was already mirrored leaves its earlier
    ///   `.md` on disk — this skips future writes but doesn't delete existing
    ///   files. A sweep that removes stale/locked files is a later refinement.
    static func mirrorIfEnabled(context: ModelContext) {
        guard isEnabled, let folder = resolveFolder() else { return }
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        export(notes.filter { !$0.isLocked }, to: folder)
    }

    /// Performs a one-shot export of `notes` to `folder` (used by mirroring and
    /// by the manual "Export Now" command).
    @discardableResult
    static func export(_ notes: [Note], to folder: URL) -> Bool {
        let didScope = folder.startAccessingSecurityScopedResource()
        defer { if didScope { folder.stopAccessingSecurityScopedResource() } }
        do {
            try MarkdownExporter().export(notes, to: folder)
            return true
        } catch {
            return false
        }
    }

    /// Exports all non-trashed notes into a single combined `.md` file
    /// (advanced export). Returns the number of notes written, or nil on failure.
    @discardableResult
    static func exportCombined(_ notes: [Note], to folder: URL) -> Int? {
        let didScope = folder.startAccessingSecurityScopedResource()
        defer { if didScope { folder.stopAccessingSecurityScopedResource() } }
        let included = notes.filter { !$0.isTrashed }
        let body = included
            .map { frontmatter(for: $0) + "\n\n" + $0.body }
            .joined(separator: "\n\n\n")
        let url = folder.appendingPathComponent("HuskyNotes-Combined.md")
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            return included.count
        } catch {
            return nil
        }
    }

    /// Two-way import: reads the `.md` files in the mirror folder and reconciles
    /// them back into the store, matching by frontmatter `id`. Newer files (by
    /// the frontmatter `modified` date) overwrite the note; unknown ids create
    /// new notes. Manual + last-write-wins — a safe step toward full two-way
    /// sync without a background file watcher.
    ///
    /// - Returns: the number of notes created or updated.
    @discardableResult
    static func importChanges(context: ModelContext) -> Int {
        guard let folder = resolveFolder() else { return 0 }
        let didScope = folder.startAccessingSecurityScopedResource()
        defer { if didScope { folder.stopAccessingSecurityScopedResource() } }

        let allNotes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        var byID: [UUID: Note] = [:]
        for note in allNotes { byID[note.id] = note }

        var changed = 0
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "md" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let parsed = Frontmatter.parseDocument(text)
            guard let frontmatter = parsed.frontmatter else { continue } // only id'd notes

            if let existing = byID[frontmatter.id] {
                if frontmatter.modified > existing.modifiedAt, existing.body != parsed.body {
                    existing.body = parsed.body
                    existing.modifiedAt = frontmatter.modified
                    existing.recomputeTitle()
                    TagReconciler.reconcile(existing, in: context)
                    changed += 1
                }
            } else {
                let note = Note(
                    id: frontmatter.id,
                    body: parsed.body,
                    createdAt: frontmatter.created,
                    modifiedAt: frontmatter.modified,
                    isPinned: frontmatter.pinned
                )
                note.recomputeTitle()
                context.insert(note)
                TagReconciler.reconcile(note, in: context)
                changed += 1
            }
        }
        return changed
    }

    /// Resolves the saved bookmark back into a usable folder URL.
    private static func resolveFolder() -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        return url
    }

    // TODO (v0.4+): two-way mirror. Watch the folder with an NSFilePresenter /
    // DispatchSource, parse changed `.md` via Frontmatter.parseDocument, and
    // reconcile back into the store by `id` with conflict handling. Hazardous —
    // ship one-way first.
}
