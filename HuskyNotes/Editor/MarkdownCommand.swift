//
//  MarkdownCommand.swift
//  HuskyNotes
//
//  The set of formatting actions the editor understands, plus the lightweight
//  broadcast channel that carries them from the macOS `Format` menu (or any
//  future toolbar) to the focused editor's coordinator.
//
//  Menu items don't hold a reference to the text view; they post a command and
//  whichever `MarkdownEditor` is first responder applies it. This keeps the
//  SwiftUI command tree decoupled from the AppKit/UIKit text view.
//

import Foundation

/// A formatting action that can be applied to the Markdown source around the
/// current selection.
enum MarkdownCommand: Equatable, Sendable {
    /// Toggle `**bold**`.
    case bold
    /// Toggle `*italic*`.
    case italic
    /// Toggle `<u>underline</u>` (HTML passthrough — Markdown has no underline).
    case underline
    /// Toggle `~~strikethrough~~` (GFM).
    case strikethrough
    /// Toggle `==highlight==`.
    case highlight
    /// Toggle inline `` `code` ``.
    case inlineCode
    /// Wrap the selection in a fenced code block.
    case codeBlock
    /// Insert / wrap a `[link](url)`.
    case link
    /// Insert a `[[wiki link]]` (backlinks are a later milestone).
    case wikiLink
    /// Set the selected lines to a heading of the given level (1–6); level 0
    /// clears any heading (plain paragraph).
    case heading(Int)
    /// Toggle a `- ` bullet list on the selected lines.
    case bulletList
    /// Toggle a `1. ` ordered list on the selected lines.
    case orderedList
    /// Toggle a `- [ ] ` task item on the selected lines.
    case todo
    /// Toggle a `> ` block quote on the selected lines.
    case quote
    /// Insert a `---` thematic break (line separator).
    case lineSeparator
    /// Insert today's date (`yyyy-MM-dd`).
    case currentDate
}

extension Notification.Name {
    /// Posted by the `Format` menu; observed by the focused editor coordinator.
    static let huskyFormatCommand = Notification.Name("huskynotes.formatCommand")
}

extension MarkdownCommand {
    /// `userInfo` key under which the command travels on the notification.
    static let userInfoKey = "command"

    /// Broadcasts this command to the focused editor.
    func send() {
        NotificationCenter.default.post(
            name: .huskyFormatCommand,
            object: nil,
            userInfo: [Self.userInfoKey: self]
        )
    }

    /// Extracts a command from a `.huskyFormatCommand` notification, if present.
    static func from(_ notification: Notification) -> MarkdownCommand? {
        notification.userInfo?[userInfoKey] as? MarkdownCommand
    }
}
