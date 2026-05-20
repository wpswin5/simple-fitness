import Foundation
import SwiftUI
import SwiftData
import Observation

// MARK: - Draft Types

/// A single planned interval within a cardio template (not persisted until save)
struct DraftInterval: Identifiable {
    let id = UUID()
    var label: String = ""
    var distanceText: String = ""
    var paceMinutes: String = ""
    var paceSeconds: String = ""
    var isRest: Bool = false

    var paceSecondsPerUnit: Int? {
        let m = Int(paceMinutes) ?? 0
        let s = Int(paceSeconds) ?? 0
        let total = m * 60 + s
        return total > 0 ? total : nil
    }

    var displaySummary: String {
        if isRest { return "Rest" }
        var parts: [String] = []
        if !label.isEmpty { parts.append(label) }
        if let d = Double(distanceText), d > 0 { parts.append(String(format: "%.1f mi", d)) }
        if let p = paceSecondsPerUnit {
            let m = p / 60; let s = p % 60
            parts.append(String(format: "%d:%02d", m, s))
        }
        return parts.isEmpty ? "Interval" : parts.joined(separator: " @ ")
    }
}

/// Lightweight cardio target used while building a program day (not persisted until save)
struct DraftCardioTemplate {
    var type: CardioType = .running
    var targetHours: String = ""
    var targetMinutes: String = ""
    var targetSeconds: String = ""
    var targetDistance: String = ""
    var distanceUnit: DistanceUnit = .miles
    var isIntervalWorkout: Bool = false
    var intervals: [DraftInterval] = []
    var notes: String = ""

    var displayName: String {
        var parts: [String] = [type.displayName]
        if !intervals.isEmpty && isIntervalWorkout {
            parts.append("\(intervals.count) interval\(intervals.count == 1 ? "" : "s")")
        } else if let d = Double(targetDistance), d > 0 {
            parts.append(String(format: "%.1f %@", d, distanceUnit.abbreviation))
        } else if targetDurationSeconds > 0 {
            let h = Int(targetHours) ?? 0
            let m = Int(targetMinutes) ?? 0
            if h > 0 { parts.append("\(h)h \(m)min") }
            else { parts.append("\(m) min") }
        }
        return parts.joined(separator: " · ")
    }

    var targetDurationSeconds: Int {
        ((Int(targetHours) ?? 0) * 3600) + ((Int(targetMinutes) ?? 0) * 60) + (Int(targetSeconds) ?? 0)
    }
}

/// A single activity (workout or cardio) within a draft program day
struct DraftProgramActivity: Identifiable {
    let id = UUID()
    var order: Int = 0
    var workout: Workout? = nil
    var cardioTemplate: DraftCardioTemplate? = nil

    var isWorkout: Bool { workout != nil }

    var displayName: String {
        if let w = workout { return w.name }
        if let c = cardioTemplate { return c.displayName }
        return "Activity"
    }

    var icon: String {
        if workout != nil { return "dumbbell.fill" }
        if let c = cardioTemplate { return c.type.icon }
        return "figure.run"
    }
}

struct DraftProgramDay: Identifiable {
    let id = UUID()
    var dayOfWeek: DayOfWeek
    var activities: [DraftProgramActivity] = []

    var isRestDay: Bool { activities.isEmpty }

    var displayName: String {
        switch activities.count {
        case 0: return "Rest"
        case 1: return activities[0].displayName
        default: return activities.map { $0.displayName }.joined(separator: " + ")
        }
    }

    var icon: String { activities.first?.icon ?? "moon.fill" }
}

struct DraftProgramWeek: Identifiable {
    let id = UUID()
    var weekNumber: Int
    var days: [DraftProgramDay]

    /// Creates a blank week with all days set to rest.
    init(weekNumber: Int) {
        self.weekNumber = weekNumber
        self.days = DayOfWeek.allCases.map { DraftProgramDay(dayOfWeek: $0) }
    }

