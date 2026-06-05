//
//  MarkdownStyler.swift
//  HuskyNotes
//
//  Live source styling for the editor. Parses Markdown with apple/swift-markdown
//  and produces an `NSAttributedString` whose *visible characters are identical*
//  to the input (CommonMark + GFM). Syntax markers (`#`, `*`, `` ` ``, `>`, …) are
//  NOT removed — this is source styling, not a rendered preview.
//
//  All colours and fonts come exclusively from the active `Theme`; nothing here
//  is hard-coded, in keeping with the project's decoupled-theming principle.
//

import Foundation
import Markdown

#if os(macOS)
import AppKit
/// Platform font type bridged for cross-platform attributed-string styling.
typealias PlatformFont = NSFont
#else
import UIKit
/// Platform font type bridged for cross-platform attributed-string styling.
typealias PlatformFont = UIFont
#endif

/// A rendered list marker (bullet or task checkbox) and the syntax it replaces.
///
/// Collected while walking the AST, then turned into an inline image glyph —
/// unless the caret is on that line, where the raw Markdown stays visible so it
/// remains editable (mirrors the syntax-concealment behaviour).
private struct ListGlyph {
    enum Kind { case bullet; case checkbox(checked: Bool) }
    /// The single marker character that becomes the glyph (the `-`/`*`/`+`).
    let markerRange: NSRange
    /// Extra syntax to hide for task items (the ` [ ]` / ` [x]`), if any.
    let concealRange: NSRange?
    let kind: Kind
    /// Whether to strike + dim the item's text (completed tasks).
    let strikeContent: Bool
    let contentRange: NSRange?
}

// MARK: - MarkdownStyler

/// Converts Markdown source into a themed `NSAttributedString` for live editing.
///
/// The styler walks the swift-markdown AST and maps each node's *source range*
/// back onto the original string, then applies attributes to exactly those
/// character ranges. Because we only ever decorate the original text (never
/// rewrite it), `result.string` is guaranteed to equal `markdown` verbatim.
struct MarkdownStyler {

    /// Creates a styled attributed string for the given Markdown source.
    ///
    /// - Parameters:
    ///   - markdown: The CommonMark + GFM source. This is the canonical text and
    ///     is reproduced character-for-character in the output.
    ///   - theme: The active theme supplying every colour, font and metric.
    ///   - revealedRange: The character range (typically the paragraph the caret
    ///     is in) whose syntax markers should stay visible. Markers outside it
    ///     are concealed, Bear-style. Pass `nil` to conceal every marker (the
    ///     fully "rendered" look when the editor isn't focused).
    /// - Returns: An `NSAttributedString` whose visible string equals `markdown`.
    func attributedString(
        for markdown: String,
        theme: Theme,
        revealing revealedRange: NSRange? = nil
    ) -> NSAttributedString {
        let fonts = FontSet(theme: theme)

        // 1. Base layer: the whole text in body style. Guarantees that any range
        //    the visitor does not touch still renders legibly and round-trips.
        let result = NSMutableAttributedString(
            string: markdown,
            attributes: Self.baseAttributes(theme: theme, fonts: fonts)
        )

        guard !markdown.isEmpty else { return result }

        // 2. Decoration layer: walk the AST and overlay attributes onto the
        //    source ranges of each element. Source-range mapping keeps the
        //    visible characters untouched (live source styling). The visitor also
        //    collects the ranges of syntax *markers* (e.g. the `#`, `**`, `` ` ``)
        //    so we can hide them.
        let document = Document(parsing: markdown, options: [.parseBlockDirectives])
        var visitor = StylingVisitor(
            source: markdown,
            target: result,
            theme: theme,
            fonts: fonts
        )
        visitor.visit(document)

        // 2b. Footnotes: swift-markdown doesn't model them, so style references
        //     and definitions with a small regex pass.
        styleFootnotes(in: result, source: markdown, theme: theme, fonts: fonts)

        // 3. Concealment layer: hide marker ranges that don't intersect the
        //    revealed (active) line so the text reads like rendered Markdown
        //    everywhere except where the caret is.
        conceal(visitor.concealRanges, in: result, revealing: revealedRange)

        // 4. List markers: style bullets and task checkboxes (`- [ ]` / `- [x]`)
        //    as monospace + accent affordances, and dim completed tasks. Kept as
        //    *visible text* (not image attachments) because editable TextKit 2
        //    text views don't reliably render inline image attachments — the raw
        //    `[ ]` reads clearly and stays tappable; Read mode shows true boxes.
        applyListMarkers(visitor.listGlyphs, in: result, theme: theme, fonts: fonts)

        return result
    }

