//
//  ThemeStore.swift
//  HuskyNotes
//
//  Observable store that owns the loaded themes and the active selection.
//  Inject once at the app root via `.environment(themeStore)` and read it in
//  views with `@Environment(ThemeStore.self) private var themeStore`.
//
//  Theme selection and any user-created themes are **device-local**
//  (UserDefaults), so a broken or exotic theme can never propagate across a
//  user's devices via sync.
//

import Foundation
import Observation

/// Owns the available themes (built-in + user-created) and the active selection.
///
/// Built-in themes are loaded once at init; custom themes are persisted as JSON
/// in `UserDefaults`. The active theme id is also persisted; the computed
/// `active` always resolves to a valid theme, falling back to Blue Husky.
@Observable
final class ThemeStore {

    /// All available themes: built-ins first, then user themes.
    private(set) var themes: [Theme]

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

    // MARK: Storage

    private let builtIns: [Theme]
    private var userThemes: [Theme] {
        didSet {
            persistUserThemes()
            rebuild()
        }
    }

    private static let activeIDKey = "huskynotes.activeThemeID"
    private static let userThemesKey = "huskynotes.userThemes"
    private static let defaultID = "blue-husky"

    private let defaults: UserDefaults

    // MARK: Init

    /// Create the store, loading built-in + user themes and restoring the saved
    /// selection. `defaults` is injectable for testing.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.builtIns = BuiltInThemes.load()
        let loadedUser = Self.loadUserThemes(from: defaults)
        self.userThemes = loadedUser
        self.themes = builtIns + loadedUser
        self.activeThemeID = defaults.string(forKey: Self.activeIDKey) ?? Self.defaultID
    }

    // MARK: Selection

    /// Select a theme by id. Unknown ids are ignored so `active` stays valid.
    func select(_ id: String) {
        guard themes.contains(where: { $0.id == id }) else { return }
        activeThemeID = id
    }

    // MARK: Custom themes

    /// Whether `id` is a built-in (non-editable, non-deletable) theme.
    func isBuiltIn(_ id: String) -> Bool {
        builtIns.contains { $0.id == id }
    }

    /// Creates an editable copy of `base` with a fresh id and a " Copy" name,
    /// stores it, selects it, and returns it.
    @discardableResult
    func duplicate(_ base: Theme) -> Theme {
        let copy = Theme(
            id: "custom-\(UUID().uuidString.prefix(8))",
            name: base.name + " Copy",
            isDark: base.isDark,
            background: base.background,
            surface: base.surface,
            textPrimary: base.textPrimary,
            textSecondary: base.textSecondary,
            accent: base.accent,
            heading: base.heading,
            link: base.link,
            codeBackground: base.codeBackground,
            codeText: base.codeText,
            quoteBar: base.quoteBar,
            selection: base.selection,
            bodyFont: base.bodyFont,
            monoFont: base.monoFont,
            bodySize: base.bodySize,
            lineSpacing: base.lineSpacing
        )
        userThemes.append(copy)
        activeThemeID = copy.id
        return copy
    }

    /// Inserts or updates a custom theme, then re-selects it so edits show live.
    /// Built-in ids are ignored (they're read-only).
    func saveCustom(_ theme: Theme) {
        guard !isBuiltIn(theme.id) else { return }
        if let index = userThemes.firstIndex(where: { $0.id == theme.id }) {
            userThemes[index] = theme
        } else {
            userThemes.append(theme)
        }
        activeThemeID = theme.id
    }

    /// Deletes a custom theme; built-ins can't be deleted. If the deleted theme
    /// was active, falls back to the default.
    func deleteCustom(_ id: String) {
        guard !isBuiltIn(id) else { return }
        userThemes.removeAll { $0.id == id }
        if activeThemeID == id {
            activeThemeID = Self.defaultID
        }
    }

    // MARK: Persistence

    private func rebuild() {
        themes = builtIns + userThemes
    }

    private func persistUserThemes() {
        if let data = try? JSONEncoder().encode(userThemes) {
            defaults.set(data, forKey: Self.userThemesKey)
        }
    }

    private static func loadUserThemes(from defaults: UserDefaults) -> [Theme] {
        guard
            let data = defaults.data(forKey: userThemesKey),
            let themes = try? JSONDecoder().decode([Theme].self, from: data)
        else { return [] }
        return themes
    }
}
