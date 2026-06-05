//
//  AttachmentsBar.swift
//  HuskyNotes
//
//  A horizontal strip of a note's attachments shown beneath the editor. Images
//  render as thumbnails; other files (PDFs, etc.) show a typed chip with an icon,
//  name and size. Tapping an item opens it in `AttachmentViewer` (PDFKit for
//  PDFs, Quick Look for everything else); each can be removed.
//
//  Attachment bytes live in SwiftData external storage and are exported into
//  `_attachments/` by `MarkdownExporter`.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shows, previews and removes a note's attachments.
struct AttachmentsBar: View {

    /// The note whose attachments are displayed.
    @Bindable var note: Note

    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    /// The attachment currently being previewed (drives the viewer sheet).
    @State private var previewing: Attachment?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(note.attachments ?? []) { attachment in
                    item(attachment)
                }
            }
            .padding(8)
        }
        .frame(height: 92)
        .background(theme.surface.swiftUIColor)
        .sheet(item: $previewing) { attachment in
            AttachmentViewer(attachment: attachment)
                .environment(themeStore)
        }
    }

    /// A single attachment cell — image thumbnail or file chip — with a delete
    /// affordance, tappable to preview.
    @ViewBuilder
    private func item(_ attachment: Attachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                previewing = attachment
            } label: {
                if let image = image(from: attachment.data) {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    fileChip(attachment)
                }
            }
            .buttonStyle(.plain)

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

    /// A non-image file chip: type icon + truncated name + size.
    @ViewBuilder
    private func fileChip(_ attachment: Attachment) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon(for: attachment))
                .font(.title2)
                .foregroundStyle(theme.accent.swiftUIColor)
            Text(attachment.filename.isEmpty ? "File" : attachment.filename)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(theme.textPrimary.swiftUIColor)
            if attachment.byteCount > 0 {
                Text(sizeText(attachment.byteCount))
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textSecondary.swiftUIColor)
            }
        }
        .padding(6)
        .frame(width: 92, height: 64)
        .background(theme.codeBackground.swiftUIColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// SF Symbol for an attachment based on its type.
    private func icon(for attachment: Attachment) -> String {
        if attachment.contentType == UTType.pdf.identifier
            || attachment.filename.lowercased().hasSuffix(".pdf") {
            return "doc.richtext"
        }
        if let id = attachment.contentType, let type = UTType(id) {
            if type.conforms(to: .movie) { return "film" }
            if type.conforms(to: .audio) { return "waveform" }
            if type.conforms(to: .text) { return "doc.text" }
            if type.conforms(to: .archive) { return "doc.zipper" }
        }
        return "doc.fill"
    }

    /// Human-readable byte size.
    private func sizeText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
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
