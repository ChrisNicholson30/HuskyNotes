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

/// Renders Markdown source as native, themed, read-only SwiftUI.
struct MarkdownReadingView: View {

    let markdown: String
    let theme: Theme

    var body: some View {
        let document = Document(parsing: markdown, options: [.parseBlockDirectives])
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(document.children.enumerated()), id: \.offset) { _, child in
                block(child)
            }
        }
        .tint(theme.accent.swiftUIColor)
        .foregroundStyle(theme.textPrimary.swiftUIColor)
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
            return AnyView(codeView(code.code))
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
            Image(systemName: checkbox == .checked ? "checkmark.square.fill" : "square")
                .foregroundStyle((checkbox == .checked ? theme.accent : theme.textSecondary).swiftUIColor)
        } else if ordered {
            Text("\(number).")
                .foregroundStyle(theme.textSecondary.swiftUIColor)
                .monospacedDigit()
        } else {
            Text("•").foregroundStyle(theme.accent.swiftUIColor)
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
    private func codeView(_ code: String) -> some View {
        Text(code.hasSuffix("\n") ? String(code.dropLast()) : code)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(theme.codeText.swiftUIColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(theme.codeBackground.swiftUIColor, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Tables

    @ViewBuilder
    private func tableView(_ table: Markdown.Table) -> some View {
        let headCells = Array(table.head.cells)
        let rows = Array(table.body.rows)
        let columnCount = max(headCells.count, rows.map { Array($0.cells).count }.max() ?? 0)

        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                ForEach(0..<columnCount, id: \.self) { column in
                    Text(column < headCells.count ? inline(headCells[column]) : AttributedString(""))
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.heading.swiftUIColor)
                }
            }
            Divider()
                .overlay(theme.textSecondary.swiftUIColor.opacity(0.4))
                .gridCellColumns(max(columnCount, 1))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let cells = Array(row.cells)
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        Text(column < cells.count ? inline(cells[column]) : AttributedString(""))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface.swiftUIColor, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Inline + fonts

    /// Renders a node's inline content (bold/italic/code/links) as an
    /// `AttributedString` via SwiftUI's Markdown parser.
    private func inline(_ markup: Markup) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let attributed = try? AttributedString(markdown: markup.format(), options: options) {
            return attributed
        }
        return AttributedString(plainText(of: markup))
    }

    /// Recursively collects the plain text of a node (handles `any Markup`,
    /// which doesn't expose `plainText` directly).
    private func plainText(of markup: Markup) -> String {
        if let text = markup as? Markdown.Text { return text.string }
        return markup.children.map { plainText(of: $0) }.joined()
    }

    private func headingFont(_ level: Int) -> Font {
        let base = CGFloat(theme.bodySize)
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
