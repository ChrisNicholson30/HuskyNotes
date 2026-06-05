//
//  SyntaxHighlighter.swift
//  HuskyNotes
//
//  A small, dependency-free syntax highlighter for fenced code blocks. Given a
//  code string and its language (from the ``` info string), it returns coloured
//  token spans — keywords, types, strings, comments, numbers, HTML tags, CSS
//  properties — which the editor styler and Read-mode renderer paint using the
//  active `Theme`'s palette (no new theme keys; colours are derived from the
//  existing accent / heading / quote / secondary roles).
//
//  Tokenising is regex-based and deliberately approximate: it's presentation
//  only and never touches the canonical Markdown source.
//

import Foundation

/// Tokenises code by language into themed colour spans.
enum SyntaxHighlighter {

    /// A coloured region of code.
    struct Span {
        let range: NSRange
        let kind: TokenKind
    }

    /// The kinds of token we colour. Mapped to theme roles in ``color(for:in:)``.
    enum TokenKind {
        case keyword, type, string, number, comment, tag, attribute
    }

    // MARK: Public API

    /// The colour for a token kind, drawn from the theme's dedicated syntax
    /// palette (its own, or the built-in dark/light default) — a distinct,
    /// multi-hue code scheme rather than the surrounding UI colours.
    static func color(for kind: TokenKind, in theme: Theme) -> HexColor {
        let palette = theme.resolvedSyntax
        switch kind {
        case .keyword:   return palette.keyword
        case .type:      return palette.type
        case .string:    return palette.string
        case .number:    return palette.number
        case .comment:   return palette.comment
        case .tag:       return palette.tag
        case .attribute: return palette.attribute
        }
    }

    /// Colour spans for `code` in the given `language` (case-insensitive; `nil`
    /// or unknown languages get comment/string/number highlighting only).
    static func spans(for code: String, language: String?) -> [Span] {
        switch family(for: language) {
        case .clike(let keywords): return cLikeSpans(code, keywords: keywords)
        case .python:              return pythonSpans(code)
        case .html:                return htmlSpans(code)
        case .css:                 return cssSpans(code)
        case .plain:               return cLikeSpans(code, keywords: [])
        }
    }

    // MARK: Language families

    private enum Family {
        case clike(Set<String>)
        case python
        case html
        case css
        case plain
    }

    private static func family(for language: String?) -> Family {
        switch (language ?? "").lowercased() {
        case "swift": return .clike(swiftKeywords)
        case "java", "kotlin", "kt": return .clike(javaKeywords)
        case "javascript", "js", "jsx", "typescript", "ts", "tsx": return .clike(jsKeywords)
        case "c", "cpp", "c++", "objc", "objective-c", "cs", "csharp", "c#",
             "go", "golang", "rust", "rs", "scala", "dart", "php":
            return .clike(cFamilyKeywords)
        case "python", "py": return .python
        case "html", "xml", "svg", "xhtml": return .html
        case "css", "scss", "less": return .css
        case "json": return .clike([])
        default: return .plain
        }
    }

    // MARK: Tokenisers

    /// A collector that adds regex matches as spans, skipping anything that
    /// overlaps an already-claimed region (so keywords inside strings/comments
    /// aren't recoloured).
    private struct Collector {
        let code: String
        let full: NSRange
        var spans: [Span] = []
        private var claimed: [NSRange] = []

        init(_ code: String) {
            self.code = code
            self.full = NSRange(location: 0, length: (code as NSString).length)
        }

