//
//  SidebarView.swift
//  HuskyNotes
//
//  The primary navigation column: the fixed smart lists followed by a "Tags"
//  section driven by a live `@Query` over `Tag`. All chrome colours are read
//  from the active `Theme` — nothing here is hard-coded.
//

import SwiftUI
import SwiftData

/// The sidebar listing built-in smart lists and the user's tags.
///
/// The selection is bound to an optional ``SmartList`` so a parent
/// `NavigationSplitView` can drive the note-list column.
struct SidebarView: View {

    /// The currently selected smart list (shared with the note-list column).
    @Binding var selection: SmartList?

    /// Optional callback fired when a row is chosen — used by the iPhone
    /// slide-over to dismiss itself after a selection.
    var onSelect: (() -> Void)? = nil

    /// All tags, alphabetised. The inverse relationship lets us show counts.
    @Query(sort: \Tag.name, order: .forward) private var tags: [Tag]

    /// User-created folders, in creation order.
    @Query(sort: \Folder.createdAt, order: .forward) private var folders: [Folder]

    /// SwiftData context for creating / deleting folders.
    @Environment(\.modelContext) private var modelContext

    /// The active theme supplies every colour used below.
    @Environment(ThemeStore.self) private var themeStore

    /// The whole-app lock, re-injected into the settings cover (presentations
    /// don't reliably inherit custom environment objects).
    @Environment(AppLock.self) private var appLock

    /// Convenience accessor for the resolved active theme.
    private var theme: Theme { themeStore.active }

    /// Whether the settings sheet is presented (iOS/iPadOS; macOS uses ⌘,).
    @State private var showSettings = false

    /// Whether the new-folder sheet is presented.
    @State private var isCreatingFolder = false

    /// The folder currently being edited (drives the edit sheet).
    @State private var editingFolder: Folder?

    /// The tag pending deletion (drives the confirmation dialog). Deleting a tag
    /// also strips its `#tag` from notes, so we confirm first.
    @State private var tagToDelete: Tag?

    var body: some View {
        List {
            Section {
                ForEach(SmartList.fixed) { item in
                    row(for: item)
                }
            }

            Section {
                ForEach(folders) { folder in
                    folderRow(for: folder)
                }
            } header: {
                HStack {
                    Text("Folders")
                        .foregroundStyle(theme.textSecondary.swiftUIColor)
                    Spacer()
                    Button {
                        isCreatingFolder = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(theme.accent.swiftUIColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New Folder")
                }
            }

            if !tags.isEmpty {
                Section {
                    ForEach(tags) { tag in
                        row(for: .tag(tag))
                            .contextMenu {
                                Button(role: .destructive) { tagToDelete = tag } label: {
                                    Label("Delete Tag", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("Tags")
                        .foregroundStyle(theme.textSecondary.swiftUIColor)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.surface.swiftUIColor)
        .tint(theme.accent.swiftUIColor)
        .navigationTitle("Husky Notes")
        .sheet(isPresented: $isCreatingFolder) {
            FolderEditorView(folder: nil)
                .environment(themeStore)
        }
        .sheet(item: $editingFolder) { folder in
            FolderEditorView(folder: folder)
                .environment(themeStore)
        }
        .confirmationDialog(
            "Delete Tag",
            isPresented: Binding(get: { tagToDelete != nil }, set: { if !$0 { tagToDelete = nil } }),
            presenting: tagToDelete
        ) { tag in
            Button("Delete “#\(tag.name)”", role: .destructive) { delete(tag) }
            Button("Cancel", role: .cancel) { }
        } message: { tag in
            let count = (tag.notes ?? []).count
            Text("This removes #\(tag.name) from \(count) note\(count == 1 ? "" : "s"). The notes themselves are kept.")
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
                .environment(themeStore)
                .environment(appLock)
        }
        #endif
    }

    /// A single themed, tappable sidebar row. A `Button` (rather than
    /// `List(selection:)`) so it selects on tap in *any* container — the
    /// split-view column and the iPhone slide-over alike.
    @ViewBuilder
    private func row(for item: SmartList) -> some View {
        Button {
            selection = item
            onSelect?()
        } label: {
            Label {
                Text(item.title)
                    .foregroundStyle(theme.textPrimary.swiftUIColor)
            } icon: {
                Image(systemName: item.systemImage)
                    .foregroundStyle(theme.accent.swiftUIColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            (selection == item ? theme.accent.swiftUIColor.opacity(0.18) : theme.surface.swiftUIColor)
        )
    }

    /// A folder row: its emoji or colour-tinted glyph, name, selection state, and
    /// a context menu to edit or delete it.
    @ViewBuilder
    private func folderRow(for folder: Folder) -> some View {
        let item = SmartList.folder(folder)
        Button {
            selection = item
            onSelect?()
        } label: {
            Label {
                Text(folder.name.isEmpty ? "Untitled Folder" : folder.name)
                    .foregroundStyle(theme.textPrimary.swiftUIColor)
            } icon: {
                folderIcon(folder)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            (selection == item ? theme.accent.swiftUIColor.opacity(0.18) : theme.surface.swiftUIColor)
        )
        .contextMenu {
            Button { editingFolder = folder } label: {
                Label("Edit Folder", systemImage: "pencil")
            }
            Button(role: .destructive) { delete(folder) } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    /// The folder's icon — its emoji if set, otherwise a colour-tinted glyph.
    @ViewBuilder
    private func folderIcon(_ folder: Folder) -> some View {
        if let emoji = folder.icon, !emoji.isEmpty {
            Text(emoji)
        } else {
            Image(systemName: "folder.fill")
                .foregroundStyle(folderColor(folder))
        }
    }

    /// The folder's colour, falling back to the theme accent.
    private func folderColor(_ folder: Folder) -> Color {
        folder.colorHex.map { HexColor($0).swiftUIColor } ?? theme.accent.swiftUIColor
    }

    /// Deletes a folder. Its notes survive (the relationship nullifies); if the
    /// deleted folder was selected, fall back to All Notes.
    private func delete(_ folder: Folder) {
        if case .folder(let selected) = selection, selected.id == folder.id {
            selection = .all
        }
        modelContext.delete(folder)
    }

    /// Deletes a tag everywhere: strips its `#tag` from every note that carries it
    /// (the body is canonical, so this is what truly removes it), then deletes the
    /// `Tag` row. The notes themselves are kept. Falls back to All Notes if the
    /// deleted tag was the active filter, and re-mirrors to `.md` if that's on.
    private func delete(_ tag: Tag) {
        if case .tag(let selected) = selection, selected.id == tag.id {
            selection = .all
        }

        let name = tag.name
        for note in (tag.notes ?? []) {
            let newBody = TagParser.removing(tagNamed: name, from: note.body)
            guard newBody != note.body else { continue }
            note.body = newBody
            note.modifiedAt = Date()
            note.recomputeTitle()
        }

        // Deleting the tag nullifies its inverse on each note; with the `#tag`
        // text gone, a later save won't re-derive it.
        modelContext.delete(tag)
        MirrorService.mirrorIfEnabled(context: modelContext)
        tagToDelete = nil
    }
}
