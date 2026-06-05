//
//  TagReconciler.swift
//  HuskyNotes
//
//  Husky Notes' tags are *derived* from inline `#hashtags` in a note's Markdown
//  body — the body stays canonical, and the `Tag` relationship is a denormalised
//  index kept in sync on save (see DESIGN §4). This file holds the pure parser
//  (`TagParser`) and the SwiftData reconciliation (`TagReconciler`).
//

import Foundation
import SwiftData

/// Extracts inline `#tag` names from Markdown source.
enum TagParser {

    /// A `#tag` is a `#` (not part of a heading, URL fragment, or `##`) followed
    /// by a word character and optional nested `/sub` segments, e.g.
    /// `#work`, `#work/clients`, `#q3-2026`. Because the first character after
    /// `#` must be a tag character (not a space), ATX headings (`# Title`) are
    /// naturally excluded.
    private static let pattern =
        "(?<![\\w/#])#([A-Za-z0-9_][A-Za-z0-9_-]*(?:/[A-Za-z0-9_-]+)*)"

    /// Returns the distinct tag names found in `markdown`, in first-seen order,
    /// without the leading `#`. De-duplication is case-insensitive.
    static func tagNames(in markdown: String) -> [String] {
        guard
            !markdown.isEmpty,
            let regex = try? NSRegularExpression(pattern: pattern)
        else { return [] }

        let ns = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))

        var seen = Set<String>()
        var ordered: [String] = []
        for match in matches where match.numberOfRanges > 1 {
            let name = ns.substring(with: match.range(at: 1))
            let key = name.lowercased()
            if seen.insert(key).inserted {
                ordered.append(name)
            }
        }
        return ordered
    }

    /// Returns `markdown` with every standalone occurrence of `#name` removed
    /// (case-insensitively) — the body is canonical, so stripping the text is what
    /// actually deletes the tag, otherwise it would be re-derived on the next save.
    ///
    /// Only the exact tag is removed: deleting `work` strips `#work` but leaves
    /// `#workflow`, `#work-item` and the nested tag `#work/clients` untouched.
    static func removing(tagNamed name: String, from markdown: String) -> String {
        guard !name.isEmpty, !markdown.isEmpty else { return markdown }
        let escaped = NSRegularExpression.escapedPattern(for: name)
        // Same boundaries as `pattern`, anchored to this exact name, with a
        // trailing guard so a longer tag (more name chars, `-`, or `/sub`) is kept.
        let exact = "(?<![\\w/#])#\(escaped)(?![A-Za-z0-9_/-])"
        guard let regex = try? NSRegularExpression(pattern: exact, options: [.caseInsensitive]) else {
            return markdown
        }
        let ns = markdown as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.stringByReplacingMatches(in: markdown, options: [], range: range, withTemplate: "")
    }
}

/// Reconciles a note's `Tag` relationship with the `#tags` in its body.
///
/// Existing `Tag` rows are reused (matched case-insensitively by name); missing
/// ones are created; tags left with no notes are pruned so the sidebar never
/// shows empty tags.
@MainActor
enum TagReconciler {

    /// Re-derives `note.tags` from `note.body`. A no-op when nothing changed.
    static func reconcile(_ note: Note, in context: ModelContext) {
        let desired = TagParser.tagNames(in: note.body)
        let desiredKeys = Set(desired.map { $0.lowercased() })
        let currentKeys = Set((note.tags ?? []).map { $0.name.lowercased() })

        guard desiredKeys != currentKeys else { return }

        let allTags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        var byName: [String: Tag] = [:]
        for tag in allTags { byName[tag.name.lowercased()] = tag }

        var newTags: [Tag] = []
        for name in desired {
            if let existing = byName[name.lowercased()] {
                newTags.append(existing)
            } else {
                let tag = Tag(name: name)
                context.insert(tag)
                byName[name.lowercased()] = tag
                newTags.append(tag)
            }
        }
        note.tags = newTags

        // Prune only tags that are *not* among the ones we just assigned, so a
        // freshly-attached tag can't be deleted if its inverse `notes`
        // relationship hasn't propagated yet. We'd rather leave a rare orphan
        // (cleaned up next pass) than drop a tag that's actually in use.
        let keepIDs = Set(newTags.map(\.id))
        prune(allTags, keeping: keepIDs, in: context)
    }

    /// Deletes tags with no remaining notes, except any whose id is in `keepIDs`.
    private static func prune(_ tags: [Tag], keeping keepIDs: Set<UUID>, in context: ModelContext) {
        for tag in tags where !keepIDs.contains(tag.id) && (tag.notes ?? []).isEmpty {
            context.delete(tag)
        }
    }
}
