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

    /// Mirrors all non-trashed notes to the chosen folder, if mirroring is on and
    /// a folder is set. Safe to call frequently (e.g. after edits) — it's a
    /// straight re-export. Returns silently if disabled or unconfigured.
    static func mirrorIfEnabled(context: ModelContext) {
        guard isEnabled, let folder = resolveFolder() else { return }
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        export(notes, to: folder)
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
