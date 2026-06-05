//
//  SmartList.swift
//  HuskyNotes
//
//  The fixed "smart lists" shown in the sidebar (All, Pinned, Today, …) plus a
//  case for an individual tag. Each case knows its own display title and SF
//  Symbol so the sidebar can render it without any extra mapping tables.
//

import Foundation

/// A selectable filter shown in the sidebar.
///
/// The first six cases are built-in "smart" filters; ``tag(_:)`` represents a
/// user tag. `Hashable`/`Identifiable` conformance lets it drive a SwiftUI
/// `List` selection and `NavigationSplitView` detail routing.
enum SmartList: Hashable, Identifiable {
    /// All notes that are not archived or trashed.
    case all
    /// Pinned notes.
    case pinned
    /// Notes modified today.
    case today
    /// Open task items (`- [ ]`) gathered from every note.
    case todo
    /// Notes that carry no tags.
    case untagged
    /// Archived notes.
    case archived
    /// Trashed notes.
    case trash
    /// A single user tag.
    case tag(Tag)
    /// A single user-created folder.
    case folder(Folder)

    /// Stable identity for SwiftUI selection.
    ///
    /// The fixed cases use constant strings; ``tag(_:)`` uses the tag's UUID so
    /// distinct tags remain distinct selections.
    var id: String {
        switch self {
        case .all:      return "smartlist.all"
        case .pinned:   return "smartlist.pinned"
        case .today:    return "smartlist.today"
        case .todo:     return "smartlist.todo"
        case .untagged: return "smartlist.untagged"
        case .archived: return "smartlist.archived"
        case .trash:    return "smartlist.trash"
        case .tag(let tag): return "smartlist.tag.\(tag.id.uuidString)"
        case .folder(let folder): return "smartlist.folder.\(folder.id.uuidString)"
        }
    }

    /// Human-readable title for the row / navigation bar.
    var title: String {
        switch self {
        case .all:      return "All Notes"
        case .pinned:   return "Pinned"
        case .today:    return "Today"
        case .todo:     return "To-Do"
        case .untagged: return "Untagged"
        case .archived: return "Archive"
        case .trash:    return "Trash"
        case .tag(let tag): return tag.name.isEmpty ? "Untitled Tag" : tag.name
        case .folder(let folder): return folder.name.isEmpty ? "Untitled Folder" : folder.name
        }
    }

    /// SF Symbol name used for the row's leading icon.
    var systemImage: String {
        switch self {
        case .all:      return "note.text"
        case .pinned:   return "pin"
        case .today:    return "calendar"
        case .todo:     return "checklist"
        case .untagged: return "tag.slash"
        case .archived: return "archivebox"
        case .trash:    return "trash"
        case .tag:      return "number"
        case .folder:   return "folder"
        }
    }

    /// The ordered list of built-in smart lists (excludes per-tag cases).
    static var fixed: [SmartList] {
        [.all, .pinned, .today, .todo, .untagged, .archived, .trash]
    }
}