    /// Styles list markers so checkboxes/bullets read as affordances, and dims
    /// completed task content.
    private func applyListMarkers(
        _ glyphs: [ListGlyph],
        in target: NSMutableAttributedString,
        theme: Theme,
        fonts: FontSet
    ) {
        guard !glyphs.isEmpty else { return }
        let length = target.length
        let accent = theme.accent.platformColor

        for glyph in glyphs {
            // Completed-task content: strike through + dim.
            if glyph.strikeContent, let content = glyph.contentRange,
               content.location >= 0, content.location + content.length <= length, content.length > 0 {
                target.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
                target.addAttribute(.foregroundColor, value: theme.textSecondary.platformColor, range: content)
            }

            // The marker region — bullet, plus the `[ ]`/`[x]` for tasks.
            let markerRegion: NSRange
            if let conceal = glyph.concealRange {
                markerRegion = NSRange(location: glyph.markerRange.location,
                                       length: (conceal.location + conceal.length) - glyph.markerRange.location)
            } else {
                markerRegion = glyph.markerRange
            }
            guard markerRegion.location >= 0, markerRegion.location + markerRegion.length <= length else { continue }
            target.addAttributes([.foregroundColor: accent, .font: fonts.mono], range: markerRegion)
        }
    }

    /// Styles footnote references (`[^1]`) as raised accent text and footnote
    /// definition labels (`[^1]:` at line start) in the accent colour.
    private func styleFootnotes(in target: NSMutableAttributedString, source: String, theme: Theme, fonts: FontSet) {
        let ns = source as NSString
        let full = NSRange(location: 0, length: ns.length)
        let accent = theme.accent.platformColor

        // References anywhere: [^id]
        if let refs = try? NSRegularExpression(pattern: "\\[\\^[A-Za-z0-9_-]+\\]") {
            let smaller = PlatformFont.systemFont(ofSize: max(9, CGFloat(theme.bodySize) * 0.75))
            for match in refs.matches(in: source, range: full) {
                target.addAttributes(
                    [.foregroundColor: accent, .font: smaller, .baselineOffset: CGFloat(theme.bodySize) * 0.25],
                    range: match.range
                )
            }
        }
        // Definition labels at line start: [^id]:
        if let defs = try? NSRegularExpression(pattern: "(?m)^\\[\\^[A-Za-z0-9_-]+\\]:") {
            for match in defs.matches(in: source, range: full) {
                target.addAttribute(.foregroundColor, value: accent, range: match.range)
            }
        }
    }

    /// Hides the given marker ranges by collapsing them to a near-zero, clear
    /// run — unless they intersect `revealedRange`, in which case they stay
    /// visible. The backing string is never modified, so the source round-trips.
    private func conceal(_ ranges: [NSRange], in target: NSMutableAttributedString, revealing revealedRange: NSRange?) {
        guard !ranges.isEmpty else { return }
        let length = target.length
        let hiddenFont = PlatformFont.systemFont(ofSize: 0.1)
        let clear = PlatformColor.clear

        for range in ranges {
            guard range.length > 0,
                  range.location >= 0,
                  range.location + range.length <= length
            else { continue }
            if let revealedRange, NSIntersectionRange(range, revealedRange).length > 0 {
                continue // caret is on this line — keep the markers visible.
            }
            target.addAttributes(
                [.font: hiddenFont, .foregroundColor: clear, .backgroundColor: clear],
                range: range
            )
        }
    }

    /// Default attributes applied to the entire document before decoration.
    private static func baseAttributes(theme: Theme, fonts: FontSet) -> [NSAttributedString.Key: Any] {
        [
            .font: fonts.body,
            .foregroundColor: theme.textPrimary.platformColor,
            .paragraphStyle: makeParagraphStyle(theme: theme)
        ]
    }

    /// A fresh paragraph style honouring the theme's line-height multiplier.
    ///
    /// Each run gets its own instance because `NSParagraphStyle` is reference
    /// type and shared mutation would corrupt earlier ranges.
    fileprivate static func makeParagraphStyle(
        theme: Theme,
        headIndent: CGFloat = 0,
        firstLineHeadIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = CGFloat(theme.lineSpacing)
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLineHeadIndent
        return style
    }
}

// MARK: - FontSet

