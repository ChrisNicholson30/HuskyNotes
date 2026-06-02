import Foundation

/// YAML frontmatter for an exported note.
///
/// Husky Notes writes a small, stable YAML block at the top of every exported
/// `.md` file so that exports round-trip losslessly and can be re-imported and
/// matched back to their originals by ``id``.
///
/// The schema (per `DESIGN.md`) is intentionally minimal:
///
/// ```yaml
/// ---
/// id: 5E1B...UUID
/// created: 2026-06-02T10:15:00Z
/// modified: 2026-06-02T11:42:00Z
/// tags: [work, ideas]
/// pinned: true
/// ---
/// ```
///
/// Dates are ISO8601 (UTC). The note **body** is never stored here — it follows
/// the closing `---` verbatim so that content is preserved byte-for-byte.
struct Frontmatter: Equatable, Sendable {
    /// The note's stable identifier, used to match on re-import.
    var id: UUID
    /// Creation timestamp.
    var created: Date
    /// Last-modified timestamp.
    var modified: Date
    /// Tag names (without leading `#`), in stable sorted order.
    var tags: [String]
    /// Whether the note is pinned.
    var pinned: Bool

    /// The fence delimiter used to open and close a frontmatter block.
    static let fence = "---"

    /// A shared ISO8601 formatter (UTC, no fractional seconds) for timestamps.
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

// MARK: - Encoding

extension Frontmatter {
    /// Builds a ``Frontmatter`` value from a ``Note``, reading the tag names
    /// from the note's denormalised ``Note/tags`` relationship.
    init(note: Note) {
        self.id = note.id
        self.created = note.createdAt
        self.modified = note.modifiedAt
        self.tags = (note.tags ?? [])
            .map(\.name)
            .filter { !$0.isEmpty }
            .sorted()
        self.pinned = note.isPinned
    }

    /// The rendered YAML frontmatter block, **including** the opening and
    /// closing `---` fences but **without** a trailing newline.
    var yaml: String {
        var lines: [String] = [Self.fence]
        lines.append("id: \(id.uuidString)")
        lines.append("created: \(Self.iso8601.string(from: created))")
        lines.append("modified: \(Self.iso8601.string(from: modified))")
        lines.append("tags: \(Self.encodeTagList(tags))")
        lines.append("pinned: \(pinned ? "true" : "false")")
        lines.append(Self.fence)
        return lines.joined(separator: "\n")
    }

    /// Encodes a list of tags as a YAML flow sequence, quoting any entries that
    /// contain characters which would otherwise need escaping.
    private static func encodeTagList(_ tags: [String]) -> String {
        let items = tags.map(quoteIfNeeded)
        return "[\(items.joined(separator: ", "))]"
    }

    /// Wraps a scalar in double quotes (escaping `\` and `"`) only when it
    /// contains YAML-significant characters; plain identifiers are left bare.
    private static func quoteIfNeeded(_ value: String) -> String {
        let needsQuote = value.isEmpty || value.contains(where: { c in
            ",[]{}:#&*!|>'\"%@`".contains(c) || c == " "
        })
        guard needsQuote else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// Builds the YAML frontmatter string for a given note.
///
/// Convenience free function matching the module contract; equivalent to
/// `Frontmatter(note:).yaml`.
func frontmatter(for note: Note) -> String {
    Frontmatter(note: note).yaml
}

// MARK: - Decoding (round-trip import)

extension Frontmatter {
    /// The result of splitting a document into its frontmatter and body.
    struct ParsedDocument: Equatable, Sendable {
        /// The parsed frontmatter, or `nil` if the document had no valid block.
        var frontmatter: Frontmatter?
        /// The Markdown body following the frontmatter block, preserved verbatim.
        var body: String
    }

    /// Parses a full `.md` document into its frontmatter (if any) and body.
    ///
    /// A frontmatter block must begin on the very first line with `---` and end
    /// at the next line that is exactly `---`. The body is everything after the
    /// closing fence, with a single leading blank-line separator removed so that
    /// `frontmatter + "\n\n" + body` round-trips back to the same body.
    ///
    /// If no valid frontmatter block is present the whole document is treated as
    /// the body and ``ParsedDocument/frontmatter`` is `nil`.
    static func parseDocument(_ text: String) -> ParsedDocument {
        // Split preserving empty lines; normalise CRLF to LF for matching.
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalised.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        guard lines.first == fence else {
            return ParsedDocument(frontmatter: nil, body: text)
        }

        // Find the closing fence (first `---` after line 0).
        guard let closeIndex = lines.dropFirst().firstIndex(of: fence) else {
            return ParsedDocument(frontmatter: nil, body: text)
        }

        let yamlLines = Array(lines[1..<closeIndex])
        let parsed = parseFields(from: yamlLines)

        // Body is everything after the closing fence. Drop a single leading
        // blank line so we reverse the "\n\n" separator added on export.
        var bodyLines = Array(lines[(closeIndex + 1)...])
        if bodyLines.first == "" {
            bodyLines.removeFirst()
        }
        let body = bodyLines.joined(separator: "\n")

        return ParsedDocument(frontmatter: parsed, body: body)
    }

    /// Parses the frontmatter fields from the YAML lines between the fences.
    ///
    /// Returns `nil` when no recognisable `id` is present, since identity is the
    /// minimum required to match a re-imported note back to its original.
    private static func parseFields(from yamlLines: [String]) -> Frontmatter? {
        var idValue: UUID?
        var created = Date()
        var modified = Date()
        var tags: [String] = []
        var pinned = false

        for line in yamlLines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let raw = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)

            switch key {
            case "id":
                idValue = UUID(uuidString: unquote(raw))
            case "created":
                if let d = iso8601.date(from: unquote(raw)) { created = d }
            case "modified":
                if let d = iso8601.date(from: unquote(raw)) { modified = d }
            case "tags":
                tags = parseTagList(raw)
            case "pinned":
                pinned = (unquote(raw).lowercased() == "true")
            default:
                break
            }
        }

        guard let id = idValue else { return nil }
        return Frontmatter(id: id, created: created, modified: modified, tags: tags, pinned: pinned)
    }

    /// Parses a YAML flow sequence (`[a, "b c"]`) into individual tag strings.
    private static func parseTagList(_ raw: String) -> [String] {
        var inner = raw
        if inner.hasPrefix("[") && inner.hasSuffix("]") {
            inner = String(inner.dropFirst().dropLast())
        }
        guard !inner.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return inner
            .split(separator: ",")
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    /// Strips surrounding double quotes and unescapes `\"` / `\\` if present.
    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else {
            return value
        }
        let inner = String(value.dropFirst().dropLast())
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
