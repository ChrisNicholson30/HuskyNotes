//
//  FolderEditorView.swift
//  HuskyNotes
//
//  A sheet for creating or editing a `Folder`: its name, an optional emoji icon,
//  and an optional colour swatch. Used by the sidebar's Folders section. Fully
//  themed — every colour reads from the active `Theme`.
//

import SwiftUI
import SwiftData

/// Creates a new folder, or edits an existing one when `folder` is non-nil.
struct FolderEditorView: View {

    /// The folder being edited, or `nil` to create a new one.
    let folder: Folder?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    @State private var name: String = ""
    @State private var icon: String = ""
    @State private var colorHex: String?

    /// Guards `load()` so re-appearance doesn't clobber in-progress edits.
    @State private var didLoad = false

    /// A palette of pleasant folder colours.
    private static let palette: [String] = [
        "#EF4444", "#F97316", "#F59E0B", "#EAB308",
        "#10B981", "#14B8A6", "#3DA9FC", "#6366F1",
        "#8B5CF6", "#EC4899", "#64748B", "#78716C"
    ]

    private var isEditing: Bool { folder != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        previewIcon
                        TextField("Folder name", text: $name)
                    }
                }

                Section("Emoji icon") {
                    TextField("Optional emoji", text: $icon)
                        .onChange(of: icon) { _, newValue in
                            // Keep a single emoji grapheme (one Character).
                            icon = String(newValue.prefix(1))
                        }
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }

                Section("Colour") {
                    colorGrid
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background.swiftUIColor)
            .navigationTitle(isEditing ? "Edit Folder" : "New Folder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .tint(theme.accent.swiftUIColor)
            .onAppear(perform: load)
        }
    }

    /// A live preview of the folder's chosen icon + colour.
    @ViewBuilder
    private var previewIcon: some View {
        if !icon.isEmpty {
            Text(icon).font(.title2)
        } else {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(selectedColor)
        }
    }

    /// The resolved swatch colour, or the theme accent when none is chosen.
    private var selectedColor: Color {
        colorHex.map { HexColor($0).swiftUIColor } ?? theme.accent.swiftUIColor
    }

    /// A grid of colour swatches plus a "no colour" option.
    private var colorGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
            Button { colorHex = nil } label: {
                ZStack {
                    Circle().fill(theme.surface.swiftUIColor)
                    Image(systemName: "slash.circle")
                        .foregroundStyle(theme.textSecondary.swiftUIColor)
                }
                .frame(width: 32, height: 32)
                .overlay(ring(isSelected: colorHex == nil))
            }
            .buttonStyle(.plain)

            ForEach(Self.palette, id: \.self) { hex in
                Button { colorHex = hex } label: {
                    Circle()
                        .fill(HexColor(hex).swiftUIColor)
                        .frame(width: 32, height: 32)
                        .overlay(ring(isSelected: colorHex == hex))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    /// A selection ring drawn around the active swatch.
    private func ring(isSelected: Bool) -> some View {
        Circle()
            .strokeBorder(theme.accent.swiftUIColor, lineWidth: isSelected ? 3 : 0)
            .padding(-3)
    }

    // MARK: Actions

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        name = folder?.name ?? ""
        icon = folder?.icon ?? ""
        colorHex = folder?.colorHex
    }

    private func save() {
        let emoji = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        if let folder {
            folder.name = trimmedName
            folder.icon = emoji.isEmpty ? nil : emoji
            folder.colorHex = colorHex
        } else {
            let new = Folder(
                name: trimmedName,
                colorHex: colorHex,
                icon: emoji.isEmpty ? nil : emoji
            )
            modelContext.insert(new)
        }
        dismiss()
    }
}
