//
//  BuiltInThemes.swift
//  HuskyNotes
//
//  Loads the bundled theme JSON files from `Resources/Themes` into `[Theme]`.
//  Themes are decoupled from storage and shipped as plain JSON so they can be
//  edited, added to, or replaced without touching code.
//

import Foundation

/// Loader for the app's built-in themes.
enum BuiltInThemes {

    /// The canonical load order shown in the picker.
    private static let order = [
        "blue-husky",
        "husky-day",
        "pine",
        "ember",
        "glacier",
        "aurora"
    ]

    /// Load all built-in themes from the app bundle, in `order`.
    ///
    /// Any theme that fails to load is skipped. If **nothing** loads (e.g.
    /// resources weren't copied), the hard-coded `Theme.blueHusky` fallback is
    /// returned so the app always has at least one theme.
    static func load() -> [Theme] {
        let themes = order.compactMap(load(id:))
        return themes.isEmpty ? [.blueHusky] : themes
    }

    /// Load a single theme JSON by its file/id (without extension).
    private static func load(id: String) -> Theme? {
        guard let url = url(for: id) else {
            assertionFailure("Missing bundled theme JSON: \(id).json")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Theme.self, from: data)
        } catch {
            assertionFailure("Failed to decode theme \(id): \(error)")
            return nil
        }
    }

    /// Resolve the bundle URL for a theme file, trying the `Themes`
    /// subdirectory first and falling back to the bundle root.
    private static func url(for id: String) -> URL? {
        Bundle.main.url(forResource: id, withExtension: "json", subdirectory: "Themes")
            ?? Bundle.main.url(forResource: id, withExtension: "json")
    }
}
