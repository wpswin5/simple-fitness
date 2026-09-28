import Foundation

// MARK: - Parsed cardio template

struct ParsedCardioTemplate {
    var name: String
    var cardioType: CardioType
    var structureType: CardioWorkoutType
    var targetDistance: Double?
    var targetDurationSeconds: Int
    var distanceUnit: DistanceUnit
    var notes: String
    var segments: [ParsedCardioSegment]
}

struct ParsedCardioSegment {
    var order: Int
    var label: String
    var intensity: CardioIntensity
    var isRest: Bool
    var durationSeconds: Int?
    var distanceValue: Double?
    var paceSecondsPerUnit: Int?
    var inclinePercent: Double?
}

// MARK: - CardioCSV
// Encodes/decodes a saved cardio template (`isTemplate = true`) to/from a
// `#! cardio v1` section — one row per segment. Metadata carries the template
// name, activity type, structure, and optional overall targets.

enum CardioCSV {

    /// One `#! cardio v1` section = one template.
    static func decode(_ section: CSVSection, distanceUnit: DistanceUnit) -> (template: ParsedCardioTemplate?, issues: [ImportIssue]) {
        var issues: [ImportIssue] = []

        let name = section.metadata["name"] ?? "Imported Cardio"
        let cardioType = section.metadata["type"].flatMap { CardioType.loose($0) } ?? .running
        var structure = section.metadata["structure"].flatMap { CardioWorkoutType.loose($0) } ?? .steady
        let notes = section.metadata["notes"] ?? ""
        let targetDistance = section.metadata["distance"].flatMap { Double($0) }
        let targetDuration = section.metadata["duration"].flatMap { parseClock($0) } ?? 0

        // Segment columns (all optional; a steady template can have zero rows).
        let orderCol = section.columnIndex("segment")
        let labelCol = section.columnIndex("label")
        let intensityCol = section.columnIndex("intensity")
        let durationCol = section.columnIndex("duration")
        let distanceCol = section.columnIndex("distance")
        let paceCol = section.columnIndex("pace")
        let inclineCol = section.columnIndex("incline")

        var segments: [ParsedCardioSegment] = []
        for (idx, row) in section.rows.enumerated() {
            func field(_ col: Int?) -> String {
                guard let col, col < row.fields.count else { return "" }
                return row.fields[col].trimmingCharacters(in: .whitespaces)
            }
            let intensityRaw = field(intensityCol)
            var intensity: CardioIntensity = .moderate
            if !intensityRaw.isEmpty {
                if let i = CardioIntensity.loose(intensityRaw) { intensity = i }
                else { issues.append(.warning("Unknown intensity '\(intensityRaw)' → Moderate", section: "cardio", line: row.line)) }
            }
            let isRest = intensity == .rest
            let order = Int(field(orderCol)) ?? (idx + 1)
            segments.append(ParsedCardioSegment(
                order: order,
                label: field(labelCol),
                intensity: intensity,
                isRest: isRest,
                durationSeconds: parseClock(field(durationCol)),
                distanceValue: Double(field(distanceCol)),
                paceSecondsPerUnit: parseClock(field(paceCol)),
                inclinePercent: Double(field(inclineCol))
            ))
        }
        segments.sort { $0.order < $1.order }

        // A structured type needs segments; if none were given, fall back to steady.
        if structure.isSegmented && segments.isEmpty {
            issues.append(.warning("Cardio '\(name)' is \(structure.displayName) but has no segments → treated as Steady", section: "cardio", line: section.directiveLine))
            structure = .steady
        }

        let template = ParsedCardioTemplate(
            name: name,
            cardioType: cardioType,
            structureType: structure,
            targetDistance: targetDistance,
            targetDurationSeconds: targetDuration,
            distanceUnit: distanceUnit,
            notes: notes,
            segments: segments
        )
        return (template, issues)
    }

    // MARK: - Encode (used by the template example)

    static func encode(_ template: CardioTemplate) -> String {
        var lines = ["#! cardio v1"]
        lines.append("#: name = \(template.name)")
        lines.append("#: type = \(template.cardioType.rawValue)")
        lines.append("#: structure = \(template.structureType.rawValue)")
        if let d = template.targetDistance, d > 0 { lines.append("#: distance = \(d.weightFormatted)") }
        if template.targetDurationSeconds > 0 { lines.append("#: duration = \(clock(template.targetDurationSeconds))") }
        if !template.notes.isEmpty { lines.append("#: notes = \(template.notes)") }
        lines.append(CSVParser.encodeRow(["segment", "label", "intensity", "duration", "distance", "pace", "incline"]))
        for (i, iv) in template.sortedIntervals.enumerated() {
            lines.append(CSVParser.encodeRow([
                String(i + 1),
                iv.label,
                (iv.isRest ? CardioIntensity.rest : iv.intensity).rawValue,
                iv.durationSeconds.map { clock($0) } ?? "",
                iv.distanceValue.map { $0.weightFormatted } ?? "",
                iv.paceSecondsPerUnit.map { clock($0) } ?? "",
                iv.inclinePercent.map { $0.weightFormatted } ?? "",
            ]))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Clock helpers ("MM:SS" or "HH:MM:SS" ↔ seconds)

    static func parseClock(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains(":") { return Int(trimmed) }   // bare seconds
        let parts = trimmed.split(separator: ":").map { Int($0) ?? 0 }
        let total: Int
        switch parts.count {
        case 2: total = parts[0] * 60 + parts[1]
        case 3: total = parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
        return total > 0 ? total : nil
    }

    private static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Loose enum matching

extension CardioType {
    static func loose(_ s: String) -> CardioType? {
        let key = s.lowercased().replacingOccurrences(of: " ", with: "")
        switch key {
        case "run", "running": return .running
        case "bike", "biking", "cycle", "cycling": return .biking
        case "swim", "swimming": return .swimming
        default: return allCases.first { $0.rawValue.lowercased() == key }
        }
    }
}

extension CardioWorkoutType {
    static func loose(_ s: String) -> CardioWorkoutType? {
        let key = s.lowercased().replacingOccurrences(of: " ", with: "")
        return allCases.first {
            $0.rawValue.lowercased() == key ||
            $0.displayName.lowercased().replacingOccurrences(of: " ", with: "") == key
        }
    }
}

extension CardioIntensity {
    static func loose(_ s: String) -> CardioIntensity? {
        let key = s.lowercased().replacingOccurrences(of: " ", with: "")
        return allCases.first { $0.rawValue.lowercased() == key || $0.displayName.lowercased() == key }
    }
}