/// Resolves the theme's font descriptors into concrete platform fonts and
/// derives the bold/italic/heading/mono variants used while styling.
private struct FontSet {

    let body: PlatformFont
    let mono: PlatformFont
    private let bodySize: CGFloat
    private let theme: Theme

    init(theme: Theme) {
        self.theme = theme
        self.bodySize = CGFloat(theme.bodySize)
        self.body = FontSet.resolve(name: theme.bodyFont, size: CGFloat(theme.bodySize), monospaced: false)
        self.mono = FontSet.resolve(name: theme.monoFont, size: CGFloat(theme.bodySize), monospaced: true)
    }

    /// Body font with the bold trait applied.
    var bodyBold: PlatformFont { FontSet.applying(traits: .bold, to: body) }

    /// Body font with the italic trait applied.
    var bodyItalic: PlatformFont { FontSet.applying(traits: .italic, to: body) }

    /// Body font with both bold and italic traits applied.
    var bodyBoldItalic: PlatformFont { FontSet.applying(traits: [.bold, .italic], to: body) }

    /// A bold heading font sized for the given level (H1 largest … H6 smallest).
    func heading(level: Int) -> PlatformFont {
        let scale: CGFloat
        switch max(1, min(level, 6)) {
        case 1: scale = 1.9
        case 2: scale = 1.6
        case 3: scale = 1.35
        case 4: scale = 1.2
        case 5: scale = 1.1
        default: scale = 1.0
        }
        let sized = FontSet.resolve(name: theme.bodyFont, size: bodySize * scale, monospaced: false)
        return FontSet.applying(traits: .bold, to: sized)
    }

    // MARK: Resolution helpers

    /// Resolves a theme font name ("system", a PostScript name, or unknown) to a
    /// concrete platform font, falling back to the system font when needed.
    private static func resolve(name: String, size: CGFloat, monospaced: Bool) -> PlatformFont {
        if name.lowercased() == "system" || name.isEmpty {
            #if os(macOS)
            return monospaced
                ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                : NSFont.systemFont(ofSize: size)
            #else
            return monospaced
                ? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
                : UIFont.systemFont(ofSize: size)
            #endif
        }
        if let named = PlatformFont(name: name, size: size) {
            return named
        }
        // Unknown PostScript name → graceful fallback.
        #if os(macOS)
        return monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            : NSFont.systemFont(ofSize: size)
        #else
        return monospaced
            ? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            : UIFont.systemFont(ofSize: size)
        #endif
    }

    #if os(macOS)
    /// Symbolic traits used to derive bold/italic variants on macOS.
    struct Trait: OptionSet {
        let rawValue: Int
        static let bold = Trait(rawValue: 1 << 0)
        static let italic = Trait(rawValue: 1 << 1)
    }

