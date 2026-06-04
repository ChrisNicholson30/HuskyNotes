//
//  ThemeSettingsView.swift
//  HuskyNotes
//
//  A theme picker: a grid of cards, each showing a theme's name and four
//  representative swatches (background, surface, accent, heading). Tapping a
//  card calls `themeStore.select(_:)`, which persists the choice and updates
//  every view live via the environment.
//

import SwiftUI

/// Lets the user browse and select a theme.
struct ThemeSettingsView: View {

    /// The shared theme store, read from the environment.
    @Environment(ThemeStore.self) private var themeStore

    /// The currently active theme (drives the page's own chrome).
    private var theme: Theme { themeStore.active }

    /// The theme draft currently open in the editor sheet, if any.
    @State private var editing: ThemeDraft?

    /// Adaptive grid of theme cards.
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            HStack {
                Text("Themes")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.textPrimary.swiftUIColor)
                Spacer()
                Button {
                    editing = ThemeDraft(theme: themeStore.duplicate(themeStore.active))
                } label: {
                    Label("New from Active", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent.swiftUIColor)
            }
            .padding([.horizontal, .top])

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(themeStore.themes) { candidate in
                    card(for: candidate)
                        .onTapGesture { themeStore.select(candidate.id) }
                        .contextMenu { menu(for: candidate) }
                }
            }
            .padding()
        }
        .background(theme.background.swiftUIColor)
        .navigationTitle("Themes")
        .sheet(item: $editing) { draft in
            ThemeEditorView(draft: draft)
                .environment(themeStore)
        }
    }

    /// The per-card context menu: duplicate (any theme) plus edit/delete for
    /// user themes (built-ins are read-only).
    @ViewBuilder
    private func menu(for candidate: Theme) -> some View {
        Button {
            editing = ThemeDraft(theme: themeStore.duplicate(candidate))
        } label: {
            Label("Duplicate & Edit", systemImage: "plus.square.on.square")
        }
        if !themeStore.isBuiltIn(candidate.id) {
            Button {
                editing = ThemeDraft(theme: candidate)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                themeStore.deleteCustom(candidate.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// A single tappable theme card showing four swatches and the name.
    @ViewBuilder
    private func card(for candidate: Theme) -> some View {
        let isActive = candidate.id == themeStore.activeThemeID

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                swatch(candidate.background)
                swatch(candidate.surface)
                swatch(candidate.accent)
                swatch(candidate.heading)
            }

            HStack {
                Text(candidate.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.textPrimary.swiftUIColor)
                Spacer(minLength: 0)
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent.swiftUIColor)
                }
            }
        }
        .padding(12)
        .background(theme.surface.swiftUIColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isActive ? theme.accent.swiftUIColor : theme.textSecondary.swiftUIColor.opacity(0.25),
                    lineWidth: isActive ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(candidate.name)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    /// A single rounded colour swatch.
    @ViewBuilder
    private func swatch(_ color: HexColor) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color.swiftUIColor)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(theme.textSecondary.swiftUIColor.opacity(0.2), lineWidth: 0.5)
            }
    }
}
