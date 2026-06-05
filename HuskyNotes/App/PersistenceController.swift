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

    /// The container used by the live app.
    static let shared = PersistenceController()

    /// The SwiftData container backing the whole app.
    let container: ModelContainer

    /// Whether the container is mirroring to CloudKit (sync on) or local-only.
    let isSyncing: Bool

    /// The CloudKit container identifier for the private database.
    static let cloudKitContainerID = "iCloud.com.huskynotes.app"

    /// UserDefaults key toggling iCloud sync (read at launch; relaunch to apply).
    static let syncEnabledKey = "huskynotes.syncEnabled"

    /// The full schema: every `@Model` type the app persists.
    private static let schema = Schema([Note.self, Tag.self, Attachment.self])

    /// Creates a container.
    ///
    /// When iCloud sync is enabled (Settings → Storage) **and** the app is built
    /// with the iCloud/CloudKit entitlement + container, the store mirrors to the
    /// user's *private* CloudKit database. If the cloud container can't be
    /// created (no entitlement, not signed into iCloud, etc.) we fall back to a
    /// local store so the app always launches.
    ///
    /// - Parameter inMemory: when `true`, nothing is written to disk — used for
    ///   previews and tests.
    init(inMemory: Bool = false) {
        let local = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: inMemory)

        // Only attempt CloudKit when the user enabled it AND an iCloud identity is
        // actually available. The identity token is non-nil only when the app has
        // the iCloud entitlement and the user is signed in — so this avoids the
        // async `NSCloudKitMirroringDelegate` setup trapping on unsigned builds,
        // simulators with no iCloud account, or a misconfigured container.
        let wantsSync = !inMemory
            && UserDefaults.standard.bool(forKey: Self.syncEnabledKey)
            && FileManager.default.ubiquityIdentityToken != nil

        if wantsSync {
            let cloud = ModelConfiguration(
                schema: Self.schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(Self.cloudKitContainerID)
            )
            if let container = try? ModelContainer(for: Self.schema, configurations: [cloud]) {
                self.container = container
                self.isSyncing = true
                return
            }
            // Couldn't stand up the cloud store — fall back to local below.
        }

        do {
            container = try ModelContainer(for: Self.schema, configurations: [local])
            isSyncing = false
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
