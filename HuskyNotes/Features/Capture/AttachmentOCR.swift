//
//  AttachmentOCR.swift
//  HuskyNotes
//
//  Bridges `OCRService` to the SwiftData store: when an attachment is imported,
//  recognize its text on a background task and write it back to
//  `Attachment.recognizedText` (a derived cache that makes the attachment's text
//  searchable). The canonical Markdown body is never touched.
//

import Foundation
import SwiftData

/// Schedules and persists OCR for attachments. Main-actor isolated because it
/// touches the SwiftData main context; the heavy recognition runs detached.
@MainActor
enum AttachmentOCR {

    /// Recognizes `attachment`'s text in the background (if it hasn't been done
    /// and the type is supported), then stores it. Safe to call repeatedly.
    static func recognizeIfNeeded(_ attachment: Attachment) {
        guard attachment.recognizedText == nil,
              let data = attachment.data,
              OCRService.canRecognize(contentType: attachment.contentType, data: data) else { return }

        // Capture only Sendable values across the task boundary (never the model).
        let id = attachment.id
        let contentType = attachment.contentType
        Task.detached(priority: .utility) {
            guard let text = OCRService.recognizeText(in: data, contentType: contentType),
                  !text.isEmpty else { return }
            await persist(text, attachmentID: id)
        }
    }

    /// Writes recognized text back onto the attachment, re-fetched by id in the
    /// main context (the original model can't cross the task boundary).
    private static func persist(_ text: String, attachmentID: UUID) {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<Attachment>(
            predicate: #Predicate { $0.id == attachmentID }
        )
        guard let attachment = try? context.fetch(descriptor).first else { return }
        attachment.recognizedText = text
    }
}
