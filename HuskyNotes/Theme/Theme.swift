//
//  Theme.swift
//  HuskyNotes
//
//  The `Theme` value type: a fully described, Codable palette + typography
//  spec. Themes are decoupled from note storage — they live as bundled or
//  user-supplied JSON and are never persisted alongside note content. Every
//  view and the TextKit editor read their colours from the active `Theme`.
//

import Foundation

/// A complete visual theme: colours, fonts and spacing.
///
/// Themes are loaded from JSON (`Resources/Themes/*.json`) and matched to this
/// shape one-to-one. `Sendable` so a theme can cross actor/concurrency
/// boundaries (e.g. into the styler) under Swift 6 strict concurrency.
struct Theme: Codable, Identifiable, Hashable, Sendable {

    /// Stable identifier, e.g. `"blue-husky"`. Used to persist the selection.
    let id: String
    /// Human-readable display name, e.g. `"Blue Husky"`.
    let name: String
    /// Whether this theme is a dark appearance (drives e.g. status bar style).
    let isDark: Bool

    /// Window/editor background.
    let background: HexColor
    /// Raised surfaces: sidebars, cards, list rows.
    let surface: HexColor
    /// Primary body text colour.
    let textPrimary: HexColor
    /// Secondary/muted text: subtitles, metadata.
    let textSecondary: HexColor
    /// Accent / tint colour: controls, insertion point.
    let accent: HexColor
    /// Heading colour for `#` headings.
    let heading: HexColor
    /// Link colour.
    let link: HexColor
    /// Background fill behind inline code and code blocks.
    let codeBackground: HexColor
    /// Foreground colour for code text.
    let codeText: HexColor
    /// The vertical bar/indent colour for block quotes.
    let quoteBar: HexColor
    /// Text selection highlight colour.
    let selection: HexColor

    /// Body font: `"system"` or a PostScript font name.
    let bodyFont: String
    /// Monospaced font for code: `"system"` or a PostScript name.
    let monoFont: String
    /// Base body point size.
    let bodySize: Double
    /// Line-height multiplier (e.g. `1.45`).
    let lineSpacing: Double
}

extension Theme {

    /// A hard-coded Blue Husky fallback so the app is **never** themeless,
    /// even if no bundle JSON can be loaded.
    static let blueHusky = Theme(
        id: "blue-husky",
        name: "Blue Husky",
        isDark: true,
        background: HexColor("#0B1622"),
        surface: HexColor("#13202E"),
        textPrimary: HexColor("#E6EEF5"),
        textSecondary: HexColor("#8FA6B8"),
        accent: HexColor("#3DA9FC"),
        heading: HexColor("#7FD0FF"),
        link: HexColor("#3DA9FC"),
        codeBackground: HexColor("#0E1B27"),
        codeText: HexColor("#A7C7E0"),
        quoteBar: HexColor("#2C6E9B"),
        selection: HexColor("#1E3A52"),
        bodyFont: "system",
        monoFont: "SFMono-Regular",
        bodySize: 16,
        lineSpacing: 1.45
    )
}
