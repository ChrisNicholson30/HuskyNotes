import Foundation
import SwiftData

/// A binary attachment (image, file, etc.) owned by a single ``Note``.
///
/// The attachment's ``data`` is stored using `.externalStorage` so large blobs
/// live outside the SQLite store. The model is **CloudKit-ready**: every stored
/// property has a default value and the relationship is optional.
@Model
final class Attachment {
    /// Stable identifier. Defaulted for CloudKit mirroring.
    var id: UUID = UUID()

    /// The original filename of the attachment.
    var filename: String = ""

    /// The attachment's bytes, stored externally to keep the store small.
    @Attribute(.externalStorage) var data: Data? = nil

    /// The UTI of the attachment (e.g. `"com.adobe.pdf"`), for icon + preview
    /// routing. Defaulted/optional for CloudKit mirroring.
    var contentType: String? = nil

    /// The attachment's size in bytes (for display).
    var byteCount: Int = 0

    /// The owning note. The inverse is ``Note/attachments``.
    var note: Note? = nil

    /// When the attachment was created.
    var createdAt: Date = Date()

    /// Creates an attachment. All parameters default so the initialiser can be
    /// called with no arguments.
    init(
        id: UUID = UUID(),
        filename: String = "",
        data: Data? = nil,
        contentType: String? = nil,
        byteCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.filename = filename
        self.data = data
        self.contentType = contentType
        self.byteCount = byteCount
        self.createdAt = createdAt
    }
}
