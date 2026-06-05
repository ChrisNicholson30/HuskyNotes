//
//  LockScreenView.swift
//  HuskyNotes
//
//  The full-screen cover shown while the app is locked (see ``AppLock``). It
//  hides all note content, auto-prompts for Face ID / Touch ID on appear, and
//  offers a manual "Unlock" button if the first prompt is dismissed. Themed.
//

import SwiftUI

/// The lock screen presented over the app while it is locked.
struct LockScreenView: View {

    /// Shared app-lock state; the view triggers authentication through it.
    @Environment(AppLock.self) private var appLock
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    var body: some View {
        ZStack {
            theme.background.swiftUIColor.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(theme.accent.swiftUIColor)

                Text("Husky Notes is Locked")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(theme.textPrimary.swiftUIColor)

                Text("Unlock with \(appLock.biometryName) to continue.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary.swiftUIColor)
                    .multilineTextAlignment(.center)

                Button {
                    appLock.authenticate()
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent.swiftUIColor)
                .padding(.top, 4)
            }
            .padding(40)
        }
        // Re-prompt automatically when the lock screen appears.
        .onAppear { appLock.authenticate() }
    }
}
