//
//  NewNoteWidget.swift
//  HuskyNotes-Widgets
//
//  A configurable home-screen widget: tap it to open Husky Notes into a new
//  note. Long-press → Edit Widget to pick a target folder; with none chosen the
//  note is filed in the general Notes list.
//

import WidgetKit
import SwiftUI
import AppIntents

/// Per-widget configuration: an optional target folder.
struct NewNoteWidgetConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "New Note"
    static let description = IntentDescription("Quickly start a new note, optionally in a folder.")

    @Parameter(title: "Folder")
    var folder: FolderAppEntity?
}

/// One timeline entry carrying the configured folder name.
struct NewNoteEntry: TimelineEntry {
    let date: Date
    let folderName: String?
}

/// Supplies the (static) timeline; the widget never needs to refresh.
struct NewNoteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NewNoteEntry {
        NewNoteEntry(date: Date(), folderName: nil)
    }

    func snapshot(for configuration: NewNoteWidgetConfig, in context: Context) async -> NewNoteEntry {
        NewNoteEntry(date: Date(), folderName: configuration.folder?.name)
    }

    func timeline(for configuration: NewNoteWidgetConfig, in context: Context) async -> Timeline<NewNoteEntry> {
        Timeline(entries: [NewNoteEntry(date: Date(), folderName: configuration.folder?.name)], policy: .never)
    }
}

struct NewNoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "com.huskynotes.app.widget.newnote",
            intent: NewNoteWidgetConfig.self,
            provider: NewNoteProvider()
        ) { entry in
            NewNoteWidgetView(folderName: entry.folderName)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("New Note")
        .description("Quickly start a new note — optionally in a folder.")
        .supportedFamilies([.systemSmall])
    }
}

struct NewNoteWidgetView: View {
    let folderName: String?

    var body: some View {
        Button(intent: intent) {
            VStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 30, weight: .semibold))
                Text(folderName?.isEmpty == false ? folderName! : "New Note")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
    }

    /// The capture intent, pre-filled with the configured folder (if any).
    private var intent: NewHuskyNoteIntent {
        if let folderName, !folderName.isEmpty {
            return NewHuskyNoteIntent(folder: FolderAppEntity(id: folderName))
        }
        return NewHuskyNoteIntent()
    }
}
