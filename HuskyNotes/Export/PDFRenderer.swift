//
//  PDFRenderer.swift
//  HuskyNotes
//
//  Renders a note's Markdown — exactly as it appears in Read mode — into a
//  paginated PDF. It reuses `MarkdownReadingView` via `ImageRenderer`, so the
//  exported document matches the in-app rendering (headings, lists, task boxes,
//  quotes, code, tables). Dark themes are swapped for a light "paper" appearance
//  so the output stays legible and printer-friendly.
//
//  Pagination: the full content is rendered once, then sliced into US-Letter
//  pages with a uniform margin. Drawing the same content per page under a clip
//  window + vertical translation keeps it dependency-free and reliable.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Builds PDF data / files from a note's rendered Markdown.
@MainActor
enum PDFRenderer {

    /// US Letter at 72 dpi (8.5" × 11").
    private static let pageSize = CGSize(width: 612, height: 792)
    /// Uniform page margin.
    private static let margin: CGFloat = 48

    /// The content view used for both export and (on macOS) printing, themed for
    /// paper and constrained to the printable column width.
    static func contentView(for note: Note, theme: Theme, width: CGFloat) -> some View {
        MarkdownReadingView(
            markdown: note.body,
            theme: theme,
            attachments: note.attachments ?? []
        )
        .frame(width: width, alignment: .leading)
        .background(theme.background.swiftUIColor)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
    }

    /// The theme to render with: the active one if it's light, else a light paper
    /// appearance so the PDF doesn't print as a dark page.
    static func renderTheme(for theme: Theme) -> Theme {
        theme.isDark ? .paper : theme
    }

    /// Renders the note to paginated PDF data, or `nil` if rendering fails.
    static func pdfData(for note: Note, theme: Theme) -> Data? {
        let printTheme = renderTheme(for: theme)
        let contentWidth = pageSize.width - margin * 2
        let contentHeight = pageSize.height - margin * 2

        let renderer = ImageRenderer(content: contentView(for: note, theme: printTheme, width: contentWidth))

        let data = NSMutableData()
        let background = printTheme.background.platformColor.cgColor

        renderer.render { size, drawInContext in
            // `size` is (contentWidth, fullContentHeight). Under the identity
            // transform `drawInContext` places the content's top edge at
            // y = size.height (PDF y-up) and bottom at y = 0.
            let fullHeight = size.height
            let pageCount = max(1, Int(ceil(fullHeight / contentHeight)))

            var mediaBox = CGRect(origin: .zero, size: pageSize)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }

            for page in 0..<pageCount {
                ctx.beginPDFPage(nil)
                ctx.saveGState()

                // Paper fill behind the whole page (covers the margins too).
                ctx.setFillColor(background)
                ctx.fill(CGRect(origin: .zero, size: pageSize))

                // Clip to the content window, then position this page's slice so
                // the content offset `page * contentHeight` lands at the top margin.
                ctx.clip(to: CGRect(x: margin, y: margin, width: contentWidth, height: contentHeight))
                ctx.translateBy(
                    x: margin,
                    y: CGFloat(page) * contentHeight + (pageSize.height - margin - fullHeight)
                )
                drawInContext(ctx)

                ctx.restoreGState()
                ctx.endPDFPage()
            }
            ctx.closePDF()
        }

        return data.isEmpty ? nil : (data as Data)
    }

    /// Writes the note's PDF to a temporary file named after its title, returning
    /// the URL (for sharing). Returns `nil` if rendering or writing fails.
    static func pdfFile(for note: Note, theme: Theme) -> URL? {
        guard let data = pdfData(for: note, theme: theme) else { return nil }
        let base = MarkdownExporter.sanitise(note.title.isEmpty ? "Untitled" : note.title)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(base).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
