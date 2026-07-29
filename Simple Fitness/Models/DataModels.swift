import Foundation
import SwiftData

// MARK: - Exercise

@Model
final class Exercise {
    var id: String = UUID().uuidString
    var name: String
    var muscleGroup: MuscleGroup
    var equipment: String = ""
    var isCustom: Bool = true
    var createdDate: Date = Date()
    var estimatedOneRepMax: Double = 0.0
    var exerciseDescription: String = ""

    init(name: String, muscleGroup: MuscleGroup, equipment: String = "", description: String = "") {
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.exerciseDescription = description
    }
}

enum MuscleGroup: String, Codable, CaseIterable {
    case chest, back, shoulders, biceps, triceps, forearms
    case quadriceps, hamstrings, glutes, calves, core
    case legs, fullBody

    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .quadriceps: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .calves: return "Calves"
        case .core: return "Core"
        case .legs: return "Legs"
        case .fullBody: return "Full Body"
        }
    }
}

// MARK: - Workout Structure

/// One exercise "slot" within a set/block. Defines *which* exercise and whether it's
/// timed vs rep-based; the per-round targets (reps/weight/effort) live on `ExerciseTarget`.
@Model
final class ExerciseInSet {
    var id: String = UUID().uuidString
    var exercise: Exercise?
    var exerciseName: String
    var isTimeBased: Bool = false
    var order: Int = 0
    var notes: String = ""

    init(exercise: Exercise, isTimeBased: Bool = false, order: Int = 0) {
        self.exercise = exercise
        self.exerciseName = exercise.name
        self.isTimeBased = isTimeBased
        self.order = order
    }
}

/// The target for a single exercise slot within a single round
/// (e.g. "8 reps @ 135 lb, 75% effort").
@Model
final class ExerciseTarget {
    var id: String = UUID().uuidString
    var order: Int = 0                // matches the ExerciseInSet slot's `order`
    var exerciseName: String = ""
    var targetReps: Int?
    var targetTime: Int?             // seconds, for timed exercises
    var targetWeight: Double?        // lbs; nil = unspecified
    var effortLevel: Double?         // 0.0–1.0 of estimated 1RM; nil = unspecified

    init(order: Int,
         exerciseName: String,
         targetReps: Int? = nil,
         targetTime: Int? = nil,
         targetWeight: Double? = nil,
         effortLevel: Double? = nil) {
        self.order = order
        self.exerciseName = exerciseName
        self.targetReps = targetReps
        self.targetTime = targetTime
        self.targetWeight = targetWeight
        self.effortLevel = effortLevel
    }

