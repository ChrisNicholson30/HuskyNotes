//
//  HuskyWidgetsBundle.swift
//  HuskyNotes-Widgets
//
//  The widget extension's entry point. Vends a "New Note" Control (for the
//  Action Button / Control Centre) and a configurable home-screen widget.
//

import WidgetKit
import SwiftUI

@main
struct HuskyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NewNoteWidget()
        NewNoteControl()
    }
}
