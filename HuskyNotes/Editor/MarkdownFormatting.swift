//
//  MarkdownFormatting.swift
//  HuskyNotes
//
//  Pure, platform-agnostic logic that applies a `MarkdownCommand` to a Markdown
//  source string and selection, returning the new string and new selection.
//
//  All range maths is done in UTF-16 (`NSString`/`NSRange`) so it matches the
//  selection semantics of `UITextView`/`NSTextView` exactly. Keeping this free
//  of any UIKit/AppKit type makes it straightforward to unit-test.
//

import Foundation

/// Applies Markdown formatting commands to a source string + selection.
enum MarkdownFormatting {

    /// The result of a formatting operation.
    struct Result: Equatable {
        /// The rewritten Markdown source.
        var text: String
        /// The selection to restore after the edit (UTF-16 / `NSRange`).
        var selection: NSRange
    }

    /// Applies `command` to `text` at `selection`.
    static func apply(_ command: MarkdownCommand, to text: String, selection: NSRange) -> Result {
        let ns = text as NSString
        let sel = clamp(selection, length: ns.length)

        switch command {
        case .bold:          return wrap(ns, sel, marker: "**")
        case .italic:        return wrap(ns, sel, marker: "*")
        case .strikethrough: return wrap(ns, sel, marker: "~~")
        case .highlight:     return wrap(ns, sel, marker: "==")
        case .inlineCode:    return wrap(ns, sel, marker: "`")
        case .underline:     return wrapAsymmetric(ns, sel, open: "<u>", close: "</u>")
        case .codeBlock:     return fenceCodeBlock(ns, sel)
        case .link:          return insertLink(ns, sel)
        case .wikiLink:      return insertPair(ns, sel, open: "[[", close: "]]")
        case .heading(let level): return setHeading(ns, sel, level: level)
        case .bulletList:    return toggleLinePrefix(ns, sel, prefix: "- ")
        case .orderedList:   return toggleLinePrefix(ns, sel, prefix: "1. ")
        case .todo:          return toggleLinePrefix(ns, sel, prefix: "- [ ] ")
        case .quote:         return toggleLinePrefix(ns, sel, prefix: "> ")
        case .lineSeparator: return insertBlock(ns, sel, block: "\n---\n")
        case .currentDate:   return insertText(ns, sel, string: todayString())
        case .table:         return insertTable(ns, sel)
        }
    }

    /// Inserts a starter 2×2 GFM table, placing the caret in the first header
    /// cell. A blank line is added before the table when it doesn't already start
    /// a line, so the table parses as its own block.
    private static func insertTable(_ ns: NSString, _ sel: NSRange) -> Result {
        let atLineStart = sel.location == 0 || ns.character(at: sel.location - 1) == 0x0A
        let lead = atLineStart ? "" : "\n"
        let table = "| Column | Column |\n| --- | --- |\n|  |  |\n"
        let block = lead + table
        let m = NSMutableString(string: ns)
        m.replaceCharacters(in: sel, with: block)
        // Select the first header label ("Column") so the user can type over it.
        let headerStart = sel.location + (lead as NSString).length + 2 // after "| "
        return Result(text: m as String,
                      selection: NSRange(location: headerStart, length: 6))
    }

    // MARK: - Inline wrapping

    /// Toggles a symmetric inline marker (e.g. `**`, `*`, `` ` ``) around the
    /// selection. If the selection is already wrapped, the markers are removed;
    /// otherwise they're added. An empty selection inserts the markers and
    /// places the caret between them.
    private static func wrap(_ ns: NSString, _ sel: NSRange, marker: String) -> Result {
        let mlen = (marker as NSString).length
        let before = sel.location - mlen
        let after = sel.location + sel.length

        // Already wrapped? Unwrap.
        if before >= 0, after + mlen <= ns.length,
           ns.substring(with: NSRange(location: before, length: mlen)) == marker,
           ns.substring(with: NSRange(location: after, length: mlen)) == marker {
            let m = NSMutableString(string: ns)
            m.deleteCharacters(in: NSRange(location: after, length: mlen))
            m.deleteCharacters(in: NSRange(location: before, length: mlen))
            return Result(text: m as String,
                          selection: NSRange(location: sel.location - mlen, length: sel.length))
        }

        // Otherwise wrap.
        let m = NSMutableString(string: ns)
        m.insert(marker, at: after)
        m.insert(marker, at: sel.location)
        return Result(text: m as String,
                      selection: NSRange(location: sel.location + mlen, length: sel.length))
    }

