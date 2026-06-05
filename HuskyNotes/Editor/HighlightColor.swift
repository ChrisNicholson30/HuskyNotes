//
//  HighlightColor.swift
//  HuskyNotes
//
//  The palette of text highlighter colours — traditional fluorescent-marker
//  hues. A highlight is stored as plain, portable HTML in the Markdown source:
//
//      <mark class="hl-yellow">highlighted text</mark>
//
//  This round-trips losslessly and degrades gracefully: Markdown viewers that
//  don't know the `hl-…` class still render a default `<mark>` (yellow). In the
//  app, the class names map back to these colours for the editor and Read mode.
//

import Foundation

/// A text-highlighter colour. Raw values are the suffix used in the stored
/// `<mark class="hl-…">` tag, so they must stay stable for round-tripping.
enum HighlightColor: String, CaseIterable, Identifiable, Sendable, Equatable {
    case yellow
    case green
    case pink
    case orange
    case purple

    var id: String { rawValue }

    /// Human-readable name for menus.
    var displayName: String {
        switch self {
        case .yellow: return "Yellow"
        case .green:  return "Green"
        case .pink:   return "Pink"
        case .orange: return "Orange"
        case .purple: return "Purple"
        }
    }

    /// The class suffix used in the stored tag (`hl-yellow`, …).
    var markClass: String { "hl-\(rawValue)" }

    /// The opening tag written into the Markdown source.
    var openTag: String { "<mark class=\"\(markClass)\">" }

    /// The closing tag — shared by every colour.
    static let closeTag = "</mark>"

    /// The fluorescent highlighter fill painted behind the text.
    var fill: HexColor {
        switch self {
        case .yellow: return HexColor("#FFF35C")
        case .green:  return HexColor("#B6F560")
        case .pink:   return HexColor("#FF8FCF")
        case .orange: return HexColor("#FFB454")
        case .purple: return HexColor("#C6A2FF")
        }
    }

    /// A near-black ink so highlighted text stays readable on the bright fill in
    /// every theme — exactly like marker over print.
    var ink: HexColor { HexColor("#1A1A1A") }

    // MARK: Parsing

    /// The regex matching a full highlight span; group 1 is the colour class
    /// suffix, group 2 is the inner (highlighted) content.
    static let spanPattern = "<mark class=\"hl-([a-z]+)\">(.*?)</mark>"

    /// The regex matching an opening tag at the *end* of a string (used to detect
    /// a highlight that ends exactly at the caret); group 1 is the colour suffix.
    static let openTagAtEndPattern = "<mark class=\"hl-([a-z]+)\">$"
}
