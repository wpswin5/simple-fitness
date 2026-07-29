import Foundation
import SwiftData

// MARK: - ParsedProgram
// Decoded program in draft form, ready to hand to CreateProgramViewModel(prefilled:).

struct ParsedProgram {
    var name: String
    var description: String
    var goal: TrainingGoal
    var difficulty: DifficultyLevel
    var weeks: [DraftProgramWeek]
}

// MARK: - ProgramCSV
// Encodes/decodes a multi-week program to/from a `#! program v1` section (one row
// per scheduled activity). Activities reference workouts and cardio templates by
// name, resolved against what already exists plus what was imported earlier in the
// same file.

@MainActor
enum ProgramCSV {

    /// - Parameters:
    ///   - workoutLookup: normalized-name → Workout (existing + just-imported).
    ///   - cardioLookup: normalized-name → saved CardioTemplate.
    static func decode(
        _ section: CSVSection,
        workoutLookup: [String: Workout],
        cardioLookup: [String: CardioTemplate]
    ) -> (program: ParsedProgram?, issues: [ImportIssue]) {
        var issues: [ImportIssue] = []

        guard let weekCol = section.columnIndex("week"),
              let dayCol = section.columnIndex("day"),
              let typeCol = section.columnIndex("type"),
              let nameCol = section.columnIndex("name") else {
            issues.append(.error("Program section is missing a required column (needs week, day, type, name)", section: "program", line: section.directiveLine))
            return (nil, issues)
        }

        let name = section.metadata["name"] ?? "Imported Program"
        let description = section.metadata["description"] ?? ""
        var goal: TrainingGoal = .strengthGain
        if let raw = section.metadata["goal"] {
            if let g = TrainingGoal.loose(raw) { goal = g }
            else { issues.append(.warning("Unknown goal '\(raw)' → Strength", section: "program", line: section.directiveLine)) }
        }
        var difficulty: DifficultyLevel = .intermediate
        if let raw = section.metadata["difficulty"] {
            if let d = DifficultyLevel.loose(raw) { difficulty = d }
            else { issues.append(.warning("Unknown difficulty '\(raw)' → Intermediate", section: "program", line: section.directiveLine)) }
        }

        // week → day → activities
        var schedule: [Int: [DayOfWeek: [DraftProgramActivity]]] = [:]
        var maxWeek = 0

        for row in section.rows {
            func field(_ col: Int) -> String {
                guard col < row.fields.count else { return "" }
                return row.fields[col].trimmingCharacters(in: .whitespaces)
            }

            guard let week = Int(field(weekCol)), week >= 1 else {
                issues.append(.error("Invalid week '\(field(weekCol))'", section: "program", line: row.line)); continue
            }
            guard let day = DayOfWeek.loose(field(dayCol)) else {
                issues.append(.error("Invalid day '\(field(dayCol))'", section: "program", line: row.line)); continue
            }
            let type = field(typeCol).lowercased()
            let refName = field(nameCol)
            guard !refName.isEmpty else {
                issues.append(.error("Activity row has no name", section: "program", line: row.line)); continue
            }
            let key = ExerciseResolver.normalize(refName)

            var activity: DraftProgramActivity?
            switch type {
            case "workout", "strength", "lift":
                if let workout = workoutLookup[key] {
                    activity = DraftProgramActivity(workout: workout)
                } else {
                    issues.append(.error("Unknown workout '\(refName)' (import it or define it in a workout section above)", section: "program", line: row.line))
                }
            case "cardio", "run", "bike", "swim":
                if let template = cardioLookup[key] {
                    activity = DraftProgramActivity(cardioTemplate: draftCardio(from: template))
                } else {
                    issues.append(.warning("Unknown cardio template '\(refName)' → skipped (create it in the Cardio tab first)", section: "program", line: row.line))
                }
            default:
                issues.append(.error("Invalid type '\(type)' (use 'workout' or 'cardio')", section: "program", line: row.line))
            }

            guard let activity else { continue }
            maxWeek = max(maxWeek, week)
            schedule[week, default: [:]][day, default: []].append(activity)
        }

        guard maxWeek > 0 else {
            issues.append(.error("Program '\(name)' has no valid scheduled activities", section: "program"))
            return (nil, issues)
        }

        // Build contiguous weeks 1...maxWeek, filling gaps with all-rest weeks.
        let weeks: [DraftProgramWeek] = (1...maxWeek).map { weekNo in
            var week = DraftProgramWeek(weekNumber: weekNo)
            let dayMap = schedule[weekNo] ?? [:]
            for i in week.days.indices {
                if let acts = dayMap[week.days[i].dayOfWeek] {
                    week.days[i].activities = acts.enumerated().map { idx, a in
                        var updated = a; updated.order = idx; return updated
                    }
                }
            }
            return week
        }

        return (ParsedProgram(name: name, description: description, goal: goal, difficulty: difficulty, weeks: weeks), issues)
    }

