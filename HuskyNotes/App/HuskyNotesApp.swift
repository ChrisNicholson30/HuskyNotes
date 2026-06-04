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
#if os(macOS)
import AppKit
#endif

/// The Husky Notes application.
@main
struct HuskyNotesApp: App {

    /// The app-wide theme store. Owned here, injected into every view.
    @State private var themeStore = ThemeStore()

    /// Drives draining the Share Extension inbox when the app becomes active.
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(themeStore)
                // Match the system appearance to the active theme so SwiftUI
                // chrome (menus, alerts) reads correctly in light/dark themes.
                .preferredColorScheme(themeStore.active.isDark ? .dark : .light)
                .onAppear { drainSharedInbox() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { drainSharedInbox() }
                }
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

            // Export lives in the File menu on macOS.
            CommandGroup(replacing: .importExport) {
                Button("Export All Notes…") { exportAllNotes() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Export as Single File…") { exportCombinedNotes() }
            }

            // The Format menu — Bear-style text commands routed to the focused
            // editor. Each item broadcasts a `MarkdownCommand`; the active
            // `MarkdownEditor` applies it to its selection.
            CommandMenu("Format") {
                Menu("Heading") {
                    Button("Heading 1") { MarkdownCommand.heading(1).send() }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("Heading 2") { MarkdownCommand.heading(2).send() }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("Heading 3") { MarkdownCommand.heading(3).send() }
                        .keyboardShortcut("3", modifiers: .command)
                    Divider()
                    Button("Body Text") { MarkdownCommand.heading(0).send() }
                        .keyboardShortcut("0", modifiers: .command)
                }
                Divider()
                Button("Bold") { MarkdownCommand.bold.send() }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Italic") { MarkdownCommand.italic.send() }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Underline") { MarkdownCommand.underline.send() }
                    .keyboardShortcut("u", modifiers: .command)
                Button("Strikethrough") { MarkdownCommand.strikethrough.send() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Button("Highlight") { MarkdownCommand.highlight.send() }
                    .keyboardShortcut("h", modifiers: [.command, .control])
                Divider()
                Button("Link") { MarkdownCommand.link.send() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Wiki Link") { MarkdownCommand.wikiLink.send() }
                    .keyboardShortcut("d", modifiers: .command)
                Button("Inline Code") { MarkdownCommand.inlineCode.send() }
                    .keyboardShortcut("c", modifiers: [.command, .control])
                Button("Code Block") { MarkdownCommand.codeBlock.send() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Divider()
                Button("Bullet List") { MarkdownCommand.bulletList.send() }
                    .keyboardShortcut("l", modifiers: .command)
                Button("Ordered List") { MarkdownCommand.orderedList.send() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("To-Do") { MarkdownCommand.todo.send() }
                    .keyboardShortcut("t", modifiers: [.command, .control])
                Button("Quote") { MarkdownCommand.quote.send() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Button("Line Separator") { MarkdownCommand.lineSeparator.send() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                Button("Insert Current Date") { MarkdownCommand.currentDate.send() }
            }
        }
        #endif

        #if os(macOS)
        // A native Settings window hosting themes + storage.
        Settings {
            SettingsView()
                .environment(themeStore)
                .modelContainer(PersistenceController.shared.container)
        }
        #endif
    }

    /// Turns any pending Share Extension items (captured web pages) into notes,
    /// then clears the inbox. No-ops where the App Group isn't available.
    @MainActor
    private func drainSharedInbox() {
        let items = SharedInbox.load()
        guard !items.isEmpty else { return }
        let context = PersistenceController.shared.container.mainContext
        for item in items {
            let note = Note(body: item.markdown, createdAt: item.date, modifiedAt: item.date)
            note.recomputeTitle()
            context.insert(note)
            TagReconciler.reconcile(note, in: context)
        }
        SharedInbox.clear()
    }

    #if os(macOS)
    /// Prompts for a folder and exports every note as individual `.md` files.
    @MainActor
    private func exportAllNotes() {
        guard let folder = chooseFolder() else { return }
        let notes = (try? PersistenceController.shared.container.mainContext.fetch(FetchDescriptor<Note>())) ?? []
        _ = MirrorService.export(notes, to: folder)
    }

    /// Prompts for a folder and exports all notes into one combined `.md` file.
    @MainActor
    private func exportCombinedNotes() {
        guard let folder = chooseFolder() else { return }
        let notes = (try? PersistenceController.shared.container.mainContext.fetch(FetchDescriptor<Note>())) ?? []
        _ = MirrorService.exportCombined(notes, to: folder)
    }

    /// Shows an `NSOpenPanel` to pick a destination folder.
    @MainActor
    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Here"
        return panel.runModal() == .OK ? panel.url : nil
    }
    #endif
}

extension Notification.Name {
    /// Posted when the user invokes the "New Note" menu command (macOS).
    /// - TODO: Wire this through to `NoteListView`'s insert in a later milestone.
    static let huskyNewNote = Notification.Name("huskynotes.newNote")
}
