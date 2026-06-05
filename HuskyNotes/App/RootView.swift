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

/// The root scene content.
struct RootView: View {

    /// The selected smart list (sidebar → note-list filter).
    @State private var selectedList: SmartList? = .all

    /// The selected note (note-list → editor).
    @State private var selectedNote: Note?

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
        #if os(iOS)
        if horizontalSizeClass == .compact {
            MobileRootView(
                selectedList: $selectedList,
                selectedNote: $selectedNote,
                isFocusMode: $isFocusMode
            )
        } else {
            splitView
        }
        #else
        splitView
        #endif
    }

    /// The three-column split view used on macOS and iPad.
    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selectedList)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
                #endif
        } content: {
            NoteListView(filter: selectedList ?? .all, selection: $selectedNote)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
                #endif
        } detail: {
            if let selectedNote {
                NoteEditorView(note: selectedNote, isFocusMode: $isFocusMode)
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

    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    /// Whether the slide-over sidebar is open.
    @State private var showSidebar = false

    private var sidebarWidth: CGFloat { 300 }

    var body: some View {
        ZStack(alignment: .leading) {
            // Main content: the note list, pushing the editor on tap.
            NavigationStack {
                NoteListView(filter: selectedList ?? .all, selection: $selectedNote)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                open()
                            } label: {
                                Label("Folders", systemImage: "sidebar.leading")
                            }
                            .tint(theme.accent.swiftUIColor)
                        }
                    }
                    .navigationDestination(item: $selectedNote) { note in
                        NoteEditorView(note: note, isFocusMode: $isFocusMode)
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
            .gesture(closeDrag)
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
