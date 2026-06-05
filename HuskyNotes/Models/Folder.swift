import Foundation
import SwiftData

/// A user-created folder that groups notes.
///
/// Unlike ``Tag``s — which are *derived* from `#hashtags` in the body — folders
/// are **explicit**: the user creates them and files notes into them. A note
/// belongs to at most one folder (see ``Note/folder``).
///
/// The model is **CloudKit-ready**: every stored property has a default value
/// and the relationship is optional, satisfying the SwiftData + CloudKit
/// mirroring requirements.
@Model
final class Folder {
    /// Stable identifier. Defaulted for CloudKit mirroring.
    var id: UUID = UUID()

    /// The folder's display name.
    var name: String = ""

    /// Optional `"#RRGGBB"` colour used to tint the folder's icon in the
    /// sidebar and note rows. `nil` falls back to the active theme's accent.
    var colorHex: String? = nil

    /// Optional single emoji shown in place of the default folder glyph.
    var icon: String? = nil

    /// When the folder was created (used as a stable display order).
    var createdAt: Date = Date()

    /// Notes filed in this folder. The inverse is ``Note/folder``; deleting a
    /// folder nullifies this link so the notes themselves survive.
    var notes: [Note]? = []

    /// Creates a folder. All parameters default so the initialiser can be called
    /// with no arguments.
    init(
        id: UUID = UUID(),
        name: String = "",
        colorHex: String? = nil,
        icon: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.createdAt = createdAt
    }
}
