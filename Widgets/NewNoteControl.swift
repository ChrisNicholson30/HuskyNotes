//
//  NewNoteControl.swift
//  HuskyNotes-Widgets
//
//  An iOS 18 Control for quick note capture. Add it to the Action Button or
//  Control Centre: one press opens Husky Notes straight into a new note (filed
//  in the general Notes list). For folder-specific capture, use the configurable
//  home-screen widget or a Shortcut built on the same "New Note" intent.
//

import WidgetKit
import SwiftUI
import AppIntents

/// A one-press "New Note" control for the Action Button / Control Centre.
struct NewNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.huskynotes.app.control.newnote") {
            ControlWidgetButton(action: NewHuskyNoteIntent()) {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
        .displayName("New Husky Note")
        .description("Open Husky Notes and start a new note.")
    }
}
