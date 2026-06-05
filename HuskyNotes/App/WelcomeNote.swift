//
//  WelcomeNote.swift
//  HuskyNotes
//
//  The Markdown for the welcome / demo note seeded into a fresh library on first
//  launch (see `HuskyNotesApp.seedWelcomeNoteIfNeeded`). It doubles as a live
//  tour of every editor tool — each example is real Markdown, so it renders in
//  Read mode and shows its source in the editor. Also reused by the SwiftUI
//  preview container so there's a single source of truth.
//

import Foundation

/// The seeded welcome / demo note.
enum WelcomeNote {

    /// A complete, self-explaining tour of Husky Notes' tools, in Markdown.
    static let markdown = """
    # 👋 Welcome to Husky Notes

    A native, **open** Markdown notebook for iPhone, iPad and Mac. Everything you write is saved as plain Markdown — no lock-in, always yours.

    > This note is a live demo. Tap **Read** (📖) in the toolbar to see it fully rendered, and **Edit** (✏️) to see exactly how each example is written.

    ---

    ## Formatting as you type

    Mix **bold**, *italic*, ~~strikethrough~~ and `inline code` right in your sentences. The editor hides the Markdown symbols and shows the result, so it reads like a finished page while you write.

    Highlight what matters in five colours: <mark class="hl-yellow">yellow</mark>, <mark class="hl-green">green</mark>, <mark class="hl-pink">pink</mark>, <mark class="hl-orange">orange</mark> and <mark class="hl-purple">purple</mark>.

    ## Headings

    # Heading 1
    ## Heading 2
    ### Heading 3

    Start a line with `#`, `##` or `###` — or use ⌘1 / ⌘2 / ⌘3.

    ## Lists

    - A simple bullet
    - Another point
      - And a nested one

    1. First step
    2. Second step
    3. Third step

    ## To-dos

    - [x] Add a checkbox by writing `- [ ]`
    - [x] Tap the box to tick it off
    - [ ] See every open task in one place via the **To-Do** list

    ## Quotes & dividers

    > Reliability over cleverness — your notes should just work.

    Drop a horizontal rule with three dashes:

    ---

    ## Code

    Fenced code blocks get real syntax highlighting:

    ```swift
    struct Note {
        var title: String   // shown in your list
        var body: String    // plain Markdown — always yours
    }
    ```

    ## Links

    Link to the web: [huskynotes.com](https://huskynotes.com).

    Link between your own notes with a wiki link — just type `[[Note Title]]`.

    ## Tables

    | Tool       | What it does          |
    | ---------- | --------------------- |
    | Headings   | Structure your note   |
    | Tables     | Tidy rows and columns |
    | Highlights | Draw the eye          |

    ## Tags

    Write a #tag anywhere in a note and Husky Notes builds a **smart list** for it automatically. Try #welcome, #demo or #ideas — then find them in the sidebar.

    ## Attachments

    Tap the **photo** or **document** button in the toolbar to drop an image, PDF or file straight into a note. Attachments live with the note and travel with it.

    ---

    ## Tools & shortcuts

    On **Mac**, use the **Format** menu or the shortcuts below. On **iPhone & iPad**, tap the formatting bar just above the keyboard.

    | Tool           | Shortcut (Mac) |
    | -------------- | -------------- |
    | Bold           | ⌘B             |
    | Italic         | ⌘I             |
    | Underline      | ⌘U             |
    | Strikethrough  | ⇧⌘U            |
    | Highlight      | ⌃⌘H            |
    | Link           | ⌘K             |
    | Wiki link      | ⌘D             |
    | Inline code    | ⌃⌘C            |
    | Code block     | ⇧⌘C            |
    | Bullet list    | ⌘L             |
    | Ordered list   | ⇧⌘L            |
    | To-do          | ⌃⌘T            |
    | Quote          | ⇧⌘T            |
    | Line separator | ⌥⌘S            |
    | New note       | ⌘N             |

    Table and Insert Current Date also live in the **Format** menu.

    ## More to explore

    - 📖 **Read mode** — a clean, rendered view (the book icon)
    - 🎯 **Focus mode** — hide everything but the page
    - 🎨 **Themes** — six built-in looks plus a full theme editor in Settings
    - 🔍 **Search** — combine text and #tags, like `#work invoice`
    - 🗂️ **Folders** — file notes alongside your auto-built tag lists
    - 🔒 **Lock** — protect a note with Face ID / Touch ID
    - 📤 **Export** — share as `.md`, **Export as PDF**, or **Print** (the share menu)
    - ☁️ **iCloud sync** — turn it on in Settings; offline-first and private

    You can edit or delete this note anytime. Happy writing! 🐺
    """
}
