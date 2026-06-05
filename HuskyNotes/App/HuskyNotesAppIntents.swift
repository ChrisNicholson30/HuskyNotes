//
//  HuskyNotesAppIntents.swift
//  HuskyNotes
//
//  App Intents → Shortcuts + Siri integration. Lets users capture into the vault
//  without opening the app ("Hey Siri, create a note in Husky Notes"), and build
//  automations. Intents run in the app process and write straight to the shared
//  SwiftData container, then reconcile tags like any other edit.
//

import AppIntents
import SwiftData

/// Creates a new note from supplied text.
struct CreateNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Note"
    static let description = IntentDescription("Creates a new note in Husky Notes.")

    @Parameter(title: "Text", requestValueDialog: "What should the note say?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let context = PersistenceController.shared.container.mainContext
        let note = Note(body: text, createdAt: .now, modifiedAt: .now)
        note.recomputeTitle()
        context.insert(note)
        TagReconciler.reconcile(note, in: context)
        try? context.save()

        let name = note.title.isEmpty ? "Untitled" : note.title
        return .result(value: name, dialog: "Created “\(name)” in Husky Notes.")
    }
}

/// Appends text to the most recently modified note (creating one if the vault is
/// empty) — a fast "add to my running note" capture.
struct AppendToLastNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Append to Last Note"
    static let description = IntentDescription("Adds text to your most recently edited note.")

    @Parameter(title: "Text", requestValueDialog: "What should I add?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PersistenceController.shared.container.mainContext
        var descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { !$0.isTrashed },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        let note: Note
        if let latest = try? context.fetch(descriptor).first {
            note = latest
            note.body += (note.body.isEmpty ? "" : "\n") + text
        } else {
            note = Note(body: text, createdAt: .now, modifiedAt: .now)
            context.insert(note)
        }
        note.modifiedAt = .now
        note.recomputeTitle()
        TagReconciler.reconcile(note, in: context)
        try? context.save()

        let name = note.title.isEmpty ? "your note" : "“\(note.title)”"
        return .result(dialog: "Added to \(name).")
    }
}

/// Exposes the intents to Siri and the Shortcuts gallery with spoken phrases.
struct HuskyNotesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "New \(.applicationName) note",
                "Add a note to \(.applicationName)"
            ],
            shortTitle: "Create Note",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: AppendToLastNoteIntent(),
            phrases: [
                "Append to my last \(.applicationName) note",
                "Add to my \(.applicationName) note"
            ],
            shortTitle: "Append to Last Note",
            systemImageName: "text.append"
        )
    }
}
