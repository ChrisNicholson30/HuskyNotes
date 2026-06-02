//
//  HuskyNotesApp.swift
//  HuskyNotes
//
//  The `@main` entry point. Creates the shared `ThemeStore`, injects the
//  SwiftData container and the theme into the environment, and matches the
//  system colour scheme to the active theme's appearance.
//

import SwiftUI
import SwiftData

/// The Husky Notes application.
@main
struct HuskyNotesApp: App {

    /// The app-wide theme store. Owned here, injected into every view.
    @State private var themeStore = ThemeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(themeStore)
                // Match the system appearance to the active theme so SwiftUI
                // chrome (menus, alerts) reads correctly in light/dark themes.
                .preferredColorScheme(themeStore.active.isDark ? .dark : .light)
        }
        .modelContainer(PersistenceController.shared.container)
        #if os(macOS)
        .commands {
            // Placeholder for v1.0 menu commands (new note, export, focus mode…).
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    NotificationCenter.default.post(name: .huskyNewNote, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        // A native Settings window hosting the theme picker.
        Settings {
            ThemeSettingsView()
                .environment(themeStore)
                .frame(width: 480, height: 420)
        }
        #endif
    }
}

extension Notification.Name {
    /// Posted when the user invokes the "New Note" menu command (macOS).
    /// - TODO: Wire this through to `NoteListView`'s insert in a later milestone.
    static let huskyNewNote = Notification.Name("huskynotes.newNote")
}
