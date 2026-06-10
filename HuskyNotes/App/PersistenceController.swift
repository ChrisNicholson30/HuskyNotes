//
//  PersistenceController.swift
//  HuskyNotes
//
//  Owns the SwiftData `ModelContainer` and the iCloud-sync state.
//
//  Sync is the user's own **private** CloudKit database, never a server. The
//  controller is `@Observable`, so flipping sync on/off rebuilds the store and
//  swaps it in **live** — no relaunch. Both the local and CloudKit stores use the
//  same on-disk file, so existing notes simply begin mirroring (nothing is moved
//  or duplicated). Sync defaults **on** when an iCloud identity is available, so a
//  fresh install just works across the user's devices.
//

import Foundation
import SwiftData
import Observation

/// Builds, vends, and live-swaps the app's SwiftData container.
@MainActor
@Observable
final class PersistenceController {

    /// The shared instance used by the running app.
    @MainActor static let shared = PersistenceController()

    /// The SwiftData container backing the whole app. Reassigned when sync is
    /// toggled; reading it in a SwiftUI body re-injects the new store automatically.
    private(set) var container: ModelContainer

    /// Whether the current container is mirroring to CloudKit (sync active).
    private(set) var isSyncing: Bool

    /// The CloudKit container identifier for the user's private database.
    static let cloudKitContainerID = "iCloud.com.huskynotes.app"

    /// UserDefaults key recording the user's sync preference.
    static let syncEnabledKey = "huskynotes.syncEnabled"

    /// The full schema: every `@Model` type the app persists.
    private static let schema = Schema([Note.self, Tag.self, Folder.self, Attachment.self, TodoItem.self])

    init() {
        let (container, syncing) = Self.makeContainer(sync: Self.syncPreferenceEnabled)
        self.container = container
        self.isSyncing = syncing
    }

    /// The user's sync preference. Defaults to **on** the first time (a notes app
    /// should sync across devices out of the box), and is only honoured when an
    /// iCloud identity is actually present (otherwise the store stays local).
    static var syncPreferenceEnabled: Bool {
        if UserDefaults.standard.object(forKey: syncEnabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: syncEnabledKey)
    }

    /// Whether iCloud is currently available (signed in + entitlement present).
    var iCloudAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    /// Turns sync on/off **live** — rebuilds the store on the same file with (or
    /// without) CloudKit mirroring and swaps it in. No relaunch. `@Observable`
    /// re-injects the new container; the posted notification lets the UI drop any
    /// model object it was holding from the old store.
    func setSyncEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.syncEnabledKey)
        let (container, syncing) = Self.makeContainer(sync: enabled)
        self.container = container
        self.isSyncing = syncing
        NotificationCenter.default.post(name: .huskyStoreDidChange, object: nil)
    }

    // MARK: - Container building

    /// Builds a container: CloudKit-mirrored when `sync` is on *and* an iCloud
    /// identity exists, else local. Falls back to local (then in-memory) so the
    /// app always launches. Returns the container and whether it's syncing.
    private static func makeContainer(sync: Bool) -> (ModelContainer, Bool) {
        // Only attempt CloudKit when sync is wanted AND an iCloud identity is
        // available — the token is non-nil only with the entitlement + a signed-in
        // user, which avoids the async mirroring delegate trapping otherwise.
        if sync, FileManager.default.ubiquityIdentityToken != nil {
            let cloud = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
                return (container, true)
            }
            // Couldn't stand up the cloud store — fall back to local below.
        }

        let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let container = try? ModelContainer(for: schema, configurations: [local]) {
            return (container, false)
        }

        // The store failed to open — most often an incompatible schema from an
        // earlier build. Move it aside (kept as `.bak`) and start fresh rather than
        // crash-loop.
        relocateStore(at: local.url)
        if let container = try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]) {
            return (container, false)
        }

        // Last resort: in-memory so the app still launches.
        if let memory = try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]) {
            return (memory, false)
        }

        fatalError("Could not create any ModelContainer.")
    }

    /// Moves an unreadable store (and its `-wal`/`-shm` sidecars) aside to a
    /// `.bak`, so a fresh store can be created without destroying the old data.
    private static func relocateStore(at url: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let backup = URL(fileURLWithPath: source.path + ".bak")
            try? fileManager.removeItem(at: backup)
            try? fileManager.moveItem(at: source, to: backup)
        }
    }

    /// An in-memory container seeded with a couple of sample notes, for previews.
    @MainActor
    static let preview: ModelContainer = {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let welcome = Note(body: WelcomeNote.markdown, createdAt: .now, modifiedAt: .now, isPinned: true)
        welcome.recomputeTitle()
        context.insert(welcome)

        let scratch = Note(body: "# Scratchpad\n\nQuick thoughts go here. #ideas")
        scratch.recomputeTitle()
        context.insert(scratch)

        return container
    }()
}

extension Notification.Name {
    /// Posted when the SwiftData container is swapped (sync toggled), so views can
    /// drop any model object held from the previous store.
    static let huskyStoreDidChange = Notification.Name("huskynotes.storeDidChange")
}