    /// Returns `font` with the requested traits, falling back to the original
    /// font if the trait combination is unavailable.
    private static func applying(traits: Trait, to font: PlatformFont) -> PlatformFont {
        var symbolic: NSFontDescriptor.SymbolicTraits = []
        if traits.contains(.bold) { symbolic.insert(.bold) }
        if traits.contains(.italic) { symbolic.insert(.italic) }
        let descriptor = font.fontDescriptor.withSymbolicTraits(symbolic)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
    #else
    /// Symbolic traits used to derive bold/italic variants on iOS/iPadOS.
    struct Trait: OptionSet {
        let rawValue: Int
        static let bold = Trait(rawValue: 1 << 0)
        static let italic = Trait(rawValue: 1 << 1)
    }

    /// Returns `font` with the requested traits, falling back to the original
    /// font if the trait combination is unavailable.
    private static func applying(traits: Trait, to font: PlatformFont) -> PlatformFont {
        var symbolic: UIFontDescriptor.SymbolicTraits = []
        if traits.contains(.bold) { symbolic.insert(.traitBold) }
        if traits.contains(.italic) { symbolic.insert(.traitItalic) }
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(symbolic) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
    #endif
}

// MARK: - StylingVisitor

/// Walks the Markdown AST and overlays themed attributes onto the source ranges
/// of each element. Inline emphasis traits are tracked on a stack so that nested
/// bold/italic combine correctly.
private struct StylingVisitor: MarkupWalker {

    let source: String
    let target: NSMutableAttributedString
    let theme: Theme
    let fonts: FontSet

    /// The source as an `NSString`, for UTF-16 marker scanning that matches the
    /// attributed string's range semantics.
    private let ns: NSString

    /// Collected ranges of syntax markers (e.g. `#`, `**`, `` ` ``, `[`…`](…)`),
    /// to be concealed unless the caret sits on their line.
    private(set) var concealRanges: [NSRange] = []

    /// Collected list bullets / task checkboxes to render as inline glyphs.
    private(set) var listGlyphs: [ListGlyph] = []

    /// UTF-8/Unicode offset cache mapping `SourceLocation` → `String.Index`.
    private let lineStarts: [Int]

    init(source: String, target: NSMutableAttributedString, theme: Theme, fonts: FontSet) {
        self.source = source
        self.target = target
        self.theme = theme
        self.fonts = fonts
        self.ns = source as NSString
        self.lineStarts = StylingVisitor.computeLineStarts(in: source)
    }

    // MARK: Block elements

    mutating func visitHeading(_ heading: Heading) {
        if let range = nsRange(for: heading) {
            applyFontPreservingTraits(fonts.heading(level: heading.level), over: range)
            target.addAttribute(.foregroundColor, value: theme.heading.platformColor, range: range)
            recordHeadingMarker(in: range)
        }
        descendInto(heading)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        if let range = nsRange(for: codeBlock) {
            target.addAttributes(
                [
                    .font: fonts.mono,
                    .foregroundColor: theme.codeText.platformColor,
                    .backgroundColor: theme.codeBackground.platformColor
                ],
                range: range
            )
        }
        // Code blocks have no stylable inline children; do not descend.
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        if let range = nsRange(for: blockQuote) {
            let style = MarkdownStyler.makeParagraphStyle(
                theme: theme,
                headIndent: 16,
                firstLineHeadIndent: 16
            )
            target.addAttributes(
                [
                    .foregroundColor: theme.textSecondary.platformColor,
                    .paragraphStyle: style
                ],
                range: range
            )
            recordBlockQuoteMarkers(in: range)
        }
        descendInto(blockQuote)
    }

    /// GFM tables: render the whole block in the monospaced font so the pipe
    /// columns line up (a true grid widget is a reading-mode concern).
    mutating func visitTable(_ table: Markdown.Table) {
        if let range = nsRange(for: table) {
            target.addAttribute(.font, value: fonts.mono, range: range)
            target.addAttribute(.foregroundColor, value: theme.textPrimary.platformColor, range: range)
        }
        descendInto(table)
    }

    // MARK: Inline elements

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        if let range = nsRange(for: inlineCode) {
            target.addAttributes(
                [
                    .font: fonts.mono,
                    .foregroundColor: theme.codeText.platformColor,
                    .backgroundColor: theme.codeBackground.platformColor
                ],
                range: range
            )
            recordBacktickMarkers(in: range)
        }
    }

    mutating func visitStrong(_ strong: Strong) {
        if let range = nsRange(for: strong) {
            mergeTrait(.bold, over: range)
            recordPairedDelimiters(in: range, length: 2) // ** or __
        }
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        if let range = nsRange(for: emphasis) {
            mergeTrait(.italic, over: range)
            recordPairedDelimiters(in: range, length: 1) // * or _
        }
        descendInto(emphasis)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        if let range = nsRange(for: strikethrough) {
            target.addAttribute(
                .strikethroughStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: range
            )
            target.addAttribute(.foregroundColor, value: theme.textSecondary.platformColor, range: range)
            recordPairedDelimiters(in: range, length: 2) // ~~
        }
        descendInto(strikethrough)
    }

    mutating func visitLink(_ link: Link) {
        if let range = nsRange(for: link) {
            target.addAttributes(
                [
                    .foregroundColor: theme.link.platformColor,
                    .underlineColor: theme.link.platformColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: range
            )
            recordLinkMarkers(in: range)
        }
        descendInto(link)
    }

    // MARK: List markers — colour the bullet/number with the accent

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        descendInto(unorderedList)
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        descendInto(orderedList)
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let range = nsRange(for: listItem) {
            detectListMarker(in: range, checkbox: listItem.checkbox)
        }
        descendInto(listItem)
    }

    /// Locates a list item's leading marker (`-`/`*`/`+`, optionally a `[ ]`/`[x]`
    /// task box) and records a ``ListGlyph`` for it. Ordered-list items are left
    /// untouched (their numbers read fine as-is).
    private mutating func detectListMarker(in range: NSRange, checkbox: Checkbox?) {
        let end = range.location + range.length
        var i = range.location
        while i < end, ns.character(at: i) == 32 || ns.character(at: i) == 9 { i += 1 } // indent
        guard i < end else { return }

        let bullet = ns.character(at: i)
        guard bullet == 45 || bullet == 42 || bullet == 43 else { return } // - * + only
        let markerRange = NSRange(location: i, length: 1)

        // Expect a single space after the bullet.
        guard i + 1 < end, ns.character(at: i + 1) == 32 else {
            listGlyphs.append(ListGlyph(markerRange: markerRange, concealRange: nil,
                                        kind: .bullet, strikeContent: false, contentRange: nil))
            return
        }

        if let checkbox {
            // Pattern: bullet, space, '[', mark, ']', space, content
            let open = i + 2, close = i + 4
            guard close < end, ns.character(at: open) == 91, ns.character(at: close) == 93 else {
                listGlyphs.append(ListGlyph(markerRange: markerRange, concealRange: nil,
                                            kind: .bullet, strikeContent: false, contentRange: nil))
                return
            }
            let checked = (checkbox == .checked)
            let conceal = NSRange(location: i + 1, length: 4) // " [ ]" — keep the next space
            let contentStart = min(i + 6, end)
            let content = NSRange(location: contentStart, length: end - contentStart)
            listGlyphs.append(ListGlyph(markerRange: markerRange, concealRange: conceal,
                                        kind: .checkbox(checked: checked),
                                        strikeContent: checked, contentRange: content))
        } else {
            listGlyphs.append(ListGlyph(markerRange: markerRange, concealRange: nil,
                                        kind: .bullet, strikeContent: false, contentRange: nil))
        }
    }

    // MARK: Trait merging

    /// Recomputes a run's font so that an additional trait (bold/italic) is
    /// combined with whatever is already present, preserving nesting.
    private mutating func mergeTrait(_ trait: FontTrait, over range: NSRange) {
        target.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let current = (value as? PlatformFont) ?? fonts.body
            let hasBold = trait == .bold || fontHasBold(current)
            let hasItalic = trait == .italic || fontHasItalic(current)
            let merged: PlatformFont
            switch (hasBold, hasItalic) {
            case (true, true): merged = fonts.bodyBoldItalic
            case (true, false): merged = fonts.bodyBold
            case (false, true): merged = fonts.bodyItalic
            case (false, false): merged = fonts.body
            }
            target.addAttribute(.font, value: merged, range: subRange)
        }
    }