        mutating func add(_ pattern: String, _ kind: TokenKind,
                          options: NSRegularExpression.Options = [], group: Int = 0) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in re.matches(in: code, range: full) {
                let range = match.range(at: group)
                guard range.location != NSNotFound, range.length > 0 else { continue }
                if claimed.contains(where: { NSIntersectionRange($0, range).length > 0 }) { continue }
                spans.append(Span(range: range, kind: kind))
                claimed.append(range)
            }
        }
    }

    private static func cLikeSpans(_ code: String, keywords: Set<String>) -> [Span] {
        var c = Collector(code)
        // Comments and strings first so they win over keywords/numbers inside them.
        c.add(#"/\*[\s\S]*?\*/"#, .comment)
        c.add(#"//[^\n]*"#, .comment)
        c.add(#""(?:\\.|[^"\\\n])*""#, .string)
        c.add(#"'(?:\\.|[^'\\\n])*'"#, .string)
        c.add(#"`(?:\\.|[^`\\])*`"#, .string)
        c.add(#"\b0[xX][0-9A-Fa-f]+\b"#, .number)
        c.add(#"\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .number)
        if let pattern = keywordPattern(keywords) { c.add(pattern, .keyword) }
        // Capitalised identifiers read as types (Swift/Java/Kotlin convention).
        c.add(#"\b[A-Z][A-Za-z0-9_]*\b"#, .type)
        return c.spans
    }

    private static func pythonSpans(_ code: String) -> [Span] {
        var c = Collector(code)
        c.add(#"#[^\n]*"#, .comment)
        c.add(#"(?:'''[\s\S]*?'''|\"\"\"[\s\S]*?\"\"\")"#, .string)
        c.add(#""(?:\\.|[^"\\\n])*""#, .string)
        c.add(#"'(?:\\.|[^'\\\n])*'"#, .string)
        c.add(#"\b\d[\d_]*(?:\.\d+)?\b"#, .number)
        if let pattern = keywordPattern(pythonKeywords) { c.add(pattern, .keyword) }
        return c.spans
    }

    private static func htmlSpans(_ code: String) -> [Span] {
        var c = Collector(code)
        c.add(#"<!--[\s\S]*?-->"#, .comment)
        c.add(#""[^"]*"|'[^']*'"#, .string)
        // Opening/closing tag punctuation + name, e.g. "<div", "</span".
        c.add(#"</?[A-Za-z][A-Za-z0-9:-]*"#, .tag)
        // Attribute names just before "=".
        c.add(#"[A-Za-z_:][-A-Za-z0-9_:.]*(?=\s*=)"#, .attribute)
        return c.spans
    }

    private static func cssSpans(_ code: String) -> [Span] {
        var c = Collector(code)
        c.add(#"/\*[\s\S]*?\*/"#, .comment)
        c.add(#""[^"]*"|'[^']*'"#, .string)
        c.add(#"@[A-Za-z-]+"#, .keyword)                       // at-rules
        c.add(#"#[0-9A-Fa-f]{3,8}\b"#, .number)                // hex colours
        c.add(#"[A-Za-z-]+(?=\s*:)"#, .attribute)              // property names
        c.add(#"\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|pt|s|ms|deg|fr)?\b"#, .number)
        return c.spans
    }

    /// Builds a word-boundary alternation for a keyword set, or `nil` if empty.
    private static func keywordPattern(_ keywords: Set<String>) -> String? {
        guard !keywords.isEmpty else { return nil }
        let escaped = keywords.map { NSRegularExpression.escapedPattern(for: $0) }
        return #"\b(?:"# + escaped.joined(separator: "|") + #")\b"#
    }

    // MARK: Keyword sets

    private static let swiftKeywords: Set<String> = [
        "associatedtype", "async", "await", "as", "any", "break", "case", "catch", "class",
        "continue", "convenience", "default", "defer", "deinit", "didSet", "do", "else", "enum",
        "extension", "fallthrough", "false", "fileprivate", "final", "for", "func", "get", "guard",
        "if", "import", "in", "indirect", "init", "inout", "internal", "is", "lazy", "let",
        "mutating", "nil", "nonmutating", "open", "operator", "override", "private", "protocol",
        "public", "repeat", "required", "rethrows", "return", "self", "set", "some", "static",
        "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias",
        "unowned", "var", "weak", "where", "while", "willSet"
    ]

    private static let javaKeywords: Set<String> = [
        "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class",
        "const", "continue", "default", "do", "double", "else", "enum", "extends", "final",
        "finally", "float", "for", "goto", "if", "implements", "import", "instanceof", "int",
        "interface", "long", "native", "new", "package", "private", "protected", "public",
        "return", "sealed", "short", "static", "strictfp", "super", "switch", "synchronized",
        "this", "throw", "throws", "transient", "try", "val", "var", "void", "volatile", "while",
        "true", "false", "null", "record", "yield", "fun", "object", "when"
    ]

    private static let jsKeywords: Set<String> = [
        "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
        "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for",
        "from", "function", "get", "if", "implements", "import", "in", "instanceof", "interface",
        "let", "namespace", "new", "null", "of", "private", "protected", "public", "return", "set",
        "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined",
        "var", "void", "while", "yield"
    ]

    private static let cFamilyKeywords: Set<String> = [
        "auto", "break", "case", "catch", "char", "class", "const", "continue", "default", "delete",
        "do", "double", "else", "enum", "extern", "false", "final", "float", "for", "func", "go",
        "goto", "if", "import", "int", "interface", "let", "long", "map", "namespace", "new", "nil",
        "package", "private", "protected", "public", "return", "short", "signed", "sizeof", "static",
        "struct", "switch", "template", "this", "throw", "true", "try", "type", "typedef", "union",
        "unsigned", "using", "var", "void", "volatile", "while"
    ]

    private static let pythonKeywords: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
        "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import",
        "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return", "True",
        "try", "while", "with", "yield"
    ]
}
