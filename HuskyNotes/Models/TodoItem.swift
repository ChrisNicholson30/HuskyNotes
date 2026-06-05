import Foundation
import SwiftData

/// A standalone quick to-do.
///
/// Quick to-dos are their **own** lightweight list — deliberately *not* derived
/// from note bodies. They let you jot a task without creating a note. The model
/// is **CloudKit-ready**: every stored property has a default value.
@Model
final class TodoItem {
    /// Stable identifier. Defaulted for CloudKit mirroring.
    var id: UUID = UUID()

    /// The to-do's text.
    var text: String = ""

    /// Whether the to-do is completed.
    var isDone: Bool = false

    /// When the to-do was created.
    var createdAt: Date = Date()

    /// When it was completed, if applicable.
    var completedAt: Date? = nil

    /// Manual position in the list (lower sorts first).
    var sortOrder: Int = 0

    /// Creates a to-do. All parameters default so the initialiser can be called
    /// with no arguments.
    init(
        id: UUID = UUID(),
        text: String = "",
        isDone: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.sortOrder = sortOrder
    }
}
