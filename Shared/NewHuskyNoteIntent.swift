//
//  NewHuskyNoteIntent.swift
//  HuskyNotes  +  HuskyNotes-Widgets  (shared source)
//
//  The App Intent behind the "New Note" Control (Action Button / Control
//  Centre), the home-screen widget, and Shortcuts/Siri. It records a pending
//  new note (with an optional target folder) and launches the app, which opens
//  a fresh, focused note on activation.
//
//  Compiled into both the app and the widget extension so the system can route
//  `openAppWhenRun` to the main app.
//

import AppIntents

/// Opens Husky Notes straight into a new note, optionally in a folder.
struct NewHuskyNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New Note"
    static let description = IntentDescription("Open Husky Notes and start a new note.")

    /// Bring the app to the foreground so the user can type immediately.
    static let openAppWhenRun = true

    /// Optional target folder; nil files the note in the general Notes list.
    @Parameter(title: "Folder")
    var folder: FolderAppEntity?

    init() {}
    init(folder: FolderAppEntity?) { self.folder = folder }

    func perform() async throws -> some IntentResult {
        QuickCapture.requestNewNote(inFolderNamed: folder?.name)
        return .result()
    }
}