    // MARK: - Encode (used by the template; program export UI is a later add)

    static func encode(_ program: Program) -> String {
        var lines: [String] = ["#! program v1"]
        lines.append("#: name = \(program.name)")
        if !program.programDescription.isEmpty {
            lines.append("#: description = \(program.programDescription)")
        }
        lines.append("#: goal = \(program.targetGoal.rawValue)")
        lines.append("#: difficulty = \(program.difficultyLevel.rawValue)")
        lines.append(CSVParser.encodeRow(["week", "day", "type", "name"]))

        for week in program.sortedWeeks {
            for day in week.days.sorted(by: { $0.dayOfWeek.sortOrder < $1.dayOfWeek.sortOrder }) {
                for activity in day.sortedActivities {
                    if let workout = activity.workout {
                        lines.append(CSVParser.encodeRow([String(week.weekNumber), day.dayOfWeek.rawValue, "workout", workout.name]))
                    } else if let cardio = activity.cardioTemplate {
                        let label = cardio.name.isEmpty ? cardio.displayName : cardio.name
                        lines.append(CSVParser.encodeRow([String(week.weekNumber), day.dayOfWeek.rawValue, "cardio", label]))
                    }
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Cardio template → draft (mirrors CreateProgramView.draftFromTemplate)

    private static func draftCardio(from t: CardioTemplate) -> DraftCardioTemplate {
        var d = DraftCardioTemplate(type: t.cardioType)
        d.structureType = t.structureType
        d.distanceUnit = t.distanceUnit
        d.isIntervalWorkout = t.isIntervalWorkout
        d.notes = t.notes
        if t.targetDurationSeconds > 0 {
            let s = t.targetDurationSeconds
            d.targetHours = s / 3600 > 0 ? "\(s / 3600)" : ""
            d.targetMinutes = (s % 3600) / 60 > 0 ? "\((s % 3600) / 60)" : ""
            d.targetSeconds = s % 60 > 0 ? "\(s % 60)" : ""
        }
        if let dist = t.targetDistance, dist > 0 { d.targetDistance = String(format: "%.2f", dist) }
        d.intervals = t.sortedIntervals.map { iv in
            var di = DraftInterval()
            di.label = iv.label; di.isRest = iv.isRest; di.intensity = iv.intensity
            if let x = iv.distanceValue, x > 0 { di.distanceText = String(format: "%.2f", x) }
            if let p = iv.paceSecondsPerUnit, p > 0 { di.paceMinutes = "\(p / 60)"; di.paceSeconds = p % 60 > 0 ? "\(p % 60)" : "" }
            if let dur = iv.durationSeconds, dur > 0 { di.durationMinutes = "\(dur / 60)"; di.durationSecondsText = dur % 60 > 0 ? "\(dur % 60)" : "" }
            if let inc = iv.inclinePercent, inc > 0 { di.inclineText = inc.weightFormatted }
            return di
        }
        return d
    }
}

// MARK: - Loose enum matching

extension TrainingGoal {
    static func loose(_ s: String) -> TrainingGoal? {
        let key = s.lowercased().replacingOccurrences(of: " ", with: "")
        return allCases.first {
            $0.rawValue.lowercased() == key ||
            $0.displayName.lowercased().replacingOccurrences(of: " ", with: "") == key
        }
    }
}

extension DifficultyLevel {
    static func loose(_ s: String) -> DifficultyLevel? {
        let key = s.lowercased().replacingOccurrences(of: " ", with: "")
        return allCases.first { $0.rawValue.lowercased() == key || $0.displayName.lowercased() == key }
    }
}

extension DayOfWeek {
    static func loose(_ s: String) -> DayOfWeek? {
        let key = s.lowercased().replacingOccurrences(of: " ", with: "")
        return allCases.first {
            $0.rawValue.lowercased() == key ||
            $0.shortName.lowercased() == key ||
            $0.rawValue.lowercased().hasPrefix(key) && key.count >= 3
        }
    }
}
