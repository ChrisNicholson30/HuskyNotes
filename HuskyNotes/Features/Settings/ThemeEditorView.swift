//
//  ThemeEditorView.swift
//  HuskyNotes
//
//  In-app theme editor. Users duplicate a built-in (or custom) theme and tweak
//  every colour token plus typography, with a live preview. Custom themes are
//  device-local (stored by `ThemeStore` in UserDefaults) and never synced, so a
//  broken theme can't propagate across devices.
//

import SwiftUI

/// A mutable working copy of a `Theme`, with colours as SwiftUI `Color` so the
/// editor's `ColorPicker`s can bind to them directly.
@Observable
final class ThemeDraft: Identifiable {
    let id: String
    var name: String
    var isDark: Bool

    var background: Color
    var surface: Color
    var textPrimary: Color
    var textSecondary: Color
    var accent: Color
    var heading: Color
    var link: Color
    var codeBackground: Color
    var codeText: Color
    var quoteBar: Color
    var selection: Color

    var bodyFont: String
    var monoFont: String
    var bodySize: Double
    var lineSpacing: Double

    /// Seeds the draft from an existing theme.
    init(theme: Theme) {
        id = theme.id
        name = theme.name
        isDark = theme.isDark
        background = theme.background.swiftUIColor
        surface = theme.surface.swiftUIColor
        textPrimary = theme.textPrimary.swiftUIColor
        textSecondary = theme.textSecondary.swiftUIColor
        accent = theme.accent.swiftUIColor
        heading = theme.heading.swiftUIColor
        link = theme.link.swiftUIColor
        codeBackground = theme.codeBackground.swiftUIColor
        codeText = theme.codeText.swiftUIColor
        quoteBar = theme.quoteBar.swiftUIColor
        selection = theme.selection.swiftUIColor
        bodyFont = theme.bodyFont
        monoFont = theme.monoFont
        bodySize = theme.bodySize
        lineSpacing = theme.lineSpacing
    }

    /// Builds an immutable `Theme` from the current draft values.
    func build() -> Theme {
        Theme(
            id: id,
            name: name.isEmpty ? "Untitled Theme" : name,
            isDark: isDark,
            background: HexColor(background),
            surface: HexColor(surface),
            textPrimary: HexColor(textPrimary),
            textSecondary: HexColor(textSecondary),
            accent: HexColor(accent),
            heading: HexColor(heading),
            link: HexColor(link),
            codeBackground: HexColor(codeBackground),
            codeText: HexColor(codeText),
            quoteBar: HexColor(quoteBar),
            selection: HexColor(selection),
            bodyFont: bodyFont,
            monoFont: monoFont,
            bodySize: bodySize,
            lineSpacing: lineSpacing
        )
    }
}

/// Edits a `ThemeDraft` — colours, appearance and typography — with a preview.
struct ThemeEditorView: View {

    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.dismiss) private var dismiss

    @Bindable var draft: ThemeDraft

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    TextField("Name", text: $draft.name)
                    Toggle("Dark appearance", isOn: $draft.isDark)
                }

                Section("Preview") { preview }

                Section("Colours") {
                    ColorPicker("Background", selection: $draft.background, supportsOpacity: false)
                    ColorPicker("Surface", selection: $draft.surface, supportsOpacity: false)
                    ColorPicker("Text", selection: $draft.textPrimary, supportsOpacity: false)
                    ColorPicker("Secondary text", selection: $draft.textSecondary, supportsOpacity: false)
                    ColorPicker("Accent", selection: $draft.accent, supportsOpacity: false)
                    ColorPicker("Heading", selection: $draft.heading, supportsOpacity: false)
                    ColorPicker("Link", selection: $draft.link, supportsOpacity: false)
                    ColorPicker("Code background", selection: $draft.codeBackground, supportsOpacity: false)
                    ColorPicker("Code text", selection: $draft.codeText, supportsOpacity: false)
                    ColorPicker("Quote bar", selection: $draft.quoteBar, supportsOpacity: false)
                    ColorPicker("Selection", selection: $draft.selection, supportsOpacity: false)
                }

                Section("Typography") {
                    LabeledContent("Body size") {
                        Slider(value: $draft.bodySize, in: 12...22, step: 1)
                        Text("\(Int(draft.bodySize))")
                    }
                    LabeledContent("Line spacing") {
                        Slider(value: $draft.lineSpacing, in: 1.0...2.0, step: 0.05)
                        Text(String(format: "%.2f", draft.lineSpacing))
                    }
                }

                if !themeStore.isBuiltIn(draft.id) {
                    Section {
                        Button("Delete Theme", role: .destructive) {
                            themeStore.deleteCustom(draft.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Edit Theme")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        themeStore.saveCustom(draft.build())
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 480)
    }

    /// A small live preview of body text, a heading and inline code.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heading")
                .font(.headline)
                .foregroundStyle(draft.heading)
            Text("The quick brown fox jumps over the lazy husky.")
                .foregroundStyle(draft.textPrimary)
            Text("inline code")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(draft.codeText)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(draft.codeBackground, in: RoundedRectangle(cornerRadius: 5))
            Text("a secondary line")
                .font(.subheadline)
                .foregroundStyle(draft.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(draft.background, in: RoundedRectangle(cornerRadius: 10))
    }
}
