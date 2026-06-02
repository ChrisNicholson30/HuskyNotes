//
//  PersistenceController.swift
//  HuskyNotes
//
//  Owns the SwiftData `ModelContainer`.
//
//  v0.1 is **local-only** — notes live in an on-device SQLite store and there is
//  no sync. v0.2 turns on CloudKit by switching the `ModelConfiguration` to use
//  `cloudKitDatabase: .private` (see the commented line below). The model types
//  were written to the CloudKit mirroring rules from day one (every property
//  defaulted, every relationship optional), so that switch is the only change.
//

import Foundation
import SwiftData

/// Builds and vends the app's SwiftData container.
///
/// Use ``shared`` for the running app and ``preview`` for SwiftUI previews and
/// tests (an in-memory container seeded with sample notes).
struct PersistenceController {

    /// The container used by the live app (on-disk, local-only for v0.1).
    static let shared = PersistenceController()

    /// The SwiftData container backing the whole app.
    let container: ModelContainer

    /// The full schema: every `@Model` type the app persists.
    private static let schema = Schema([Note.self, Tag.self, Attachment.self])

    /// Creates a container.
    ///
    /// - Parameter inMemory: when `true`, nothing is written to disk — used for
    ///   previews and tests.
    init(inMemory: Bool = false) {
        // v0.1 — local store only.
        let configuration = ModelConfiguration(
            schema: Self.schema,
            isStoredInMemoryOnly: inMemory
        )

        // v0.2 — flip to CloudKit private-DB sync by replacing the line above with:
        //
        //   let configuration = ModelConfiguration(
        //       schema: Self.schema,
        //       isStoredInMemoryOnly: inMemory,
        //       cloudKitDatabase: .private("iCloud.com.huskynotes.app")
        //   )
        //
        // (also requires the iCloud + CloudKit capability and container — see
        //  resources/BUILD_PLAN.md §5 v0.2.)

        do {
            container = try ModelContainer(for: Self.schema, configurations: [configuration])
        } catch {
            // A container we cannot create is unrecoverable; fail loudly in dev.
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// An in-memory container seeded with a couple of sample notes, for previews.
    @MainActor
    static let preview: ModelContainer = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.mainContext

        let welcome = Note(
            body: Self.welcomeMarkdown,
            createdAt: .now,
            modifiedAt: .now,
            isPinned: true
        )
        welcome.recomputeTitle()
        context.insert(welcome)

        let scratch = Note(body: "# Scratchpad\n\nQuick thoughts go here. #ideas")
        scratch.recomputeTitle()
        context.insert(scratch)

        return controller.container
    }()

    /// Sample Markdown used to seed the preview container. Mirrors
    /// `Resources/SampleNotes/welcome.md`.
    private static let welcomeMarkdown = """
    # Welcome to Husky Notes

    Markdown notes you'll love, sync you can trust.

    - Live, themed rendering
    - Plain `.md` underneath — always yours
    - Six beautiful themes

    > Reliability over cleverness.

    ```swift
    let store = try ModelContainer(for: Note.self)
    ```

    Tag things inline like #welcome and they become smart lists.
    """
}
