//
//  MarkdownReadingView.swift
//  HuskyNotes
//
//  A read-only, fully-rendered view of a note's Markdown — the counterpart to the
//  live source editor. Where the editor styles the source in place, this renders
//  native SwiftUI: headings, lists, task lists, quotes, code blocks, and — the
//  reason it exists — **real GFM tables** as SwiftUI grids.
//
//  Everything reads from the active `Theme`. Inline emphasis/code/links are
//  produced via `AttributedString(markdown:)` so we don't re-implement inline
//  parsing.
//

import SwiftUI
import Markdown
import PDFKit
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Renders Markdown source as native, themed, read-only SwiftUI.
struct MarkdownReadingView: View {

    let markdown: String
    let theme: Theme

    /// The note's attachments, so `_attachments/<file>` references render inline
    /// (images shown in place, PDFs as a thumbnail, other files as a card).
    var attachments: [Attachment] = []

    /// Invoked when an inline attachment is tapped, to open the full previewer.
    var onOpenAttachment: (Attachment) -> Void = { _ in }

    var body: some View {
        let document = Document(parsing: markdown, options: [.parseBlockDirectives])
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(document.children.enumerated()), id: \.offset) { _, child in
                block(child)
            }
        }
        .tint(theme.accent.swiftUIColor)
        .foregroundStyle(theme.textPrimary.swiftUIColor)
        // Read mode uses the standard system font (San Francisco), a touch larger
        // than the platform default for comfortable reading. Paragraphs, list
        // items, quotes and table cells inherit this; headings/code scale from it.
        .font(.system(size: readingBaseSize))
        // Match the editor's line spacing so prose reads with the same rhythm
        // rather than feeling cramped.
        .lineSpacing(readingLineSpacing)
    }

    // MARK: Block dispatch

    // Returns `AnyView` because blocks recurse (a quote contains blocks), which a
    // self-referential `some View` can't express.
    private func block(_ markup: Markup) -> AnyView {
        switch markup {
        case let heading as Heading:
            return AnyView(
                Text(plainText(of: heading))
                    .font(headingFont(heading.level))
                    .foregroundStyle(theme.heading.swiftUIColor)
                    .fixedSize(horizontal: false, vertical: true)
            )
        case let paragraph as Paragraph:
            // A paragraph that's just an attachment reference renders as a live
            // inline preview rather than broken Markdown.
            if let attachmentView = attachmentBlock(for: paragraph) {
                return AnyView(attachmentView)
            }
            return AnyView(
                Text(inline(paragraph))
                    .fixedSize(horizontal: false, vertical: true)
            )
        case let list as UnorderedList:
            return AnyView(listView(Array(list.listItems), ordered: false))
        case let list as OrderedList:
            return AnyView(listView(Array(list.listItems), ordered: true))
        case let quote as BlockQuote:
            return AnyView(quoteView(quote))
        case let code as CodeBlock:
            return AnyView(codeView(code.code, language: code.language))
        case let table as Markdown.Table:
            return AnyView(tableView(table))
        case is ThematicBreak:
            return AnyView(Divider().overlay(theme.textSecondary.swiftUIColor.opacity(0.4)))
        default:
            return AnyView(
                Text(plainText(of: markup))
                    .fixedSize(horizontal: false, vertical: true)
            )
        }
    }

    // MARK: Lists

    @ViewBuilder
    private func listView(_ items: [ListItem], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let checked = item.checkbox == .checked
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(for: item, ordered: ordered, number: index + 1)
                    Text(itemText(item))
                        .strikethrough(checked, color: theme.textSecondary.swiftUIColor)
                        .foregroundStyle((checked ? theme.textSecondary : theme.textPrimary).swiftUIColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func marker(for item: ListItem, ordered: Bool, number: Int) -> some View {
        if let checkbox = item.checkbox {
            taskCheckbox(checked: checkbox == .checked)
        } else if ordered {
            Text("\(number).")
                .foregroundStyle(theme.textSecondary.swiftUIColor)
                .monospacedDigit()
        } else {
            Text("•").foregroundStyle(theme.accent.swiftUIColor)
        }
    }

    /// An Obsidian-style task checkbox: a rounded square with a muted border when
    /// unchecked, and an accent fill with a white checkmark when checked. Sized
    /// to the body font and centred on the first line of the item.
    @ViewBuilder
    private func taskCheckbox(checked: Bool) -> some View {
        let side = readingBaseSize * 1.05
        let corner = side * 0.3
        // Captured as a local so the @Sendable alignment-guide closure doesn't
        // reference the main-actor-isolated `readingBaseSize` directly.
        let baselineOffset = readingBaseSize * 0.32
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(checked ? theme.accent.swiftUIColor : .clear)
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        checked ? theme.accent.swiftUIColor : theme.textSecondary.swiftUIColor.opacity(0.55),
                        lineWidth: 1.5
                    )
            }
            .overlay {
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: side * 0.62, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: side, height: side)
            // Centre the box on the line's text rather than sitting on the baseline.
            .alignmentGuide(.firstTextBaseline) { dims in
                dims[VerticalAlignment.center] + baselineOffset
            }
    }

    /// The inline text of a list item (its first paragraph).
    private func itemText(_ item: ListItem) -> AttributedString {
        let paragraph = item.children.compactMap { $0 as? Paragraph }.first
        return paragraph.map(inline) ?? AttributedString(plainText(of: item))
    }

    // MARK: Quotes / code

    @ViewBuilder
    private func quoteView(_ quote: BlockQuote) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(theme.quoteBar.swiftUIColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(quote.children.enumerated()), id: \.offset) { _, child in
                    block(child)
                }
            }
            .foregroundStyle(theme.textSecondary.swiftUIColor)
        }
    }

    @ViewBuilder
    private func codeView(_ code: String, language: String?) -> some View {
        let trimmed = code.hasSuffix("\n") ? String(code.dropLast()) : code
        Text(highlightedCode(trimmed, language: language))
            .font(.system(size: readingBaseSize, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(theme.codeBackground.swiftUIColor, in: RoundedRectangle(cornerRadius: 8))
    }

    /// Builds a language-coloured `AttributedString` for a code block, falling
    /// back to the plain code text colour for untokenised regions.
    private func highlightedCode(_ code: String, language: String?) -> AttributedString {
        var attributed = AttributedString(code)
        attributed.foregroundColor = theme.codeText.swiftUIColor
        for span in SyntaxHighlighter.spans(for: code, language: language) {
            guard let range = Range(span.range, in: attributed) else { continue }
            attributed[range].foregroundColor = SyntaxHighlighter.color(for: span.kind, in: theme).swiftUIColor
        }
        return attributed
    }

    // MARK: Tables

    @ViewBuilder
    private func tableView(_ table: Markdown.Table) -> some View {
        let headCells = Array(table.head.cells)
        let rows = Array(table.body.rows)
        let columnCount = max(headCells.count, rows.map { Array($0.cells).count }.max() ?? 0)
        let alignments = table.columnAlignments

        // Horizontal scroll so wide tables don't clip on compact widths.
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        Text(column < headCells.count ? cellText(headCells[column]) : AttributedString(""))
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.heading.swiftUIColor)
                            // One cell per column sets that column's alignment.
                            .gridColumnAlignment(columnAlignment(alignments, column))
                    }
                }
                Divider()
                    .overlay(theme.textSecondary.swiftUIColor.opacity(0.4))
                    .gridCellColumns(max(columnCount, 1))
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    let cells = Array(row.cells)
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { column in
                            Text(column < cells.count ? cellText(cells[column]) : AttributedString(""))
                        }
                    }
                    if index < rows.count - 1 {
                        Divider()
                            .overlay(theme.textSecondary.swiftUIColor.opacity(0.15))
                            .gridCellColumns(max(columnCount, 1))
                    }
                }
            }
            .padding(12)
            .background(theme.surface.swiftUIColor, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Maps a GFM column alignment to a SwiftUI grid-column alignment.
    private func columnAlignment(_ alignments: [Markdown.Table.ColumnAlignment?], _ column: Int) -> HorizontalAlignment {
        guard column < alignments.count else { return .leading }
        switch alignments[column] {
        case .center: return .center
        case .right: return .trailing
        default: return .leading
        }
    }

    /// Renders a table cell's inline content. We format the cell's **children**,
    /// never the cell itself — `Table.Cell.format()` trips an `assertionFailure`
    /// inside swift-markdown's `MarkupFormatter`, which crashes Read mode for any
    /// note containing a table.
    private func cellText(_ cell: Markdown.Table.Cell) -> AttributedString {
        attributedInline(cell.children.map { $0.format() }.joined())
    }

    // MARK: Inline attachments

    /// If `paragraph` is a lone image or attachment link pointing at one of the
    /// note's attachments, returns a view that previews it inline; else `nil`.
    private func attachmentBlock(for paragraph: Paragraph) -> AnyView? {
        guard !attachments.isEmpty else { return nil }
        // Keep only meaningful inlines (ignore whitespace-only text nodes).
        let significant = paragraph.children.filter { child in
            if let text = child as? Markdown.Text {
                return !text.string.trimmingCharacters(in: .whitespaces).isEmpty
            }
            return true
        }
        guard significant.count == 1, let only = significant.first else { return nil }

        if let image = only as? Markdown.Image, let attachment = attachment(forSource: image.source) {
            return AnyView(imageBlock(attachment))
        }
        if let link = only as? Markdown.Link, let attachment = attachment(forSource: link.destination) {
            return AnyView(fileBlock(attachment))
        }
        return nil
    }

    /// Finds the attachment whose filename matches a `_attachments/<file>` source.
    private func attachment(forSource source: String?) -> Attachment? {
        guard let source, !source.isEmpty else { return nil }
        let last = (source as NSString).lastPathComponent
        let name = last.removingPercentEncoding ?? last
        return attachments.first { $0.filename == name }
    }

    /// An inline image preview, tappable to open the full-screen viewer.
    @ViewBuilder
    private func imageBlock(_ attachment: Attachment) -> some View {
        if let image = swiftUIImage(from: attachment.data) {
            Button { onOpenAttachment(attachment) } label: {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 420, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        } else {
            fileChip(attachment)
        }
    }

    /// An inline file preview: a PDF first-page thumbnail, or a typed card for
    /// other documents. Tappable to open the full viewer.
    @ViewBuilder
    private func fileBlock(_ attachment: Attachment) -> some View {
        if isPDF(attachment), let thumb = pdfThumbnail(attachment.data) {
            Button { onOpenAttachment(attachment) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    thumb
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 460, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(theme.textSecondary.swiftUIColor.opacity(0.2))
                        )
                    fileCaption(attachment)
                }
            }
            .buttonStyle(.plain)
        } else {
            fileChip(attachment)
        }
    }

    /// A compact typed card (icon + name + size) for a non-previewable file.
    @ViewBuilder
    private func fileChip(_ attachment: Attachment) -> some View {
        Button { onOpenAttachment(attachment) } label: {
            HStack(spacing: 10) {
                Image(systemName: fileSymbol(attachment))
                    .font(.title2)
                    .foregroundStyle(theme.accent.swiftUIColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename.isEmpty ? "Attachment" : attachment.filename)
                        .lineLimit(1)
                        .foregroundStyle(theme.textPrimary.swiftUIColor)
                    Text(byteString(attachment.byteCount))
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary.swiftUIColor)
                }
                Spacer(minLength: 0)
                Image(systemName: "eye")
                    .foregroundStyle(theme.textSecondary.swiftUIColor)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface.swiftUIColor, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func fileCaption(_ attachment: Attachment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: fileSymbol(attachment))
            Text(attachment.filename.isEmpty ? "Attachment" : attachment.filename).lineLimit(1)
            Text("· \(byteString(attachment.byteCount))")
        }
        .font(.caption)
        .foregroundStyle(theme.textSecondary.swiftUIColor)
    }

    private func isPDF(_ attachment: Attachment) -> Bool {
        attachment.contentType == UTType.pdf.identifier
            || attachment.filename.lowercased().hasSuffix(".pdf")
    }

    private func fileSymbol(_ attachment: Attachment) -> String {
        isPDF(attachment) ? "doc.richtext" : "doc"
    }

    private func byteString(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    /// A first-page thumbnail of a PDF as a SwiftUI `Image`.
    private func pdfThumbnail(_ data: Data?) -> SwiftUI.Image? {
        guard let data, let document = PDFDocument(data: data), let page = document.page(at: 0) else { return nil }
        let thumb = page.thumbnail(of: CGSize(width: 800, height: 1000), for: .mediaBox)
        #if canImport(UIKit)
        return SwiftUI.Image(uiImage: thumb)
        #else
        return SwiftUI.Image(nsImage: thumb)
        #endif
    }

    /// A SwiftUI `Image` from raw bytes, or `nil` if they aren't a valid image.
    private func swiftUIImage(from data: Data?) -> SwiftUI.Image? {
        guard let data else { return nil }
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return SwiftUI.Image(uiImage: image)
        #else
        guard let image = NSImage(data: data) else { return nil }
        return SwiftUI.Image(nsImage: image)
        #endif
    }

    // MARK: Inline + fonts

    /// Renders a node's inline content (bold/italic/code/links/highlights) as an
    /// `AttributedString` via SwiftUI's Markdown parser.
    private func inline(_ markup: Markup) -> AttributedString {
        attributedInline(markup.format())
    }

    /// Parses inline Markdown, additionally honouring highlighter spans
    /// (`<mark class="hl-…">…</mark>`) — which the Markdown parser doesn't model —
    /// by splitting them out and painting the fill + ink behind their content.
    private func attributedInline(_ formatted: String) -> AttributedString {
        guard formatted.contains("<mark class=\"hl-"),
              let regex = try? NSRegularExpression(pattern: HighlightColor.spanPattern) else {
            return parseInline(formatted)
        }
        let ns = formatted as NSString
        var result = AttributedString()
        var cursor = 0
        for match in regex.matches(in: formatted, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                result.append(parseInline(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            var piece = parseInline(ns.substring(with: match.range(at: 2)))
            if let color = HighlightColor(rawValue: ns.substring(with: match.range(at: 1))) {
                piece.backgroundColor = color.fill.swiftUIColor
                piece.foregroundColor = color.ink.swiftUIColor
            }
            result.append(piece)
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result.append(parseInline(ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))))
        }
        return result
    }

    /// Parses a fragment of inline Markdown to an `AttributedString`, falling
    /// back to the literal text if parsing fails.
    private func parseInline(_ markdown: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let attributed = try? AttributedString(markdown: markdown, options: options) {
            return attributed
        }
        return AttributedString(markdown)
    }

    /// Recursively collects the plain text of a node (handles `any Markup`,
    /// which doesn't expose `plainText` directly).
    private func plainText(of markup: Markup) -> String {
        if let text = markup as? Markdown.Text { return text.string }
        return markup.children.map { plainText(of: $0) }.joined()
    }

    /// The base body size for Read mode: the platform-standard system body size,
    /// nudged slightly larger so notes read comfortably. Everything in reading
    /// mode (body, headings, code, checkboxes) is sized from this.
    private var readingBaseSize: CGFloat {
        #if os(macOS)
        return 15   // macOS standard body is 13pt
        #else
        return 18   // iOS standard body is 17pt
        #endif
    }

    /// Extra spacing between lines, reproducing the editor's line-height
    /// multiplier (`theme.lineSpacing`, applied there as `lineHeightMultiple`).
    /// SwiftUI's `.lineSpacing` is additive, so we add the natural line height
    /// (≈ 1.2 × point size) times the fraction above 1 — giving Read mode the
    /// same vertical rhythm as the editor instead of SwiftUI's tight default.
    private var readingLineSpacing: CGFloat {
        readingBaseSize * 1.2 * CGFloat(max(0, theme.lineSpacing - 1.0))
    }

    private func headingFont(_ level: Int) -> Font {
        let base = readingBaseSize
        switch max(1, min(level, 6)) {
        case 1: return .system(size: base * 1.9, weight: .bold)
        case 2: return .system(size: base * 1.6, weight: .bold)
        case 3: return .system(size: base * 1.35, weight: .bold)
        case 4: return .system(size: base * 1.2, weight: .semibold)
        case 5: return .system(size: base * 1.1, weight: .semibold)
        default: return .system(size: base, weight: .semibold)
        }
    }
}
