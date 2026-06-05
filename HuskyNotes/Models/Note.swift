import Foundation
import SwiftData

/// A single note in Husky Notes.
///
/// The note's ``body`` (Markdown source) is the **canonical source of truth**.
/// ``title`` and the ``tags`` relationship are *denormalised* values that are
/// recomputed from the body on save (see ``recomputeTitle()``).
///
/// The model is **CloudKit-ready**: every stored property has a default value
/// and every relationship is optional, satisfying the SwiftData + CloudKit
/// mirroring requirements (v0.1 is local-only; CloudKit lands in v0.2).
@Model
final class Note {
    /// Stable identifier. Defaulted for CloudKit mirroring.
    var id: UUID = UUID()

    /// Denormalised display title, recomputed from ``body`` on save.
    var title: String = ""

    /// Markdown source — the canonical source of truth for the note's content.
    var body: String = ""

    /// When the note was first created.
    var createdAt: Date = Date()

    /// When the note was last modified.
    var modifiedAt: Date = Date()

    /// Whether the note is pinned to the top of lists.
    var isPinned: Bool = false

    /// Whether the note is archived (hidden from the default list).
    var isArchived: Bool = false

    /// Whether the note is in the trash.
    var isTrashed: Bool = false

    /// When the note was moved to the trash, if applicable.
    var trashedAt: Date? = nil

    /// Whether the note is locked behind device biometrics (Face ID / Touch ID).
    var isLocked: Bool = false

    /// Tags applied to this note. Denormalised from the body and recomputed on save.
    @Relationship(deleteRule: .nullify, inverse: \Tag.notes)
    var tags: [Tag]? = []

    /// The folder this note is filed in, if any. User-assigned (unlike ``tags``,
    /// which are derived). Optional for CloudKit mirroring; nullified — not
    /// cascaded — when the folder is deleted, so the note survives.
    @Relationship(deleteRule: .nullify, inverse: \Folder.notes)
    var folder: Folder? = nil

    /// Attachments owned by this note; deleted when the note is deleted.
    @Relationship(deleteRule: .cascade, inverse: \Attachment.note)
    var attachments: [Attachment]? = []

    /// Creates a note. All parameters default so the initialiser can be called
    /// with no arguments to make a blank note.
    init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        isPinned: Bool = false,
        isArchived: Bool = false,
        isTrashed: Bool = false,
        trashedAt: Date? = nil,
        isLocked: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.isTrashed = isTrashed
        self.trashedAt = trashedAt
        self.isLocked = isLocked
    }

    /// Recomputes ``title`` from the first non-empty line of ``body``.
    ///
    /// A leading ATX heading marker (`"# "`, including multiple `#` and
    /// surrounding whitespace) is stripped so a note beginning with `# Hello`
    /// yields the title `"Hello"`. If the body is empty, the title becomes `""`.
    func recomputeTitle() {
        let firstLine = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let firstLine else {
            title = ""
            return
        }

        var line = firstLine.trimmingCharacters(in: .whitespaces)

        // Strip a leading ATX heading marker, e.g. "#", "##", "### ".
        if line.first == "#" {
            let stripped = line.drop(while: { $0 == "#" })
            // Only treat as a heading if the hashes are followed by whitespace
            // or end-of-line (per CommonMark), otherwise keep the text as-is.
            if stripped.isEmpty || stripped.first == " " {
                line = stripped.trimmingCharacters(in: .whitespaces)
            }
        }

        title = line
    }
}
