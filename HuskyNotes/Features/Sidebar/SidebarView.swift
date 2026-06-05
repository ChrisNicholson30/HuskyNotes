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

    /// The active theme supplies every colour used below.
    @Environment(ThemeStore.self) private var themeStore

    /// Convenience accessor for the resolved active theme.
    private var theme: Theme { themeStore.active }

    /// Whether the settings sheet is presented (iOS/iPadOS; macOS uses ⌘,).
    @State private var showSettings = false

    var body: some View {
        List {
            Section {
                ForEach(SmartList.fixed) { item in
                    row(for: item)
                }
            }

            if !tags.isEmpty {
                Section {
                    ForEach(tags) { tag in
                        row(for: .tag(tag))
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
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(themeStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
}
