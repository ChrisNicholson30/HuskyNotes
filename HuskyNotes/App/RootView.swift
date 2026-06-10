//
//  RootView.swift
//  HuskyNotes
//
//  Top-level navigation. On macOS and iPad (regular width) it's a three-column
//  `NavigationSplitView` (Sidebar → Note list → Editor). On iPhone (compact
//  width) it's a Bear-style layout: the note list with the editor pushed on tap,
//  and the sidebar as a **slide-over** that animates in over the content with a
//  dimming scrim.
//
//  All surfaces read their colours from the active `Theme`.
//

import SwiftUI
import SwiftData

/// The root scene content.
struct RootView: View {

    @Environment(\.modelContext) private var modelContext

    /// The selected smart list (sidebar → note-list filter).
    @State private var selectedList: SmartList? = .all

    /// The selected note (note-list → editor).
    @State private var selectedNote: Note?

    /// The id of a note that was *just created*, so the editor auto-focuses and
    /// raises the keyboard for it — and only it. Cleared once consumed.
    @State private var autoFocusNoteID: UUID?

    /// Sidebar column visibility for the split view.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// Distraction-free focus mode (collapses the split-view columns).
    @State private var isFocusMode = false

    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        rootContent
            // Quick capture from the widget / Action Button: create + open a new
            // note, optionally in the chosen folder.
            .onReceive(NotificationCenter.default.publisher(for: .huskyCreateNote)) { note in
                createQuickNote(folderName: note.userInfo?["folder"] as? String)
            }
            // iCloud sync was toggled and the store was swapped live — drop any
            // selection held from the old container before its context tears down.
            .onReceive(NotificationCenter.default.publisher(for: .huskyStoreDidChange)) { _ in
                selectedNote = nil
                selectedList = .all
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            MobileRootView(
                selectedList: $selectedList,
                selectedNote: $selectedNote,
                isFocusMode: $isFocusMode,
                autoFocusNoteID: $autoFocusNoteID
            )
        } else {
            splitView
        }
        #else
        splitView
        #endif
    }

    /// Creates a new note (optionally filed in `folderName`), selects it, and
    /// flags it for auto-focus — the quick-capture entry point.
    private func createQuickNote(folderName: String?) {
        selectedList = .all
        let note = Note(body: "# ")
        note.recomputeTitle()
        if let folderName, !folderName.isEmpty {
            let folders = (try? modelContext.fetch(FetchDescriptor<Folder>())) ?? []
            note.folder = folders.first { $0.name == folderName }
        }
        modelContext.insert(note)
        autoFocusNoteID = note.id
        selectedNote = note
    }

    /// The three-column split view used on macOS and iPad.
    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selectedList)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
                #endif
        } content: {
            contentColumn
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
                #endif
        } detail: {
            if let selectedNote {
                NoteEditorView(note: selectedNote, isFocusMode: $isFocusMode, autoFocusNoteID: $autoFocusNoteID)
            } else {
                emptyDetail
            }
        }
        .tint(theme.accent.swiftUIColor)
        .onChange(of: selectedList) { _, _ in selectedNote = nil }
        .onChange(of: isFocusMode) { _, focused in
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = focused ? .detailOnly : .all
            }
        }
        .onChange(of: selectedNote) { _, note in
            if note == nil, isFocusMode { isFocusMode = false }
        }
    }

    /// The middle column: the aggregated To-Do list for `.todo`, otherwise the
    /// filtered note list.
    @ViewBuilder
    private var contentColumn: some View {
        if selectedList == .todo {
            TodoListView()
        } else {
            NoteListView(filter: selectedList ?? .all,
                         selection: $selectedNote,
                         autoFocusNoteID: $autoFocusNoteID)
        }
    }

    /// Placeholder shown in the detail column when no note is selected.
    private var emptyDetail: some View {
        ContentUnavailableView {
            Label("No Note Selected", systemImage: "note.text")
        } description: {
            Text("Select a note from the list, or create a new one.")
        }
        .foregroundStyle(theme.textSecondary.swiftUIColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.swiftUIColor)
    }
}

#if os(iOS)

/// The iPhone (compact) layout: note list + pushed editor, with a slide-over
/// sidebar that animates over the content (Bear-style).
private struct MobileRootView: View {

    @Binding var selectedList: SmartList?
    @Binding var selectedNote: Note?
    @Binding var isFocusMode: Bool
    @Binding var autoFocusNoteID: UUID?

    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    /// Whether the slide-over sidebar is open.
    @State private var showSidebar = false

    private var sidebarWidth: CGFloat { 300 }

    /// The content shown beside the sidebar: the aggregated To-Do list for
    /// `.todo`, otherwise the filtered note list.
    @ViewBuilder
    private var contentColumn: some View {
        if selectedList == .todo {
            TodoListView()
        } else {
            NoteListView(filter: selectedList ?? .all,
                         selection: $selectedNote,
                         autoFocusNoteID: $autoFocusNoteID)
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Main content: the note list (or To-Do list), pushing the editor on tap.
            NavigationStack {
                contentColumn
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                open()
                            } label: {
                                Label("Sidebar", systemImage: "sidebar.leading")
                            }
                            .tint(theme.accent.swiftUIColor)
                        }
                    }
                    .navigationDestination(item: $selectedNote) { note in
                        NoteEditorView(note: note, isFocusMode: $isFocusMode, autoFocusNoteID: $autoFocusNoteID)
                    }
            }

            // Dimming scrim — tap or drag-left to dismiss.
            if showSidebar {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { close() }
                    .gesture(closeDrag)
            }

            // The slide-over sidebar.
            NavigationStack {
                SidebarView(selection: $selectedList, onSelect: { close() })
            }
            .frame(width: sidebarWidth)
            .background(theme.surface.swiftUIColor)
            .offset(x: showSidebar ? 0 : -(sidebarWidth + 12))
            .shadow(color: .black.opacity(showSidebar ? 0.25 : 0), radius: 12, x: 2)
            // Simultaneous (not exclusive) so it can't swallow row taps or the
            // List's vertical scroll — only a deliberate leftward drag closes.
            .simultaneousGesture(closeDrag)
        }
        .animation(.easeOut(duration: 0.25), value: showSidebar)
        // Selecting a different list returns to the list (pops the editor).
        .onChange(of: selectedList) { _, _ in selectedNote = nil }
    }

    /// A leftward drag that dismisses the sidebar.
    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                if value.translation.width < -40 { close() }
            }
    }

    private func open() {
        withAnimation(.easeOut(duration: 0.25)) { showSidebar = true }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.25)) { showSidebar = false }
    }
}

#endif