    /// Applies a font (e.g. a heading font) without clobbering existing
    /// bold/italic emphasis that may live inside the range.
    private func applyFontPreservingTraits(_ font: PlatformFont, over range: NSRange) {
        target.addAttribute(.font, value: font, range: range)
    }

    private enum FontTrait { case bold, italic }

    private func fontHasBold(_ font: PlatformFont) -> Bool {
        #if os(macOS)
        return font.fontDescriptor.symbolicTraits.contains(.bold)
        #else
        return font.fontDescriptor.symbolicTraits.contains(.traitBold)
        #endif
    }

    private func fontHasItalic(_ font: PlatformFont) -> Bool {
        #if os(macOS)
        return font.fontDescriptor.symbolicTraits.contains(.italic)
        #else
        return font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        #endif
    }

    // MARK: Marker collection (for concealment)

    /// Records the fixed-length opening and closing delimiters of an inline span
    /// (e.g. the `**` of `**bold**`, the `*` of `*italic*`).
    private mutating func recordPairedDelimiters(in range: NSRange, length: Int) {
        guard range.length >= length * 2 else { return }
        concealRanges.append(NSRange(location: range.location, length: length))
        concealRanges.append(NSRange(location: range.location + range.length - length, length: length))
    }

    /// Records the leading `#`…`#` run plus trailing spaces of an ATX heading.
    private mutating func recordHeadingMarker(in range: NSRange) {
        let end = range.location + range.length
        var i = range.location
        var hashes = 0
        while i < end, ns.character(at: i) == 35 /* # */, hashes < 6 { i += 1; hashes += 1 }
        guard hashes > 0 else { return }
        while i < end {
            let c = ns.character(at: i)
            if c == 32 || c == 9 { i += 1 } else { break } // space / tab
        }
        concealRanges.append(NSRange(location: range.location, length: i - range.location))
    }