    /// Creates a week from an existing ProgramWeek.
    init(from programWeek: ProgramWeek) {
        self.weekNumber = programWeek.weekNumber
        let existingByDay = Dictionary(uniqueKeysWithValues: programWeek.days.map { ($0.dayOfWeek, $0) })
        self.days = DayOfWeek.allCases.map { dow in
            let existing = existingByDay[dow]
            let draftActivities: [DraftProgramActivity] = (existing?.sortedActivities ?? [])
                .enumerated()
                .map { index, activity in
                    var draftCardio: DraftCardioTemplate? = nil
                    if let template = activity.cardioTemplate {
                        var dc = DraftCardioTemplate(type: template.cardioType)
                        dc.distanceUnit = template.distanceUnit
                        dc.isIntervalWorkout = template.isIntervalWorkout
                        dc.notes = template.notes
                        if template.targetDurationSeconds > 0 {
                            let total = template.targetDurationSeconds
                            dc.targetHours   = total / 3600 > 0 ? "\(total / 3600)" : ""
                            dc.targetMinutes = (total % 3600) / 60 > 0 ? "\((total % 3600) / 60)" : ""
                            dc.targetSeconds = total % 60 > 0 ? "\(total % 60)" : ""
                        }
                        if let dist = template.targetDistance {
                            dc.targetDistance = String(format: "%.1f", dist)
                        }
                        dc.intervals = template.sortedIntervals.map { iv in
                            var di = DraftInterval()
                            di.label  = iv.label
                            di.isRest = iv.isRest
                            if let d = iv.distanceValue, d > 0 { di.distanceText = String(format: "%.1f", d) }
                            if let p = iv.paceSecondsPerUnit, p > 0 {
                                di.paceMinutes = "\(p / 60)"
                                di.paceSeconds = p % 60 > 0 ? "\(p % 60)" : ""
                            }
                            return di
                        }
                        draftCardio = dc
                    }
                    return DraftProgramActivity(
                        order: index,
                        workout: activity.workout,
                        cardioTemplate: draftCardio
                    )
                }
            return DraftProgramDay(dayOfWeek: dow, activities: draftActivities)
        }
    }

    var workoutDays: Int { days.filter { !$0.isRestDay }.count }
    var restDays: Int    { days.filter {  $0.isRestDay }.count }
}

// MARK: - CreateProgramViewModel

@MainActor
@Observable
final class CreateProgramViewModel {

    // MARK: - Form State

    var programName: String = ""
    var programDescription: String = ""
    var targetGoal: TrainingGoal = .strengthGain
    var difficultyLevel: DifficultyLevel = .intermediate
    var weeks: [DraftProgramWeek] = [DraftProgramWeek(weekNumber: 1)]

    // MARK: - UI State

    var errorMessage: String? = nil

    private var editingProgram: Program? = nil
    var isEditing: Bool { editingProgram != nil }

    // MARK: - Init

    init() {}

    init(editing program: Program) {
        self.editingProgram = program
        self.programName = program.name
        self.programDescription = program.programDescription
        self.targetGoal = program.targetGoal
        self.difficultyLevel = program.difficultyLevel
        self.weeks = program.sortedWeeks.map { DraftProgramWeek(from: $0) }
        if self.weeks.isEmpty {
            self.weeks = [DraftProgramWeek(weekNumber: 1)]
        }
    }

    // MARK: - Computed

    var isValid: Bool {
        !programName.trimmingCharacters(in: .whitespaces).isEmpty && !weeks.isEmpty
    }

    var totalWorkoutDays: Int { weeks.reduce(0) { $0 + $1.workoutDays } }
    var totalWeeks: Int { weeks.count }

    // MARK: - Week Management

    func addWeek() {
        weeks.append(DraftProgramWeek(weekNumber: weeks.count + 1))
    }

    func removeLastWeek() {
        guard weeks.count > 1 else { return }
        weeks.removeLast()
    }

    // MARK: - Day Assignment

