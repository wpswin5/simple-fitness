import Foundation
import SwiftData

// MARK: - WorkoutCSV
// Encodes/decodes strength workouts to/from a "long" CSV section (one row per set).
// Decode produces MappedWorkout — the same DTO the AI generator emits — so imported
// workouts reuse the existing prefilled editor and save path.

@MainActor
enum WorkoutCSV {

    static let headerColumns = ["workout", "block", "exercise", "muscle_group", "timed", "set", "reps", "weight", "effort", "rest"]

    // MARK: - Decode

    /// Parses a workout section into MappedWorkouts, sharing `resolver` so created
    /// exercises accumulate across the whole import.
    static func decode(_ section: CSVSection, resolver: inout ExerciseResolver) -> (workouts: [MappedWorkout], issues: [ImportIssue]) {
        var issues: [ImportIssue] = []

        // Required columns.
        guard let blockCol = section.columnIndex("block"),
              let exerciseCol = section.columnIndex("exercise"),
              let setCol = section.columnIndex("set") else {
            issues.append(.error("Workout section is missing a required column (needs block, exercise, set)", section: "workout", line: section.directiveLine))
            return ([], issues)
        }
        let workoutCol = section.columnIndex("workout")
        let muscleCol = section.columnIndex("muscle_group")
        let timedCol = section.columnIndex("timed")
        let repsCol = section.columnIndex("reps")
        let weightCol = section.columnIndex("weight")
        let effortCol = section.columnIndex("effort")
        let restCol = section.columnIndex("rest")

        let defaultName = section.metadata["name"] ?? "Imported Workout"

        // Ordered accumulation: workout → block → set → per-exercise target.
        var order: [String] = []
        var accum: [String: WorkoutAccum] = [:]

        for row in section.rows {
            func field(_ col: Int?) -> String {
                guard let col, col < row.fields.count else { return "" }
                return row.fields[col].trimmingCharacters(in: .whitespaces)
            }

            let exerciseName = field(exerciseCol)
            guard !exerciseName.isEmpty else {
                issues.append(.error("Row has no exercise name", section: "workout", line: row.line)); continue
            }
            guard let block = Int(field(blockCol)) else {
                issues.append(.error("Invalid block '\(field(blockCol))'", section: "workout", line: row.line)); continue
            }
            guard let setNo = Int(field(setCol)) else {
                issues.append(.error("Invalid set '\(field(setCol))'", section: "workout", line: row.line)); continue
            }

            let workoutName = workoutCol != nil && !field(workoutCol).isEmpty ? field(workoutCol) : defaultName
            let timed = parseBool(field(timedCol))

            // Muscle group (only used when creating a brand-new exercise).
            var muscle: MuscleGroup? = nil
            let muscleRaw = field(muscleCol)
            if !muscleRaw.isEmpty {
                muscle = MuscleGroup.loose(muscleRaw)
                if muscle == nil {
                    issues.append(.warning("Unknown muscle group '\(muscleRaw)' → Full Body", section: "workout", line: row.line))
                }
            }

            // Target values.
            var target = DraftTarget()
            if timed {
                target.targetReps = nil
                target.targetTime = Int(field(repsCol)) ?? 30
            } else {
                if let r = Int(field(repsCol)) {
                    target.targetReps = r
                } else {
                    target.targetReps = 8
                    if !field(repsCol).isEmpty {
                        issues.append(.warning("Invalid reps '\(field(repsCol))' → 8", section: "workout", line: row.line))
                    }
                }
                target.targetTime = nil
            }
            if let w = Double(field(weightCol)), w > 0 { target.targetWeight = w }
            if let e = Int(field(effortCol)) {
                let clamped = min(max(e, 40), 100)
                if clamped != e {
                    issues.append(.warning("Effort '\(e)' clamped to \(clamped)", section: "workout", line: row.line))
                }
                target.effortLevel = Double(clamped) / 100.0
            }
            let rest = min(max(Int(field(restCol)) ?? 60, 15), 600)

            // Insert into accumulator.
            if accum[workoutName] == nil {
                accum[workoutName] = WorkoutAccum()
                order.append(workoutName)
            }
            accum[workoutName]?.add(block: block, set: setNo, exercise: exerciseName,
                                    muscle: muscle, timed: timed, target: target, rest: rest)
        }

        // Build MappedWorkouts.
        var workouts: [MappedWorkout] = []
        for name in order {
            guard let acc = accum[name] else { continue }
            let sets = acc.buildSets(resolver: &resolver)
            guard !sets.isEmpty else {
                issues.append(.warning("Workout '\(name)' had no valid sets and was skipped", section: "workout"))
                continue
            }
            let description = accum[name]?.description ?? section.metadata["description"] ?? ""
            workouts.append(MappedWorkout(name: name, summary: description, sets: sets, createdExercises: []))
        }
        return (workouts, issues)
    }

