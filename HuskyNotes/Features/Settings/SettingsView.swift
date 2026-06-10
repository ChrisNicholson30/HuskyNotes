//
//  SettingsView.swift
//  HuskyNotes
//
//  The settings hub: a tabbed container for Themes and Storage (sync, mirror,
//  export). Shown as the macOS Settings window and as a sheet on iOS/iPadOS.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Tabbed settings: Themes and Storage.
struct SettingsView: View {

    @Environment(ThemeStore.self) private var themeStore

    #if os(iOS)
    /// Dismisses the full-screen settings cover (the close button).
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        TabView {
            NavigationStack {
                ThemeSettingsView()
                    #if os(iOS)
                    .toolbar { closeButton }
                    #endif
            }
            .tabItem { Label("Themes", systemImage: "paintpalette") }

            NavigationStack {
                StorageSettingsView()
                    #if os(iOS)
                    .toolbar { closeButton }
                    #endif
            }
            .tabItem { Label("Storage", systemImage: "externaldrive") }
        }
        // Fixed sizing only suits the macOS Settings *window*. On iOS/iPadOS
        // settings fill the screen, so no min frame there.
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }

    #if os(iOS)
    /// A leading "✕" that closes the full-screen settings (iOS/iPadOS).
    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title2)
                    .foregroundStyle(themeStore.active.textSecondary.swiftUIColor)
            }
            .accessibilityLabel("Close Settings")
        }
    }
    #endif
}

/// iCloud sync, the continuous `.md` mirror, and one-shot export.
struct StorageSettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var themeStore
    @Environment(AppLock.self) private var appLock
    private var theme: Theme { themeStore.active }

    @State private var syncEnabled = PersistenceController.syncPreferenceEnabled
    @State private var mirrorEnabled = MirrorService.isEnabled
    @State private var mirrorFolder = MirrorService.folderDisplayPath
    @State private var isChoosingMirrorFolder = false
    @State private var statusMessage: String?

    var body: some View {
        @Bindable var appLock = appLock
        Form {
            Section("Privacy") {
                Toggle("Require \(appLock.biometryName) to Unlock", isOn: $appLock.isEnabled)
                Text("Locks Husky Notes when you leave it; reopening needs \(appLock.biometryName) or your device passcode. This setting stays on this device.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary.swiftUIColor)
            }

            Section("iCloud Sync") {
                Toggle("Sync notes via iCloud", isOn: $syncEnabled)
                    .onChange(of: syncEnabled) { _, value in
                        // Applies immediately — rebuilds the store with/without
                        // CloudKit mirroring and swaps it in. No relaunch needed.
                        PersistenceController.shared.setSyncEnabled(value)
                    }
                Text(syncStatus)
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary.swiftUIColor)
            }

            Section("Markdown Mirror") {
                Toggle("Continuously mirror to .md files", isOn: $mirrorEnabled)
                    .onChange(of: mirrorEnabled) { _, value in
                        MirrorService.isEnabled = value
                        if value { MirrorService.mirrorIfEnabled(context: modelContext) }
                    }
                Button(mirrorFolder == nil ? "Choose Folder…" : "Change Folder…") {
                    isChoosingMirrorFolder = true
                }
                if let mirrorFolder {
                    Text(mirrorFolder)
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary.swiftUIColor)
                }
                Button("Import Changes from Folder") {
                    let count = MirrorService.importChanges(context: modelContext)
                    statusMessage = "Imported \(count) note\(count == 1 ? "" : "s") from the folder."
                }
                .disabled(mirrorFolder == nil)
                Text("Mirror writes store → files; Import reads files → store (matched by id, newest wins). Continuous two-way watching is a later milestone.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary.swiftUIColor)
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary.swiftUIColor)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Storage")
        .fileImporter(isPresented: $isChoosingMirrorFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                MirrorService.setFolder(url)
                mirrorFolder = MirrorService.folderDisplayPath
                MirrorService.mirrorIfEnabled(context: modelContext)
            }
        }
    }

    /// Human-readable, reactive sync status line.
    private var syncStatus: String {
        let persistence = PersistenceController.shared
        if persistence.isSyncing {
            return "On — syncing across your devices via your own private iCloud database."
        }
        if syncEnabled && !persistence.iCloudAvailable {
            return "On, but iCloud is unavailable — sign into iCloud on this device to start syncing."
        }
        if syncEnabled {
            return "On — couldn't reach your iCloud container; using local storage for now."
        }
        return "Off — notes are stored only on this device."
    }
}