    /// e.g. "8 reps · 135 lb · 75%" or "60s hold"
    var displaySummary: String {
        var parts: [String] = []
        if let t = targetTime {
            parts.append("\(t)s")
        } else if let r = targetReps {
            parts.append("\(r) reps")
        }
        if let w = targetWeight, w > 0 {
            parts.append("\(w.weightFormatted) lb")
        }
        if let e = effortLevel, e > 0 {
            parts.append("\(Int(e * 100))%")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

/// One round (working set) of a block. Holds a per-exercise target and its own rest.
@Model
final class SetRound {
    var id: String = UUID().uuidString
    var order: Int = 0
    var restSeconds: Int = 60
    @Relationship(deleteRule: .cascade) var targets: [ExerciseTarget] = []

    init(order: Int, restSeconds: Int = 60, targets: [ExerciseTarget] = []) {
        self.order = order
        self.restSeconds = restSeconds
        self.targets = targets
    }

    var sortedTargets: [ExerciseTarget] { targets.sorted { $0.order < $1.order } }

    /// The target matching a given exercise slot order.
    func target(forSlot slotOrder: Int) -> ExerciseTarget? {
        targets.first { $0.order == slotOrder }
    }
}

/// A set/block: one exercise (or a superset of several) performed for one or more rounds.
@Model
final class WorkoutSet {
    var id: String = UUID().uuidString
    @Relationship(deleteRule: .cascade) var exercises: [ExerciseInSet] = []
    @Relationship(deleteRule: .cascade) var rounds: [SetRound] = []
    var order: Int = 0

    init(exercises: [ExerciseInSet], rounds: [SetRound] = [], order: Int = 0) {
        self.exercises = exercises
        self.rounds = rounds
        self.order = order
    }

    var isSuperset: Bool { exercises.count > 1 }
    var sortedExercises: [ExerciseInSet] { exercises.sorted { $0.order < $1.order } }
    var sortedRounds: [SetRound] { rounds.sorted { $0.order < $1.order } }
    var roundCount: Int { rounds.count }
}

@Model
final class Workout {
    var id: String = UUID().uuidString
    var name: String
    var workoutDescription: String = ""
    @Relationship(deleteRule: .cascade) var sets: [WorkoutSet] = []
    var estimatedDuration: Int = 0  // minutes
    var isCustom: Bool = true
    var createdDate: Date = Date()
    var createdByUser: String?

    init(name: String, sets: [WorkoutSet] = []) {
        self.name = name
        self.sets = sets.sorted { $0.order < $1.order }
    }

    var sortedSets: [WorkoutSet] { sets.sorted { $0.order < $1.order } }
    var totalSetCount: Int { sets.reduce(0) { $0 + $1.rounds.count } }
    var exerciseCount: Int { sets.reduce(0) { $0 + $1.exercises.count } }
}

// MARK: - Programs

/// A single scheduled activity within a program day (strength workout or cardio)
@Model
final class ProgramDayActivity {
    var id: String = UUID().uuidString
    var order: Int = 0
    var workout: Workout?
    var cardioTemplate: CardioTemplate?

    init(order: Int, workout: Workout? = nil, cardioTemplate: CardioTemplate? = nil) {
        self.order = order
        self.workout = workout
        self.cardioTemplate = cardioTemplate
    }

    var isWorkout: Bool { workout != nil }

    var displayName: String {
        if let w = workout { return w.name }
        if let c = cardioTemplate { return c.displayName }
        return "Activity"
    }

    var icon: String {
        if workout != nil { return "dumbbell.fill" }
        if let c = cardioTemplate { return c.cardioType.icon }
        return "figure.run"
    }
}

@Model
final class ProgramDay {
    var id: String = UUID().uuidString
    var dayOfWeek: DayOfWeek
    @Relationship(deleteRule: .cascade) var activities: [ProgramDayActivity] = []
    var notes: String = ""

    init(dayOfWeek: DayOfWeek, activities: [ProgramDayActivity] = []) {
        self.dayOfWeek = dayOfWeek
        self.activities = activities
    }

    var isRestDay: Bool { activities.isEmpty }
    var sortedActivities: [ProgramDayActivity] { activities.sorted { $0.order < $1.order } }
}

/// A single interval within a CardioTemplate (e.g. "1.0 mi @ 6:00 pace")
@Model
final class CardioTemplateInterval {
    var id: String = UUID().uuidString
    var order: Int = 0
    var label: String = ""              // e.g. "Warmup", "Fast", "Recovery"
    var distanceValue: Double?          // in parent template's distanceUnit
    var durationSeconds: Int?           // time-based segment; nil = distance/open
    var paceSecondsPerUnit: Int?        // seconds per mile or km; nil = no pace target
    var intensity: CardioIntensity = CardioIntensity.moderate
    var inclinePercent: Double?         // for hill work; nil = flat/unspecified
    var isRest: Bool = false

    init(order: Int) {
        self.order = order
    }

    /// "6:00" or nil
    var paceFormatted: String? {
        guard let p = paceSecondsPerUnit, p > 0 else { return nil }
        return String(format: "%d:%02d", p / 60, p % 60)
    }

    /// One-line summary: "Fast: 0.50 · 2:00 @ 6:00 · 4% incline" / "Rest · 1:00"
    var displaySummary: String {
        if isRest {
            let base = label.isEmpty ? "Rest" : label
            if let dur = durationSeconds, dur > 0 { return "\(base) · \(dur.timerFormatted)" }
            return base
        }
        var parts: [String] = []
        if let d = distanceValue, d > 0     { parts.append(String(format: "%.2f", d)) }
        if let dur = durationSeconds, dur > 0 { parts.append(dur.timerFormatted) }
        if let pace = paceFormatted          { parts.append("@ \(pace)") }
        if let incline = inclinePercent, incline > 0 {
            parts.append(String(format: "%.0f%% incline", incline))
        }
        let body = parts.joined(separator: " · ")
        if body.isEmpty { return label.isEmpty ? "Interval" : label }
        return label.isEmpty ? body : "\(label): \(body)"
    }
}

/// A cardio activity target — used in program days (isTemplate=false) or as a saved library template (isTemplate=true)
@Model
final class CardioTemplate {
    var id: String = UUID().uuidString
    var name: String = ""                 // user-facing name for library templates
    var isTemplate: Bool = false          // true = standalone saved template; false = program-day config
    var cardioType: CardioType = CardioType.running
    var structureType: CardioWorkoutType = CardioWorkoutType.steady
    var targetDurationSeconds: Int = 0    // 0 = unspecified
    var targetDistance: Double?           // nil = unspecified
    var distanceUnit: DistanceUnit = DistanceUnit.miles
    var isIntervalWorkout: Bool = false
    var notes: String = ""
    @Relationship(deleteRule: .cascade) var intervals: [CardioTemplateInterval] = []

    init(cardioType: CardioType, name: String = "", isTemplate: Bool = false) {
        self.cardioType = cardioType
        self.name = name
        self.isTemplate = isTemplate
    }

    /// A structured workout has discrete segments to step through (guided-session eligible).
    var isStructured: Bool {
        !intervals.isEmpty && (structureType.isSegmented || isIntervalWorkout)
    }

    /// Short label for day rows, e.g. "Run · Hill Repeats · 4 segments" or "Run · 5.0 mi"
    var displayName: String {
        var parts: [String] = [cardioType.displayName]
        if isStructured {
            parts.append(structureType.isSegmented ? structureType.displayName : "Intervals")
            let count = intervals.filter { !$0.isRest }.count
            if count > 0 { parts.append("\(count) segment\(count == 1 ? "" : "s")") }
        } else if let dist = targetDistance, dist > 0 {
            parts.append(String(format: "%.1f %@", dist, distanceUnit.abbreviation))
        } else if targetDurationSeconds > 0 {
            let h = targetDurationSeconds / 3600
            let m = (targetDurationSeconds % 3600) / 60
            parts.append(h > 0 ? "\(h)h \(m)m" : "\(m) min")
        }
        return parts.joined(separator: " · ")
    }

    /// Sorted intervals for display
    var sortedIntervals: [CardioTemplateInterval] {
        intervals.sorted { $0.order < $1.order }
    }
}

@Model
final class ProgramWeek {
    var id: String = UUID().uuidString
    var weekNumber: Int
    @Relationship(deleteRule: .cascade) var days: [ProgramDay] = []

    init(weekNumber: Int, days: [ProgramDay] = []) {
        self.weekNumber = weekNumber
        self.days = days
    }
}

@Model
final class Program {
    var id: String = UUID().uuidString
    var name: String
    var programDescription: String = ""
    @Relationship(deleteRule: .cascade) var weeks: [ProgramWeek] = []
    var targetGoal: TrainingGoal
    var difficultyLevel: DifficultyLevel
    var isCustom: Bool = true
    var createdDate: Date = Date()
    var createdByUser: String?

    init(name: String, weeks: [ProgramWeek] = [], targetGoal: TrainingGoal, difficultyLevel: DifficultyLevel = .intermediate) {
        self.name = name
        self.weeks = weeks.sorted { $0.weekNumber < $1.weekNumber }
        self.targetGoal = targetGoal
        self.difficultyLevel = difficultyLevel
    }

    var sortedWeeks: [ProgramWeek] { weeks.sorted { $0.weekNumber < $1.weekNumber } }
}

enum DayOfWeek: String, Codable, CaseIterable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    var shortName: String { rawValue.prefix(3).capitalized }
    var displayName: String { rawValue.capitalized }
}

enum TrainingGoal: String, Codable, CaseIterable {
    case strengthGain, hypertrophy, endurance, athleticism, weightLoss, conditioning

    var displayName: String {
        switch self {
        case .strengthGain: return "Strength"
        case .hypertrophy: return "Hypertrophy"
        case .endurance: return "Endurance"
        case .athleticism: return "Athleticism"
        case .weightLoss: return "Weight Loss"
        case .conditioning: return "Conditioning"
        }
    }
}

enum DifficultyLevel: String, Codable, CaseIterable {
    case beginner, intermediate, advanced, elite
    var displayName: String { rawValue.capitalized }
}

// MARK: - User Profile

@Model
final class UserProfile {
    var id: String = UUID().uuidString
    var auth0Id: String?
    var email: String
    var name: String = ""
    var createdDate: Date = Date()
    var lastSyncDate: Date?
    var preferredWeightUnit: WeightUnit = WeightUnit.lbs

    @Relationship(deleteRule: .cascade) var registeredPrograms: [ProgramRegistration] = []

    init(email: String, name: String = "", auth0Id: String? = nil) {
        self.email = email
        self.name = name
        self.auth0Id = auth0Id
    }
}

@Model
final class ProgramRegistration {
    var id: String = UUID().uuidString
    var program: Program?
    var programName: String
    var startDate: Date
    var currentWeek: Int = 1
    var currentDay: Int = 1
    var isActive: Bool = true

    init(program: Program, startDate: Date = Date()) {
        self.program = program
        self.programName = program.name
        self.startDate = startDate
    }
}

enum WeightUnit: String, Codable {
    case lbs, kg
}

// MARK: - Workout Logging

@Model
final class WorkoutLog {
    var id: String = UUID().uuidString
    var workout: Workout?
    var workoutName: String
    var startDate: Date
    var completedDate: Date?
    var durationSeconds: Int = 0
    @Relationship(deleteRule: .cascade) var setLogs: [WorkoutSetLog] = []
    var notes: String = ""
    var isComplete: Bool = false

    init(workout: Workout, startDate: Date = Date()) {
        self.workout = workout
        self.workoutName = workout.name
        self.startDate = startDate
    }

    var durationFormatted: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@Model
final class WorkoutSetLog {
    var id: String = UUID().uuidString
    var setOrder: Int = 0
    var completedDate: Date = Date()
    @Relationship(deleteRule: .cascade) var exerciseLogs: [ExerciseLog] = []

    init(setOrder: Int, exerciseLogs: [ExerciseLog] = []) {
        self.setOrder = setOrder
        self.exerciseLogs = exerciseLogs
    }
}

@Model
final class ExerciseLog {
    var id: String = UUID().uuidString
    var exerciseName: String
    var reps: Int?
    var weight: Double?
    var durationSeconds: Int?
    var rpe: Double?       // Rate of Perceived Exertion 0–10
    var notes: String = ""

    init(exerciseName: String, reps: Int? = nil, weight: Double? = nil, rpe: Double? = nil) {
        self.exerciseName = exerciseName
        self.reps = reps
        self.weight = weight
        self.rpe = rpe
    }

    var displaySummary: String {
        var parts: [String] = []
        if let w = weight { parts.append("\(Int(w)) lbs") }
        if let r = reps { parts.append("\(r) reps") }
        if let d = durationSeconds { parts.append("\(d)s") }
        return parts.isEmpty ? "—" : parts.joined(separator: " × ")
    }
}

// MARK: - In-Memory Log Entry (used during active workout, not persisted until complete)

struct ExerciseLogEntry {
    var exerciseName: String
    var reps: Int? = nil
    var weight: Double? = nil
    var rpe: Double? = nil
    var notes: String = ""

    var isValid: Bool { reps != nil || weight != nil }
}

// MARK: - Cardio Enums

enum CardioType: String, Codable, CaseIterable {
    case running, biking, swimming

    var displayName: String {
        switch self {
        case .running:  return "Run"
        case .biking:   return "Bike"
        case .swimming: return "Swim"
        }
    }

    var icon: String {
        switch self {
        case .running:  return "figure.run"
        case .biking:   return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        }
    }
}

enum DistanceUnit: String, Codable, CaseIterable {
    case miles, kilometers

    var abbreviation: String {
        switch self {
        case .miles:     return "mi"
        case .kilometers: return "km"
        }
    }

    var displayName: String {
        switch self {
        case .miles:     return "Miles"
        case .kilometers: return "Kilometers"
        }
    }
}

enum SwimStroke: String, Codable, CaseIterable {
    case freestyle, backstroke, breaststroke, butterfly, im

    var displayName: String {
        switch self {
        case .freestyle:   return "Freestyle"
        case .backstroke:  return "Backstroke"
        case .breaststroke: return "Breaststroke"
        case .butterfly:   return "Butterfly"
        case .im:          return "IM"
        }
    }
}

/// The structure of a cardio workout — drives default segment scaffolding and display.
enum CardioWorkoutType: String, Codable, CaseIterable {
    case steady, intervals, fartlek, hills, tempo, progression

    var displayName: String {
        switch self {
        case .steady:      return "Steady"
        case .intervals:   return "Intervals"
        case .fartlek:     return "Fartlek"
        case .hills:       return "Hill Repeats"
        case .tempo:       return "Tempo"
        case .progression: return "Progression"
        }
    }

    var icon: String {
        switch self {
        case .steady:      return "figure.run"
        case .intervals:   return "bolt.fill"
        case .fartlek:     return "shuffle"
        case .hills:       return "mountain.2.fill"
        case .tempo:       return "gauge.with.dots.needle.67percent"
        case .progression: return "chart.line.uptrend.xyaxis"
        }
    }

    var blurb: String {
        switch self {
        case .steady:      return "One continuous effort"
        case .intervals:   return "Hard efforts with recovery"
        case .fartlek:     return "Unstructured speed play"
        case .hills:       return "Uphill repeats with recovery"
        case .tempo:       return "Sustained comfortably-hard pace"
        case .progression: return "Gradually increasing effort"
        }
    }

    /// Whether this type is built from discrete segments (everything except steady).
    var isSegmented: Bool { self != .steady }
}

/// Effort level for a cardio segment.
enum CardioIntensity: String, Codable, CaseIterable {
    case easy, moderate, hard, max, rest

    var displayName: String {
        switch self {
        case .easy:     return "Easy"
        case .moderate: return "Moderate"
        case .hard:     return "Hard"
        case .max:      return "Max"
        case .rest:     return "Rest"
        }
    }
}

// MARK: - Cardio Models

/// One interval or rest segment in a run or bike session
@Model
final class CardioSplit {
    var id: String = UUID().uuidString
    var order: Int = 0
    var label: String = ""         // e.g. "Warmup", "Interval 1", "Rest"
    var durationSeconds: Int?
    var distanceValue: Double?     // in user's preferred unit
    var isRest: Bool = false
    var notes: String = ""

    init(order: Int, label: String = "", isRest: Bool = false) {
        self.order = order
        self.label = label
        self.isRest = isRest
    }

    var durationFormatted: String? {
        guard let d = durationSeconds, d > 0 else { return nil }
        let m = d / 60; let s = d % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// One set in a swim session
@Model
final class SwimSet {
    var id: String = UUID().uuidString
    var order: Int = 0
    var stroke: SwimStroke = SwimStroke.freestyle
    var laps: Int?
    var meters: Int?
    var durationSeconds: Int?
    var notes: String = ""

    init(order: Int, stroke: SwimStroke = .freestyle) {
        self.order = order
        self.stroke = stroke
    }

    var displaySummary: String {
        var parts: [String] = []
        if let l = laps   { parts.append("\(l) laps") }
        if let m = meters { parts.append("\(m) m") }
        parts.append(stroke.displayName)
        return parts.joined(separator: " · ")
    }
}

/// A completed cardio session (run, bike, or swim)
@Model
final class CardioLog {
    var id: String = UUID().uuidString
    var cardioType: CardioType = CardioType.running
    var date: Date = Date()
    var notes: String = ""

    // Duration
    var durationSeconds: Int = 0

    // Distance (running & biking)
    var distanceValue: Double?
    var distanceUnit: DistanceUnit = DistanceUnit.miles

    // Intervals/fartlek (running & biking)
    var isIntervalWorkout: Bool = false
    @Relationship(deleteRule: .cascade) var splits: [CardioSplit] = []

    // Swimming
    @Relationship(deleteRule: .cascade) var swimSets: [SwimSet] = []

    init(cardioType: CardioType, date: Date = Date()) {
        self.cardioType = cardioType
        self.date = date
    }

    /// Pace in seconds per mile or km (nil if either field is missing)
    var paceSeconds: Double? {
        guard let dist = distanceValue, dist > 0, durationSeconds > 0 else { return nil }
        return Double(durationSeconds) / dist
    }

    /// Formatted pace string: "MM:SS /mi" or "MM:SS /km"
    var paceFormatted: String? {
        guard let p = paceSeconds else { return nil }
        let m = Int(p) / 60; let s = Int(p) % 60
        return String(format: "%d:%02d /%@", m, s, distanceUnit.abbreviation)
    }

    /// Duration formatted as H:MM:SS or M:SS
    var durationFormatted: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        let s = durationSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// Short subtitle for list display
    var listSubtitle: String {
        var parts: [String] = []
        if durationSeconds > 0 { parts.append(durationFormatted) }
        if let dist = distanceValue, dist > 0 {
            parts.append(String(format: "%.2f %@", dist, distanceUnit.abbreviation))
        }
        if let pace = paceFormatted { parts.append(pace) }
        return parts.isEmpty ? "No data" : parts.joined(separator: " · ")
    }
}