    // MARK: - Encode

    /// Emits one `#! workout v1` section per workout (metadata name/description, no `workout` column).
    static func encode(_ workouts: [Workout]) -> String {
        workouts.map(encodeOne).joined(separator: "\n\n")
    }

    private static func encodeOne(_ workout: Workout) -> String {
        var lines: [String] = ["#! workout v1"]
        lines.append("#: name = \(workout.name)")
        if !workout.workoutDescription.isEmpty {
            lines.append("#: description = \(workout.workoutDescription)")
        }
        let header = ["block", "exercise", "muscle_group", "timed", "set", "reps", "weight", "effort", "rest"]
        lines.append(CSVParser.encodeRow(header))

        for (blockIndex, set) in workout.sortedSets.enumerated() {
            let slots = set.sortedExercises
            for (setIndex, round) in set.sortedRounds.enumerated() {
                for slot in slots {
                    let t = round.target(forSlot: slot.order)
                    let timed = slot.isTimeBased
                    let repsOrTime = timed ? (t?.targetTime.map(String.init) ?? "") : (t?.targetReps.map(String.init) ?? "")
                    let weight = t?.targetWeight.map { $0.weightFormatted } ?? ""
                    let effort = t?.effortLevel.map { String(Int(($0 * 100).rounded())) } ?? ""
                    let row = [
                        String(blockIndex + 1),
                        slot.exerciseName,
                        slot.exercise?.muscleGroup.rawValue ?? "",
                        timed ? "true" : "false",
                        String(setIndex + 1),
                        repsOrTime,
                        weight,
                        effort,
                        String(round.restSeconds),
                    ]
                    lines.append(CSVParser.encodeRow(row))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Value parsing

    private static func parseBool(_ s: String) -> Bool {
        ["true", "yes", "y", "1", "t"].contains(s.lowercased())
    }
}

// MARK: - Accumulator

/// Gathers rows for one workout, preserving block/set order, before building drafts.
private struct WorkoutAccum {
    var description: String? = nil

    private var blockOrder: [Int] = []
    private var blocks: [Int: BlockAccum] = [:]

    mutating func add(block: Int, set: Int, exercise: String, muscle: MuscleGroup?, timed: Bool, target: DraftTarget, rest: Int) {
        if blocks[block] == nil {
            blocks[block] = BlockAccum()
            blockOrder.append(block)
        }
        blocks[block]?.add(set: set, exercise: exercise, muscle: muscle, timed: timed, target: target, rest: rest)
    }

    func buildSets(resolver: inout ExerciseResolver) -> [DraftWorkoutSet] {
        blockOrder.compactMap { blocks[$0]?.build(resolver: &resolver) }
    }
}

private struct BlockAccum {
    private var exerciseOrder: [String] = []              // normalized keys, first-seen order
    private var slotMeta: [String: (name: String, muscle: MuscleGroup?, timed: Bool)] = [:]
    private var setOrder: [Int] = []
    private var restBySet: [Int: Int] = [:]
    private var targets: [Int: [String: DraftTarget]] = [:]   // set → normKey → target

    mutating func add(set: Int, exercise: String, muscle: MuscleGroup?, timed: Bool, target: DraftTarget, rest: Int) {
        let key = ExerciseResolver.normalize(exercise)
        if slotMeta[key] == nil {
            slotMeta[key] = (exercise, muscle, timed)
            exerciseOrder.append(key)
        }
        if targets[set] == nil {
            targets[set] = [:]
            setOrder.append(set)
        }
        targets[set]?[key] = target
        restBySet[set] = rest
    }

    func build(resolver: inout ExerciseResolver) -> DraftWorkoutSet? {
        let slots: [DraftExerciseInSet] = exerciseOrder.compactMap { key in
            guard let meta = slotMeta[key] else { return nil }
            return resolver.resolve(name: meta.name, muscleGroup: meta.muscle, isTimeBased: meta.timed)
        }
        guard !slots.isEmpty else { return nil }

        let rounds: [DraftRound] = setOrder.sorted().map { setNo in
            let perExercise = targets[setNo] ?? [:]
            let roundTargets = exerciseOrder.map { key in perExercise[key] ?? DraftTarget() }
            return DraftRound(restSeconds: restBySet[setNo] ?? 60, targets: roundTargets)
        }

        var draft = DraftWorkoutSet()
        draft.exercises = slots
        draft.rounds = rounds
        return draft
    }
}

// MARK: - MuscleGroup loose matching

extension MuscleGroup {
    /// Matches a user-written muscle group against rawValue or displayName, space-insensitively.
    static func loose(_ s: String) -> MuscleGroup? {
        let key = s.lowercased().replacingOccurrences(of: " ", with: "")
        return allCases.first {
            $0.rawValue.lowercased() == key ||
            $0.displayName.lowercased().replacingOccurrences(of: " ", with: "") == key
        }
    }
}
