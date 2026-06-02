import Foundation
import SwiftData

/// A tag that can be applied to one or more notes.
///
/// Tags are derived from `#hashtags` in a note's Markdown body and are
/// recomputed on save. The model is **CloudKit-ready**: every stored property
/// has a default value and the relationship is optional.
@Model
final class Tag {
    /// Stable identifier. Defaulted for CloudKit mirroring.
    var id: UUID = UUID()

    /// The tag's name, without the leading `#`.
    var name: String = ""

    /// Optional `"#RRGGBB"` colour override for displaying the tag.
    var colorHex: String? = nil

    /// Notes that carry this tag. The inverse is ``Note/tags``.
    var notes: [Note]? = []

    /// Creates a tag. All parameters default so the initialiser can be called
    /// with no arguments.
    init(
        id: UUID = UUID(),
        name: String = "",
        colorHex: String? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}
