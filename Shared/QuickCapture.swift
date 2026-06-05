//
//  QuickCapture.swift
//  HuskyNotes  +  HuskyNotes-Widgets  (shared source)
//
//  A small hand-off, stored in the shared App Group defaults, used by the
//  "New Note" Control / widget to ask the app to open a fresh note — optionally
//  filed into a chosen folder. The control runs an App Intent that records the
//  request (and target folder) and launches the app; the app consumes it on
//  activation and creates + focuses the note.
//
//  Foundation-only so it compiles into the app and the widget extension alike.
//

import Foundation

/// Quick-capture hand-off between the widget/control and the app.
enum QuickCapture {

    /// The App Group both targets share.
    static let appGroupID = "group.com.huskynotes.app"

    private static let pendingNewNoteKey = "huskynotes.pendingNewNote"
    private static let pendingFolderKey = "huskynotes.pendingNewNoteFolder"
    private static let folderNamesKey = "huskynotes.folderNames"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // MARK: New-note request

    /// Requests that the app open a new note, optionally in `folderName`
    /// (nil / empty → the general Notes list).
    static func requestNewNote(inFolderNamed folderName: String? = nil) {
        guard let defaults else { return }
        defaults.set(true, forKey: pendingNewNoteKey)
        if let folderName, !folderName.isEmpty {
            defaults.set(folderName, forKey: pendingFolderKey)
        } else {
            defaults.removeObject(forKey: pendingFolderKey)
        }
    }

    /// Returns (and clears) any pending new-note request and its target folder.
    static func consumePendingNewNote() -> (pending: Bool, folderName: String?) {
        guard let defaults, defaults.bool(forKey: pendingNewNoteKey) else { return (false, nil) }
        defaults.set(false, forKey: pendingNewNoteKey)
        let folder = defaults.string(forKey: pendingFolderKey)
        defaults.removeObject(forKey: pendingFolderKey)
        return (true, folder)
    }

    // MARK: Folder list (for the widget's picker)

    /// Publishes the user's folder names so the widget's folder picker can offer
    /// them (the widget can't read the SwiftData store directly).
    static func publishFolderNames(_ names: [String]) {
        defaults?.set(names, forKey: folderNamesKey)
    }

    /// The folder names last published by the app.
    static func availableFolderNames() -> [String] {
        defaults?.stringArray(forKey: folderNamesKey) ?? []
    }
}