    /// Wraps the selection with distinct opening/closing strings (e.g. `<u>` /
    /// `</u>`); empty selection places the caret between them.
    private static func wrapAsymmetric(_ ns: NSString, _ sel: NSRange, open: String, close: String) -> Result {
        let m = NSMutableString(string: ns)
        m.insert(close, at: sel.location + sel.length)
        m.insert(open, at: sel.location)
        let openLen = (open as NSString).length
        return Result(text: m as String,
                      selection: NSRange(location: sel.location + openLen, length: sel.length))
    }

    /// Inserts a matched pair (e.g. `[[` / `]]`) with the caret/selection inside.
    private static func insertPair(_ ns: NSString, _ sel: NSRange, open: String, close: String) -> Result {
        wrapAsymmetric(ns, sel, open: open, close: close)
    }

    // MARK: - Links

    /// Wraps the selection as `[text](url)` (or inserts an empty link), leaving
    /// the `url` placeholder selected so the user can type the destination.
    private static func insertLink(_ ns: NSString, _ sel: NSRange) -> Result {
        let placeholder = "url"
        let selected = ns.substring(with: sel)
        let replacement = "[\(selected)](\(placeholder))"
        let m = NSMutableString(string: ns)
        m.replaceCharacters(in: sel, with: replacement)
        // Select the "url" placeholder: after "[" + text + "]("
        let urlStart = sel.location + 1 + (selected as NSString).length + 2
        return Result(text: m as String,
                      selection: NSRange(location: urlStart, length: (placeholder as NSString).length))
    }

    // MARK: - Code block

    /// Wraps the selected lines in a fenced code block.
    private static func fenceCodeBlock(_ ns: NSString, _ sel: NSRange) -> Result {
        let line = lineRangeTrimmingTerminator(ns, sel)
        let body = ns.substring(with: line)
        let replacement = "```\n\(body)\n```"
        let m = NSMutableString(string: ns)
        m.replaceCharacters(in: line, with: replacement)
        // Place the caret on the opening fence's content line if empty,
        // otherwise select the wrapped body.
        if body.isEmpty {
            return Result(text: m as String, selection: NSRange(location: line.location + 4, length: 0))
        }
        return Result(text: m as String,
                      selection: NSRange(location: line.location + 4, length: (body as NSString).length))
    }

    // MARK: - Headings

    /// Sets the selected lines to a heading of `level` (1–6); `level == 0`
    /// strips any heading to a plain paragraph. Re-applying the same level
    /// toggles it off.
    private static func setHeading(_ ns: NSString, _ sel: NSRange, level: Int) -> Result {
        transformLines(ns, sel) { line in
            let (stripped, existingLevel) = stripHeading(line)
            if level == 0 || level == existingLevel {
                return stripped
            }
            let hashes = String(repeating: "#", count: max(1, min(level, 6)))
            return "\(hashes) \(stripped)"
        }
    }

    /// Removes a leading ATX heading marker, returning the bare text and the
    /// level that was present (0 if none).
    private static func stripHeading(_ line: String) -> (text: String, level: Int) {
        var idx = line.startIndex
        var hashes = 0
        while idx < line.endIndex, line[idx] == "#", hashes < 6 {
            hashes += 1
            idx = line.index(after: idx)
        }
        guard hashes > 0 else { return (line, 0) }
        // Require a space after the hashes for it to count as a heading.
        guard idx < line.endIndex, line[idx] == " " else { return (line, 0) }
        let rest = line[line.index(after: idx)...]
        return (String(rest), hashes)
    }

    // MARK: - Line prefixes

