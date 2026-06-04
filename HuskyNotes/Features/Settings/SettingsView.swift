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

    var body: some View {
        TabView {
            NavigationStack { ThemeSettingsView() }
                .tabItem { Label("Themes", systemImage: "paintpalette") }

            NavigationStack { StorageSettingsView() }
                .tabItem { Label("Storage", systemImage: "externaldrive") }
        }
        .frame(minWidth: 520, minHeight: 480)
    }
}

/// iCloud sync, the continuous `.md` mirror, and one-shot export.
struct StorageSettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    @State private var syncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.syncEnabledKey)
    @State private var mirrorEnabled = MirrorService.isEnabled
    @State private var mirrorFolder = MirrorService.folderDisplayPath
    @State private var isChoosingMirrorFolder = false
    @State private var isChoosingExportFolder = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("iCloud Sync") {
                Toggle("Sync notes via iCloud", isOn: $syncEnabled)
                    .onChange(of: syncEnabled) { _, value in
                        UserDefaults.standard.set(value, forKey: PersistenceController.syncEnabledKey)
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
                Text("One-way (store → files). Two-way mirror is a later milestone.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary.swiftUIColor)
            }

            Section("Export") {
                Button("Export All Notes…") { isChoosingExportFolder = true }
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
        .fileImporter(isPresented: $isChoosingExportFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let didScope = url.startAccessingSecurityScopedResource()
                defer { if didScope { url.stopAccessingSecurityScopedResource() } }
                let notes = (try? modelContext.fetch(FetchDescriptor<Note>())) ?? []
                let ok = MirrorService.export(notes, to: url)
                statusMessage = ok ? "Exported \(notes.count) notes." : "Export failed."
            }
        }
    }

    /// Human-readable sync status line.
    private var syncStatus: String {
        if PersistenceController.shared.isSyncing {
            return "Syncing via your private iCloud database."
        }
        if syncEnabled {
            return "Enabled — relaunch to apply. Requires the iCloud entitlement and your CloudKit container (see HuskyNotes.entitlements)."
        }
        return "Off — notes are stored locally on this device."
    }
}
