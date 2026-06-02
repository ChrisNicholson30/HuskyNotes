//
//  ThemeStore.swift
//  HuskyNotes
//
//  Observable store that owns the loaded themes and the active selection.
//  Inject once at the app root via `.environment(themeStore)` and read it in
//  views with `@Environment(ThemeStore.self) private var themeStore`.
//
//  Theme selection is **device-local** (UserDefaults), so a broken or exotic
//  theme can never propagate across a user's devices via sync.
//

import Foundation
import Observation

/// Owns the available themes and the active selection.
///
/// Built-in themes are loaded once at init. The active theme id is persisted
/// in `UserDefaults`; the computed `active` always resolves to a valid theme,
/// falling back to Blue Husky if the stored id is missing.
@Observable
final class ThemeStore {

    /// All available themes (built-ins, and later user themes).
    var themes: [Theme]

    /// The id of the currently selected theme; persisted to `UserDefaults`.
    var activeThemeID: String {
        didSet { defaults.set(activeThemeID, forKey: Self.activeIDKey) }
    }

    /// The resolved active theme. Falls back to the first available theme, and
    /// ultimately to the hard-coded Blue Husky, so this never fails.
    var active: Theme {
        themes.first { $0.id == activeThemeID }
            ?? themes.first
            ?? .blueHusky
    }

    // MARK: Persistence

    /// UserDefaults key for the persisted active theme id.
    private static let activeIDKey = "huskynotes.activeThemeID"
    /// Default theme id when nothing has been chosen yet.
    private static let defaultID = "blue-husky"

    private let defaults: UserDefaults

    // MARK: Init

    /// Create the store, loading built-in themes and restoring any saved
    /// selection. `defaults` is injectable for testing.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.themes = BuiltInThemes.load()
        self.activeThemeID = defaults.string(forKey: Self.activeIDKey) ?? Self.defaultID
    }

    // MARK: API

    /// Select a theme by id. Unknown ids are ignored so `active` stays valid.
    func select(_ id: String) {
        guard themes.contains(where: { $0.id == id }) else { return }
        activeThemeID = id
    }
}
