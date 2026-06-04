//
//  AttachmentsBar.swift
//  HuskyNotes
//
//  A horizontal strip of attachment thumbnails shown beneath the editor. Images
//  render as previews; other files show a generic glyph. Each can be removed.
//  Attachment bytes live in SwiftData external storage and are exported into
//  `_attachments/` by `MarkdownExporter`.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shows (and lets the user remove) a note's attachments.
struct AttachmentsBar: View {

    /// The note whose attachments are displayed.
    @Bindable var note: Note

    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(note.attachments ?? []) { attachment in
                    thumbnail(attachment)
                }
            }
            .padding(8)
        }
        .frame(height: 84)
        .background(theme.surface.swiftUIColor)
    }

    /// A single 64×64 thumbnail with a delete affordance.
    @ViewBuilder
    private func thumbnail(_ attachment: Attachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = image(from: attachment.data) {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.codeBackground.swiftUIColor)
                        .overlay {
                            Image(systemName: "doc")
                                .foregroundStyle(theme.textSecondary.swiftUIColor)
                        }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                delete(attachment)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(2)
        }
        .help(attachment.filename)
    }

    /// Decodes a SwiftUI `Image` from raw bytes, cross-platform.
    private func image(from data: Data?) -> Image? {
        guard let data else { return nil }
        #if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #endif
    }

    /// Removes an attachment from the note and the store.
    private func delete(_ attachment: Attachment) {
        note.attachments?.removeAll { $0.id == attachment.id }
        modelContext.delete(attachment)
        note.modifiedAt = Date()
    }
}
