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

    /// Optional whole-app Face ID / Touch ID lock.
    @State private var appLock = AppLock()

    /// Drives draining the Share Extension inbox when the app becomes active.
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(themeStore)
                .environment(appLock)
                // Match the system appearance to the active theme so SwiftUI
                // chrome (menus, alerts) reads correctly in light/dark themes.
                .preferredColorScheme(themeStore.active.isDark ? .dark : .light)
                // Whole-app lock: covers all note content until authenticated.
                .overlay {
                    if appLock.isLocked {
                        LockScreenView()
                            .environment(themeStore)
                            .environment(appLock)
                    }
                }
                .onAppear {
                    seedWelcomeNoteIfNeeded()
                    drainSharedInbox()
                    publishFolders()
                    handleQuickCapture()
                }
                .onChange(of: scenePhase) { _, phase in
                    appLock.handleScenePhase(phase)
                    if phase == .active {
                        drainSharedInbox()
                        publishFolders()
                        handleQuickCapture()
                    }
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

            // Own the Print command so ⌘P prints the open note. Without this, ⌘P
            // hits AppKit's default (unhandled) print action and shows the
            // "application does not support printing" alert. The open
            // `NoteEditorView` listens for this and prints itself.
            CommandGroup(replacing: .printItem) {
                Button("Print…") {
                    NotificationCenter.default.post(name: .huskyPrintNote, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
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
                Menu("Highlight") {
                    Button("Yellow") { MarkdownCommand.highlight(.yellow).send() }
                        .keyboardShortcut("h", modifiers: [.command, .control])
                    Button("Green") { MarkdownCommand.highlight(.green).send() }
                    Button("Pink") { MarkdownCommand.highlight(.pink).send() }
                    Button("Orange") { MarkdownCommand.highlight(.orange).send() }
                    Button("Purple") { MarkdownCommand.highlight(.purple).send() }
                    Divider()
                    Button("Remove Highlight") { MarkdownCommand.removeHighlight.send() }
                }
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
                Button("Table") { MarkdownCommand.table.send() }
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
                .environment(appLock)
                .modelContainer(PersistenceController.shared.container)
        }
        #endif
    }

    /// UserDefaults flag recording that the welcome note seeding has been
    /// attempted, so it never runs twice (even if the user deletes the note).
    private static let didSeedWelcomeKey = "huskynotes.didSeedWelcome"

    /// Seeds the welcome / demo note once per device. The flag guarantees it runs
    /// a single time — so it never repeats and never reappears after the user
    /// deletes it — while still showing up as a one-time welcome on existing
    /// installs. The note is pinned and fully editable/deletable.
    @MainActor
    private func seedWelcomeNoteIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.didSeedWelcomeKey) else { return }
        defaults.set(true, forKey: Self.didSeedWelcomeKey)

        let context = PersistenceController.shared.container.mainContext
        let note = Note(body: WelcomeNote.markdown, createdAt: .now, modifiedAt: .now, isPinned: true)
        note.recomputeTitle()
        context.insert(note)
        // Build the smart lists for the demo's inline #tags.
        TagReconciler.reconcile(note, in: context)
    }

    /// Turns any pending Share Extension items (captured web pages) into notes,
    /// then clears the inbox. No-ops where the App Group isn't available.
    @MainActor
    private func drainSharedInbox() {
        let items = SharedInbox.pendingItems()
        guard !items.isEmpty else { return }
        let context = PersistenceController.shared.container.mainContext
        for item in items {
            let note = Note(body: item.markdown, createdAt: item.date, modifiedAt: item.date)
            note.recomputeTitle()
            context.insert(note)

            // Import any captured attachments (images / PDFs / files).
            for ref in item.attachments {
                guard let data = SharedInbox.attachmentData(for: ref) else { continue }
                let attachment = Attachment(
                    filename: ref.filename,
                    data: data,
                    contentType: ref.contentType,
                    byteCount: data.count
                )
                attachment.note = note
                context.insert(attachment)
                var current = note.attachments ?? []
                current.append(attachment)
                note.attachments = current
                AttachmentOCR.recognizeIfNeeded(attachment)
            }

            TagReconciler.reconcile(note, in: context)
            // Remove only after the note is fully built — a crash mid-drain
            // simply retries the remaining items next launch (nothing is lost).
            SharedInbox.remove(item)
        }
    }

    /// Publishes the user's folder names to the App Group so the "New Note"
    /// widget's folder picker can offer them (the widget can't read SwiftData).
    @MainActor
    private func publishFolders() {
        let context = PersistenceController.shared.container.mainContext
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        QuickCapture.publishFolderNames(folders.map(\.name).filter { !$0.isEmpty })
    }

    /// Consumes a pending quick-capture request (widget / Action Button) and
    /// asks `RootView` to create + open a new note in the chosen folder.
    @MainActor
    private func handleQuickCapture() {
        let request = QuickCapture.consumePendingNewNote()
        guard request.pending else { return }
        // Defer so `RootView`'s observer is mounted on a cold launch.
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .huskyCreateNote,
                object: nil,
                userInfo: request.folderName.map { ["folder": $0] }
            )
        }
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

    /// Posted to ask `RootView` to create + open a new note (quick capture from
    /// the widget / Action Button). `userInfo["folder"]` optionally names a
    /// target folder.
    static let huskyCreateNote = Notification.Name("huskynotes.createNote")

    /// Posted by the File ▸ Print command (⌘P) on macOS; the open
    /// ``NoteEditorView`` responds by printing its note.
    static let huskyPrintNote = Notification.Name("huskynotes.printNote")
}
