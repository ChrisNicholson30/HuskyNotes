//
//  HexColor.swift
//  HuskyNotes
//
//  A small Codable value type that wraps a "#RRGGBB" hex string and exposes
//  the corresponding SwiftUI `Color` and platform colour. Theming is decoupled
//  from storage, so every colour in the app flows through this type — never a
//  hard-coded literal in a view.
//

import SwiftUI

#if os(macOS)
import AppKit
/// The platform-native colour type for the current OS.
typealias PlatformColor = NSColor
#else
import UIKit
/// The platform-native colour type for the current OS.
typealias PlatformColor = UIColor
#endif

/// A Codable colour stored as a `"#RRGGBB"` hex string.
///
/// `HexColor` is the single bridge between persisted theme JSON and the live
/// colours used by SwiftUI and the TextKit editor. Parsing is deliberately
/// forgiving: any malformed input falls back to **magenta** so mistakes are
/// loud and visible rather than silently wrong.
struct HexColor: Codable, Hashable, Sendable {

    /// The normalised `"#RRGGBB"` string (always upper-cased, always 7 chars).
    let hex: String

    // MARK: Components (0...1)

    /// Red channel in the range `0...1`.
    var red: Double { Self.components(from: hex).red }
    /// Green channel in the range `0...1`.
    var green: Double { Self.components(from: hex).green }
    /// Blue channel in the range `0...1`.
    var blue: Double { Self.components(from: hex).blue }

    // MARK: Init

    /// Create a `HexColor` from a hex string, normalising and validating it.
    /// Invalid input is normalised to magenta (`"#FF00FF"`).
    init(_ raw: String) {
        self.hex = Self.normalise(raw)
    }

    // MARK: Codable

    /// Decodes from a bare JSON string (e.g. `"accent": "#3DA9FC"`).
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self.hex = Self.normalise(raw)
    }

    /// Encodes back to a bare JSON string.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    // MARK: Platform bridges

    /// The colour as a SwiftUI `Color`, in the sRGB colour space.
    var swiftUIColor: Color {
        let c = Self.components(from: hex)
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }

    /// The colour as the platform-native colour (`UIColor`/`NSColor`).
    var platformColor: PlatformColor {
        let c = Self.components(from: hex)
        #if os(macOS)
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        #else
        return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        #endif
    }

    // MARK: Parsing helpers

    /// The magenta fallback used whenever input cannot be parsed.
    private static let fallback = "#FF00FF"

    /// Normalise arbitrary input into a canonical `"#RRGGBB"` string.
    ///
    /// Accepts forms with or without a leading `#`, and expands 3-digit
    /// shorthand (`#abc` → `#AABBCC`). Anything else becomes magenta.
    private static func normalise(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        s = s.uppercased()

        // Expand 3-digit shorthand.
        if s.count == 3, s.allSatisfy(\.isHexDigit) {
            s = s.map { "\($0)\($0)" }.joined()
        }

        guard s.count == 6, s.allSatisfy(\.isHexDigit) else {
            return fallback
        }
        return "#\(s)"
    }

    /// Convert a normalised hex string into `0...1` RGB components.
    /// Falls back to magenta components if parsing somehow fails.
    private static func components(from hex: String) -> (red: Double, green: Double, blue: Double) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return (1, 0, 1) // magenta
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }
}
