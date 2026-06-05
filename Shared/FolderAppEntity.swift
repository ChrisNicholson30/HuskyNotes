//
//  FolderAppEntity.swift
//  HuskyNotes  +  HuskyNotes-Widgets  (shared source)
//
//  An App Intents entity representing a target folder, so the "New Note" widget
//  and Shortcuts can offer a folder picker. Folder names are read from the App
//  Group (published by the app) — the widget never touches the SwiftData store.
//

import AppIntents

/// A folder the user can target for a quick new note.
struct FolderAppEntity: AppEntity {

    /// The folder name doubles as the stable id.
    var id: String
    var name: String

    init(id: String) { self.id = id; self.name = id }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Folder" }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    static let defaultQuery = FolderEntityQuery()
}

/// Supplies folder choices from the App Group's published list.
struct FolderEntityQuery: EntityQuery {

    func entities(for identifiers: [String]) async throws -> [FolderAppEntity] {
        identifiers.map(FolderAppEntity.init(id:))
    }

    func suggestedEntities() async throws -> [FolderAppEntity] {
        QuickCapture.availableFolderNames().map(FolderAppEntity.init(id:))
    }
}
