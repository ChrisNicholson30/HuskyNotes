//
//  BiometricAuth.swift
//  HuskyNotes
//
//  A thin wrapper over LocalAuthentication for per-note locking. Notes marked
//  `isLocked` are gated behind Face ID / Touch ID (with device-passcode
//  fallback). Authentication is local only — nothing leaves the device.
//
//  NOTE: Biometrics can't be exercised on the Simulator's default config or in a
//  headless build; this needs a real device (or an enrolled simulator) to truly
//  verify. The code compiles and degrades gracefully where biometrics are
//  unavailable.
//

import Foundation
import LocalAuthentication

/// Performs local biometric / passcode authentication for locked notes.
enum BiometricAuth {

    /// The outcome of an unlock attempt.
    enum Outcome: Equatable {
        case success
        case failed
        case unavailable
    }

    /// A human-readable name for the device's biometric capability, for UI copy.
    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// Prompts for authentication. Falls back to the device passcode when
    /// biometrics aren't enrolled/available. Calls back on the main actor.
    static func authenticate(reason: String, completion: @escaping @MainActor (Outcome) -> Void) {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"

        var error: NSError?
        // `.deviceOwnerAuthentication` allows biometric *or* passcode.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            Task { @MainActor in completion(.unavailable) }
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            Task { @MainActor in completion(success ? .success : .failed) }
        }
    }
}