    /// Replace all activities for a day with the provided list (order is set by array index).
    func setActivities(_ activities: [DraftProgramActivity], forDay dayID: UUID, inWeek weekID: UUID) {
        guard let wi = weeks.firstIndex(where: { $0.id == weekID }),
              let di = weeks[wi].days.firstIndex(where: { $0.id == dayID }) else { return }
        weeks[wi].days[di].activities = activities.enumerated().map { i, a in
            var updated = a; updated.order = i; return updated
        }
    }

    func clearDay(forDay dayID: UUID, inWeek weekID: UUID) {
        setActivities([], forDay: dayID, inWeek: weekID)
    }

    // MARK: - Copy Week 1

    func copyWeekOne(to weekID: UUID) {
        guard let source = weeks.first,
              let wi = weeks.firstIndex(where: { $0.id == weekID }) else { return }
        for (di, day) in source.days.enumerated() {
            weeks[wi].days[di].activities = day.activities
        }
    }

    // MARK: - Save (create or update)

    @discardableResult
    func save(context: ModelContext) -> Bool {
        let trimmed = programName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter a program name."
            return false
        }

        if let existing = editingProgram {
            return update(existing, trimmedName: trimmed, context: context)
        } else {
            return create(trimmedName: trimmed, context: context)
        }
    }

    // MARK: - Private helpers

    private func create(trimmedName: String, context: ModelContext) -> Bool {
        let program = Program(name: trimmedName, targetGoal: targetGoal, difficultyLevel: difficultyLevel)
        program.programDescription = programDescription
        buildWeeks(into: &program.weeks, context: context)
        context.insert(program)
        return persistSave(context: context)
    }

    private func update(_ program: Program, trimmedName: String, context: ModelContext) -> Bool {
        program.name = trimmedName
        program.programDescription = programDescription
        program.targetGoal = targetGoal
        program.difficultyLevel = difficultyLevel

        // Delete old weeks (cascade removes ProgramDay → ProgramDayActivity → CardioTemplate children)
        for week in program.weeks { context.delete(week) }
        program.weeks = []

        buildWeeks(into: &program.weeks, context: context)
        return persistSave(context: context)
    }

    private func buildWeeks(into weeks: inout [ProgramWeek], context: ModelContext) {
        for draftWeek in self.weeks {
            let programDays: [ProgramDay] = draftWeek.days.map { draftDay in
                let persistedActivities: [ProgramDayActivity] = draftDay.activities
                    .enumerated()
                    .map { index, draftActivity in
                        var cardioTemplate: CardioTemplate? = nil
                        if let draft = draftActivity.cardioTemplate {
                            let t = CardioTemplate(cardioType: draft.type)
                            t.targetDurationSeconds = draft.targetDurationSeconds
                            t.targetDistance = Double(draft.targetDistance)
                            t.distanceUnit = draft.distanceUnit
                            t.isIntervalWorkout = draft.isIntervalWorkout
                            t.notes = draft.notes
                            if draft.isIntervalWorkout {
                                let persistedIntervals = draft.intervals.enumerated().map { ivIdx, di in
                                    let iv = CardioTemplateInterval(order: ivIdx)
                                    iv.label              = di.label
                                    iv.isRest             = di.isRest
                                    iv.distanceValue      = Double(di.distanceText)
                                    iv.paceSecondsPerUnit = di.paceSecondsPerUnit
                                    context.insert(iv)
                                    return iv
                                }
                                t.intervals = persistedIntervals
                            }
                            context.insert(t)
                            cardioTemplate = t
                        }

                        let activity = ProgramDayActivity(
                            order: index,
                            workout: draftActivity.workout,
                            cardioTemplate: cardioTemplate
                        )
                        context.insert(activity)
                        return activity
                    }

                let day = ProgramDay(dayOfWeek: draftDay.dayOfWeek, activities: persistedActivities)
                context.insert(day)
                return day
            }
            let week = ProgramWeek(weekNumber: draftWeek.weekNumber, days: programDays)
            context.insert(week)
            weeks.append(week)
        }
    }

    private func persistSave(context: ModelContext) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            return false
        }
    }
}
