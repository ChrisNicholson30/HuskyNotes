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
    /// - Returns: An `NSAttributedString` whose visible string equals `markdown`.
    func attributedString(for markdown: String, theme: Theme) -> NSAttributedString {
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
        //    visible characters untouched (live source styling).
        let document = Document(parsing: markdown, options: [.parseBlockDirectives])
        var visitor = StylingVisitor(
            source: markdown,
            target: result,
            theme: theme,
            fonts: fonts
        )
        visitor.visit(document)

        return result
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

    /// UTF-8/Unicode offset cache mapping `SourceLocation` → `String.Index`.
    private let lineStarts: [Int]

    init(source: String, target: NSMutableAttributedString, theme: Theme, fonts: FontSet) {
        self.source = source
        self.target = target
        self.theme = theme
        self.fonts = fonts
        self.lineStarts = StylingVisitor.computeLineStarts(in: source)
    }

    // MARK: Block elements

    mutating func visitHeading(_ heading: Heading) {
        if let range = nsRange(for: heading) {
            applyFontPreservingTraits(fonts.heading(level: heading.level), over: range)
            target.addAttribute(.foregroundColor, value: theme.heading.platformColor, range: range)
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
        }
        descendInto(blockQuote)
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
        }
    }

    mutating func visitStrong(_ strong: Strong) {
        if let range = nsRange(for: strong) {
            mergeTrait(.bold, over: range)
        }
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        if let range = nsRange(for: emphasis) {
            mergeTrait(.italic, over: range)
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