    /// Toggles a simple per-line prefix (`- `, `> `, `1. `, `- [ ] `) across all
    /// selected lines. If every line already has the prefix it's removed,
    /// otherwise it's added to each.
    private static func toggleLinePrefix(_ ns: NSString, _ sel: NSRange, prefix: String) -> Result {
        let line = lineRangeTrimmingTerminator(ns, sel)
        let block = ns.substring(with: line)
        let lines = block.isEmpty ? [""] : block.components(separatedBy: "\n")
        let allPrefixed = lines.allSatisfy { $0.hasPrefix(prefix) }

        let transformed = lines.map { l -> String in
            if allPrefixed {
                return String(l.dropFirst(prefix.count))
            } else {
                return l.hasPrefix(prefix) ? l : prefix + l
            }
        }
        let newBlock = transformed.joined(separator: "\n")
        let m = NSMutableString(string: ns)
        m.replaceCharacters(in: line, with: newBlock)

        // With a caret (no selection) on a single line, keep a *caret* positioned
        // just past the marker so the user can type immediately — rather than
        // selecting the whole line (which the next keystroke would overwrite,
        // deleting the marker they just asked for).
        if sel.length == 0, lines.count == 1 {
            let prefixLen = (prefix as NSString).length
            let caret = allPrefixed
                ? max(line.location, sel.location - prefixLen) // removed: shift left
                : sel.location + prefixLen                     // added: shift past marker
            return Result(text: m as String, selection: NSRange(location: caret, length: 0))
        }

        // A real (multi-line or non-empty) selection: keep the block selected so
        // re-applying the command toggles it cleanly.
        return Result(text: m as String,
                      selection: NSRange(location: line.location, length: (newBlock as NSString).length))
    }

    // MARK: - List continuation (Return key)

    /// Computes the result of pressing Return inside a list item, so lists
    /// continue automatically:
    ///
    /// - On a list line **with content**, inserts a newline plus the next
    ///   marker (`- `, the next ordered number, or an unchecked `- [ ] `),
    ///   placing the caret ready to type the next item.
    /// - On an **empty** list item (just the marker), ends the list by removing
    ///   the marker and leaving a blank line.
    ///
    /// Returns `nil` when the caret isn't in a list item (or there's a ranged
    /// selection), so the editor performs a normal newline.
    static func handleReturn(text: String, selection: NSRange) -> Result? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let caret = min(max(selection.location, 0), ns.length)

        let lineRange = lineRangeTrimmingTerminator(ns, NSRange(location: caret, length: 0))
        let line = ns.substring(with: lineRange)
        guard let marker = listMarker(of: line) else { return nil }

