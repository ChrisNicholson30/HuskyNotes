//
//  AppLock.swift
//  HuskyNotes
//
//  Optional whole-app lock behind device biometrics (Face ID / Touch ID, with
//  passcode fallback). When enabled, the app presents a lock screen on launch
//  and whenever it returns from the background, hiding note content until the
//  owner authenticates. The preference is **device-local** (never synced).
//
//  Built on `BiometricAuth`; if biometrics are unavailable (e.g. an un-enrolled
//  simulator) authentication succeeds so the user is never trapped out.
//

import Foundation
import SwiftUI

/// Observable state + policy for the optional whole-app lock.
@MainActor
@Observable
final class AppLock {

    /// UserDefaults key for the device-local enable flag.
    static let enabledKey = "huskynotes.appLockEnabled"

    /// Whether the app requires authentication to open. Persisted on change.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            // Toggling off clears any active lock; toggling on takes effect when
            // the app next goes to the background.
            if !isEnabled { isLocked = false }
        }
    }

    /// Whether the lock screen is currently covering the app.
    private(set) var isLocked: Bool

    /// Guards against firing multiple overlapping authentication prompts.
    private var isAuthenticating = false

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        self.isEnabled = enabled
        // Start locked when enabled so a cold launch always authenticates.
        self.isLocked = enabled
    }

    /// The biometric capability name for UI copy (e.g. "Face ID").
    var biometryName: String { BiometricAuth.biometryName }

    /// Locks the app (no-op when disabled). Called as the app backgrounds so the
    /// switcher snapshot and a later return both require authentication.
    func lock() {
        guard isEnabled else { return }
        isLocked = true
    }

    /// Prompts for authentication and unlocks on success.
    func authenticate() {
        guard isEnabled, isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        BiometricAuth.authenticate(reason: "Unlock Husky Notes") { [weak self] outcome in
            guard let self else { return }
            self.isAuthenticating = false
            if outcome == .success || outcome == .unavailable {
                self.isLocked = false
            }
        }
    }

    /// Drives locking/unlocking from the app's scene phase.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            lock()
        case .active:
            authenticate()
        default:
            break
        }
    }
}
