import Foundation

// MARK: - ImportIssue
// A single problem found while parsing or validating an import file. Errors block
// the import; warnings are surfaced but don't stop it.

struct ImportIssue: Identifiable, Hashable {
    enum Severity {
        case error
        case warning
    }

    let id = UUID()
    var severity: Severity
    /// Human-facing section label, e.g. "workout" or "program", or "file" for
    /// structural problems that aren't tied to a section.
    var section: String
    /// 1-based source line number, when known.
    var line: Int?
    var message: String

    static func error(_ message: String, section: String = "file", line: Int? = nil) -> ImportIssue {
        ImportIssue(severity: .error, section: section, line: line, message: message)
    }

    static func warning(_ message: String, section: String = "file", line: Int? = nil) -> ImportIssue {
        ImportIssue(severity: .warning, section: section, line: line, message: message)
    }

    /// "workout, line 12: …" style location prefix for display.
    var locationLabel: String {
        if let line { return "\(section), line \(line)" }
        return section
    }
}

extension Array where Element == ImportIssue {
    var errors: [ImportIssue] { filter { $0.severity == .error } }
    var warnings: [ImportIssue] { filter { $0.severity == .warning } }
    var hasErrors: Bool { contains { $0.severity == .error } }
}