        let content = String(line.dropFirst(marker.lineMarker.count))
        let m = NSMutableString(string: ns)

        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty item → end the list: clear this line's marker.
            m.replaceCharacters(in: lineRange, with: "")
            return Result(text: m as String,
                          selection: NSRange(location: lineRange.location, length: 0))
        }

        // Non-empty item → continue: newline + the next marker at the caret.
        let insertion = "\n" + marker.continuation
        m.insert(insertion, at: caret)
        let newCaret = caret + (insertion as NSString).length
        return Result(text: m as String, selection: NSRange(location: newCaret, length: 0))
    }

    /// A parsed list marker on one line: the exact prefix present on this line
    /// and the prefix to emit for the *next* item.
    private struct ListMarker {
        /// This line's leading marker, e.g. `"- "`, `"  1. "`, `"- [x] "`.
        let lineMarker: String
        /// The marker to insert for the following item (ordered number bumped,
        /// task boxes reset to unchecked), indentation preserved.
        let continuation: String
    }

    /// Detects a leading list marker on `line` (bullet `-`/`*`/`+`, ordered
    /// `N.`/`N)`, or a `- [ ]`/`- [x]` task), or `nil` if the line isn't a list
    /// item.
    private static func listMarker(of line: String) -> ListMarker? {
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == " " || line[idx] == "\t" {
            idx = line.index(after: idx)
        }
        let indent = String(line[line.startIndex..<idx])
        guard idx < line.endIndex else { return nil }
        let first = line[idx]

        // Ordered: one or more digits, then "." or ")", then a space.
        if first.isNumber {
            var j = idx
            var digits = ""
            while j < line.endIndex, line[j].isNumber {
                digits.append(line[j])
                j = line.index(after: j)
            }
            guard j < line.endIndex, line[j] == "." || line[j] == ")" else { return nil }
            let delim = line[j]
            let afterDelim = line.index(after: j)
            guard afterDelim < line.endIndex, line[afterDelim] == " " else { return nil }
            let lineMarker = indent + digits + String(delim) + " "
            let next = (Int(digits) ?? 0) + 1
            return ListMarker(lineMarker: lineMarker,
                              continuation: indent + "\(next)" + String(delim) + " ")
        }

        // Unordered (and task) bullets: "-", "*", "+", then a space.
        if first == "-" || first == "*" || first == "+" {
            let afterBullet = line.index(after: idx)
            guard afterBullet < line.endIndex, line[afterBullet] == " " else { return nil }

            // Optional task box: "[ ] " / "[x] " / "[X] " right after the bullet.
            let boxStart = line.index(after: afterBullet)
            if let contentStart = taskBoxEnd(line, from: boxStart) {
                let lineMarker = String(line[line.startIndex..<contentStart])
                return ListMarker(lineMarker: lineMarker,
                                  continuation: indent + String(first) + " [ ] ")
            }

            let lineMarker = indent + String(first) + " "
            return ListMarker(lineMarker: lineMarker,
                              continuation: indent + String(first) + " ")
        }

        return nil
    }

    /// If `line` has a `[ ]`/`[x]`/`[X]` task box followed by a space starting at
    /// `start`, returns the index just past the trailing space; otherwise `nil`.
    private static func taskBoxEnd(_ line: String, from start: String.Index) -> String.Index? {
        guard start < line.endIndex, line[start] == "[" else { return nil }
        let mark = line.index(after: start)
        guard mark < line.endIndex, line[mark] == " " || line[mark] == "x" || line[mark] == "X" else { return nil }
        let close = line.index(after: mark)
        guard close < line.endIndex, line[close] == "]" else { return nil }
        let space = line.index(after: close)
        guard space < line.endIndex, line[space] == " " else { return nil }
        return line.index(after: space)
    }

    // MARK: - Insertions

    /// Inserts an attachment reference (image/file Markdown) at the caret on its
    /// own line — a leading newline is added when the caret isn't at the start of
    /// a line, and a trailing newline follows — placing the caret after it.
    static func insertAttachment(_ snippet: String, into text: String, at selection: NSRange) -> Result {
        let ns = text as NSString
        let sel = clamp(selection, length: ns.length)
        let atLineStart = sel.location == 0 || ns.character(at: sel.location - 1) == 0x0A
        let block = (atLineStart ? "" : "\n") + snippet + "\n"
        return insertBlock(ns, sel, block: block)
    }

    /// Inserts a block string (e.g. `\n---\n`) at the selection, replacing it,
    /// and places the caret after the inserted text.
    private static func insertBlock(_ ns: NSString, _ sel: NSRange, block: String) -> Result {
        let m = NSMutableString(string: ns)
        m.replaceCharacters(in: sel, with: block)
        return Result(text: m as String,
                      selection: NSRange(location: sel.location + (block as NSString).length, length: 0))
    }

    /// Inserts plain text at the selection and places the caret after it.
    private static func insertText(_ ns: NSString, _ sel: NSRange, string: String) -> Result {
        insertBlock(ns, sel, block: string)
    }

    // MARK: - Helpers

    /// Applies `transform` to each selected line, replacing the affected block
    /// and selecting the result.
    private static func transformLines(_ ns: NSString, _ sel: NSRange, _ transform: (String) -> String) -> Result {
        let line = lineRangeTrimmingTerminator(ns, sel)
        let block = ns.substring(with: line)
        let lines = block.isEmpty ? [""] : block.components(separatedBy: "\n")
        let newBlock = lines.map(transform).joined(separator: "\n")
        let m = NSMutableString(string: ns)
        m.replaceCharacters(in: line, with: newBlock)
        return Result(text: m as String,
                      selection: NSRange(location: line.location, length: (newBlock as NSString).length))
    }

    /// The range of the line(s) intersecting `sel`, excluding the trailing line
    /// terminator so prefixes operate on content, not the newline.
    private static func lineRangeTrimmingTerminator(_ ns: NSString, _ sel: NSRange) -> NSRange {
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        var range = ns.lineRange(for: sel)
        if range.length > 0, ns.character(at: range.location + range.length - 1) == 0x0A {
            range.length -= 1
        }
        return range
    }

    /// Clamps a selection to valid bounds for a string of the given length.
    private static func clamp(_ range: NSRange, length: Int) -> NSRange {
        let loc = min(max(range.location, 0), length)
        let len = min(max(range.length, 0), length - loc)
        return NSRange(location: loc, length: len)
    }

    /// Today's date as `yyyy-MM-dd`.
    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
