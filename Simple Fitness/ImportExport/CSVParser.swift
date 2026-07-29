import Foundation

// MARK: - Parsed model

/// One row of CSV data with its source line, for error reporting.
struct CSVRow {
    var fields: [String]
    var line: Int
}

/// A typed section of the import file, introduced by a `#! <type> v<version>` directive.
struct CSVSection {
    var type: String                 // lowercased, e.g. "workout", "program"
    var version: Int
    var metadata: [String: String]   // lowercased keys, from `#: key = value`
    var header: [String]             // lowercased column names
    var rows: [CSVRow]
    var directiveLine: Int

    /// Index of a column by (lowercased) name.
    func columnIndex(_ name: String) -> Int? {
        header.firstIndex(of: name)
    }
}

struct CSVDocument {
    var sections: [CSVSection]
}

// MARK: - CSVParser
// Line-oriented for directives/metadata/comments, with RFC-4180 field parsing for
// data rows (quoted fields may contain commas, escaped quotes `""`, and newlines).
// Pure and app-type-free so it can be unit-tested in isolation.

enum CSVParser {

    static func parse(_ text: String) -> (document: CSVDocument, issues: [ImportIssue]) {
        var issues: [ImportIssue] = []
        var sections: [CSVSection] = []

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
                             .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var current: CSVSection?
        var headerCaptured = false
        var pending: String? = nil          // accumulates a record split across lines by a quoted newline
        var pendingStartLine = 0

        func flushSection() {
            if let section = current { sections.append(section) }
            current = nil
            headerCaptured = false
        }

        func consumeRecord(_ record: String, line: Int) {
            guard current != nil else {
                issues.append(.warning("Ignored data outside any section (expected a `#! …` directive first)", line: line))
                return
            }
            let fields = parseFields(record)
            if headerCaptured {
                current?.rows.append(CSVRow(fields: fields, line: line))
            } else {
                current?.header = fields.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                headerCaptured = true
            }
        }

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1

            // Continuation of a record with an unterminated quoted field.
            if var buffer = pending {
                buffer += "\n" + rawLine
                if quotesBalanced(buffer) {
                    consumeRecord(buffer, line: pendingStartLine)
                    pending = nil
                } else {
                    pending = buffer
                }
                continue
            }

            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("#!") {
                flushSection()
                if let section = parseDirective(trimmed, line: lineNumber, issues: &issues) {
                    current = section
                }
                continue
            }
            if trimmed.hasPrefix("#:") {
                parseMetadata(trimmed, line: lineNumber, into: &current, issues: &issues)
                continue
            }
            if trimmed.hasPrefix("#") {
                continue    // comment
            }

            // Data line — may open a multi-line quoted field.
            if quotesBalanced(rawLine) {
                consumeRecord(rawLine, line: lineNumber)
            } else {
                pending = rawLine
                pendingStartLine = lineNumber
            }
        }

        if let leftover = pending {
            issues.append(.error("Unterminated quoted field", line: pendingStartLine))
            consumeRecord(leftover, line: pendingStartLine)
        }
        flushSection()

        return (CSVDocument(sections: sections), issues)
    }

    // MARK: - Directive / metadata

    private static func parseDirective(_ line: String, line lineNumber: Int, issues: inout [ImportIssue]) -> CSVSection? {
        let body = line.dropFirst(2).trimmingCharacters(in: .whitespaces)   // after "#!"
        let tokens = body.split(separator: " ").map(String.init)
        guard let type = tokens.first?.lowercased(), !type.isEmpty else {
            issues.append(.error("Malformed section directive '\(line)'", line: lineNumber))
            return nil
        }
        var version = 1
        if tokens.count > 1 {
            let raw = tokens[1].lowercased().replacingOccurrences(of: "v", with: "")
            if let parsed = Int(raw) { version = parsed }
        }
        return CSVSection(type: type, version: version, metadata: [:], header: [], rows: [], directiveLine: lineNumber)
    }

    private static func parseMetadata(_ line: String, line lineNumber: Int, into current: inout CSVSection?, issues: inout [ImportIssue]) {
        let body = line.dropFirst(2).trimmingCharacters(in: .whitespaces)   // after "#:"
        guard let eq = body.firstIndex(of: "=") else {
            issues.append(.warning("Ignored metadata without '=' : '\(line)'", line: lineNumber))
            return
        }
        let key = body[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
        let value = body[body.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        guard current != nil else {
            issues.append(.warning("Ignored metadata before any section: '\(line)'", line: lineNumber))
            return
        }
        current?.metadata[key] = value
    }

    // MARK: - Field parsing (RFC-4180)

    /// True when the string has an even number of double-quote characters, i.e.
    /// no quoted field is left open (handles `""` escapes, which are even).
    private static func quotesBalanced(_ s: String) -> Bool {
        s.reduce(0) { $1 == "\"" ? $0 + 1 : $0 } % 2 == 0
    }

    /// Splits one record into fields, honoring quotes, `""` escapes, and quoted commas/newlines.
    static func parseFields(_ record: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(record)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")   // escaped quote
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",":  fields.append(field); field = ""
                default:   field.append(c)
                }
            }
            i += 1
        }
        fields.append(field)
        return fields
    }

    // MARK: - Field encoding (for export)

    /// Quotes a field if it contains a comma, quote, or newline; escapes quotes.
    static func encodeField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    /// Joins already-encoded fields into a CSV line.
    static func encodeRow(_ fields: [String]) -> String {
        fields.map(encodeField).joined(separator: ",")
    }
}
