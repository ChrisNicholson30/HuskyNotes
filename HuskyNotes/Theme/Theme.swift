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

    /// Optional code syntax-highlighting palette. When omitted from a theme's
    /// JSON, a built-in scheme is used (see ``SyntaxPalette/defaultDark`` /
    /// ``SyntaxPalette/defaultLight``), chosen by ``isDark``.
    let syntax: SyntaxPalette?

    /// Body font: `"system"` or a PostScript font name.
    let bodyFont: String
    /// Monospaced font for code: `"system"` or a PostScript name.
    let monoFont: String
    /// Base body point size.
    let bodySize: Double
    /// Line-height multiplier (e.g. `1.45`).
    let lineSpacing: Double
}

/// A code syntax-highlighting colour scheme — deliberately multi-hue and
/// independent of the UI palette, so code reads like a real editor regardless of
/// the surrounding theme. Themes may ship their own in JSON; otherwise a built-in
/// dark/light default is used.
struct SyntaxPalette: Codable, Hashable, Sendable {
    /// Language keywords (`func`, `class`, `return`, …).
    let keyword: HexColor
    /// Type / class names and HTML attribute values.
    let type: HexColor
    /// String and character literals.
    let string: HexColor
    /// Numeric literals and CSS hex colours.
    let number: HexColor
    /// Comments.
    let comment: HexColor
    /// HTML/XML tag names.
    let tag: HexColor
    /// HTML attributes / CSS property names.
    let attribute: HexColor
}

extension SyntaxPalette {

    /// A balanced multi-hue scheme for dark themes (Material-Palenight-inspired).
    static let defaultDark = SyntaxPalette(
        keyword: HexColor("#C792EA"),   // purple
        type: HexColor("#FFCB6B"),      // amber
        string: HexColor("#C3E88D"),    // green
        number: HexColor("#F78C6C"),    // orange
        comment: HexColor("#6E7A8A"),   // muted slate
        tag: HexColor("#F07178"),       // coral
        attribute: HexColor("#FFCB6B")  // amber
    )

    /// A balanced multi-hue scheme for light themes (One-Light-inspired).
    static let defaultLight = SyntaxPalette(
        keyword: HexColor("#A626A4"),   // purple
        type: HexColor("#C18401"),      // amber
        string: HexColor("#50A14F"),    // green
        number: HexColor("#986801"),    // brown-orange
        comment: HexColor("#A0A1A7"),   // grey
        tag: HexColor("#E45649"),       // red
        attribute: HexColor("#986801")  // brown-orange
    )
}

extension Theme {

    /// The resolved syntax palette: the theme's own, or the built-in default for
    /// its appearance.
    var resolvedSyntax: SyntaxPalette {
        syntax ?? (isDark ? .defaultDark : .defaultLight)
    }

    /// A hard-coded Blue Husky fallback so the app is **never** themeless,
    /// even if no bundle JSON can be loaded.
    static let blueHusky = Theme(
        id: "blue-husky",
        name: "Blue Husky",
        isDark: true,
        background: HexColor("#070D17"),
        surface: HexColor("#0E1929"),
        textPrimary: HexColor("#E1E9F2"),
        textSecondary: HexColor("#7C92AB"),
        accent: HexColor("#2F80ED"),
        heading: HexColor("#6FB4F2"),
        link: HexColor("#4C9AED"),
        codeBackground: HexColor("#0B1525"),
        codeText: HexColor("#9DBFE0"),
        quoteBar: HexColor("#275C8A"),
        selection: HexColor("#143052"),
        syntax: nil,
        bodyFont: "system",
        monoFont: "SFMono-Regular",
        bodySize: 16,
        lineSpacing: 1.45
    )
}