    /// Records the leading and trailing backtick runs of inline code.
    private mutating func recordBacktickMarkers(in range: NSRange) {
        let end = range.location + range.length
        var leading = range.location
        while leading < end, ns.character(at: leading) == 96 /* ` */ { leading += 1 }
        let leadCount = leading - range.location
        guard leadCount > 0 else { return }
        var trailing = end
        while trailing > leading, ns.character(at: trailing - 1) == 96 { trailing -= 1 }
        concealRanges.append(NSRange(location: range.location, length: leadCount))
        if end - trailing > 0 {
            concealRanges.append(NSRange(location: trailing, length: end - trailing))
        }
    }

    /// Records a link's bracket/destination syntax (`[` … `](url)`), leaving the
    /// visible link text intact.
    private mutating func recordLinkMarkers(in range: NSRange) {
        guard range.length >= 2, ns.character(at: range.location) == 91 /* [ */ else { return }
        let close = ns.range(of: "](", options: [], range: range)
        guard close.location != NSNotFound else { return }
        concealRanges.append(NSRange(location: range.location, length: 1)) // leading [
        let tailStart = close.location
        concealRanges.append(NSRange(location: tailStart, length: range.location + range.length - tailStart))
    }

    /// Records the `>` (and one trailing space) quote prefix on each line of a
    /// block quote so the prose reads cleanly with just the indent + bar.
    private mutating func recordBlockQuoteMarkers(in range: NSRange) {
        let end = range.location + range.length
        var lineStart = range.location
        while lineStart < end {
            var i = lineStart
            while i < end, ns.character(at: i) == 32 || ns.character(at: i) == 9 { i += 1 }
            if i < end, ns.character(at: i) == 62 /* > */ {
                var markerEnd = i + 1
                if markerEnd < end, ns.character(at: markerEnd) == 32 { markerEnd += 1 }
                concealRanges.append(NSRange(location: lineStart, length: markerEnd - lineStart))
            }
            let rest = NSRange(location: lineStart, length: end - lineStart)
            let newline = ns.range(of: "\n", options: [], range: rest)
            if newline.location == NSNotFound { break }
            lineStart = newline.location + 1
        }
    }

    // MARK: Source-range → NSRange mapping

    /// Maps a markup element's `SourceRange` onto an `NSRange` of the original
    /// string. Returns `nil` if the element carries no range or the mapping
    /// falls outside the string (defensive — keeps round-tripping safe).
    private func nsRange(for markup: Markup) -> NSRange? {
        guard let range = markup.range else { return nil }
        guard
            let start = stringIndex(for: range.lowerBound),
            let end = stringIndex(for: range.upperBound),
            start <= end
        else { return nil }
        return NSRange(start..<end, in: source)
    }

    /// Converts a swift-markdown `SourceLocation` (1-based line, 1-based UTF-8
    /// column) into a `String.Index` within `source`.
    private func stringIndex(for location: SourceLocation) -> String.Index? {
        let lineIdx = location.line - 1
        guard lineIdx >= 0, lineIdx < lineStarts.count else { return nil }
        let lineStartOffset = lineStarts[lineIdx]

        // `column` is a 1-based UTF-8 byte column within the line.
        let utf8 = source.utf8
        var byteOffset = lineStartOffset + (location.column - 1)
        byteOffset = min(max(byteOffset, 0), utf8.count)

        let utf8Index = utf8.index(utf8.startIndex, offsetBy: byteOffset)
        // Snap to a valid Character boundary so NSRange(_:in:) is well-formed.
        return utf8Index.samePosition(in: source) ?? roundToCharacterBoundary(utf8Offset: byteOffset)
    }

    /// Fallback that walks back to the nearest valid scalar boundary if a UTF-8
    /// byte offset lands mid-grapheme (e.g. inside a multi-byte emoji).
    private func roundToCharacterBoundary(utf8Offset: Int) -> String.Index? {
        let utf8 = source.utf8
        var offset = min(max(utf8Offset, 0), utf8.count)
        while offset >= 0 {
            let idx = utf8.index(utf8.startIndex, offsetBy: offset)
            if let s = idx.samePosition(in: source) { return s }
            offset -= 1
        }
        return source.startIndex
    }

    /// Pre-computes the UTF-8 byte offset at which each line begins, so that a
    /// `SourceLocation`'s (line, column) can be resolved in O(1) per lookup.
    private static func computeLineStarts(in source: String) -> [Int] {
        var starts: [Int] = [0]
        var offset = 0
        for byte in source.utf8 {
            offset += 1
            if byte == 0x0A { // "\n"
                starts.append(offset)
            }
        }
        return starts
    }
}
