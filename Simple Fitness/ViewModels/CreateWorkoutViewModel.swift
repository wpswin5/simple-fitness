import Foundation
import SwiftUI
import SwiftData
import Observation

// MARK: - Draft Types
// Plain structs used during workout creation/editing. Converted to @Model objects on save.

/// One exercise slot in a set/block. Which exercise + whether it's timed.
struct DraftExerciseInSet: Identifiable {
    let id = UUID()
    var exercise: Exercise
    var isTimeBased: Bool = false
}

/// Per-exercise target within a single round. Aligned to a set's `exercises` by index.
struct DraftTarget: Identifiable {
    let id = UUID()
    var targetReps: Int? = 8
    var targetTime: Int? = 30
    var targetWeight: Double? = nil
    var effortLevel: Double = 0.75
}

/// One round (working set) of a block: a target per exercise slot + its own rest.
struct DraftRound: Identifiable {
    let id = UUID()
    var restSeconds: Int = 90
    var targets: [DraftTarget] = []
}

struct DraftWorkoutSet: Identifiable {
    let id = UUID()
    var exercises: [DraftExerciseInSet] = []
    var rounds: [DraftRound] = []

    var isSuperset: Bool { exercises.count > 1 }

    var displayName: String {
        switch exercises.count {
        case 0:  return "Empty Set"
        case 1:  return exercises[0].exercise.name
        default: return exercises.map { $0.exercise.name }.joined(separator: " + ")
        }
    }

    /// "3 sets"
    var setCountLabel: String {
        "\(rounds.count) set\(rounds.count == 1 ? "" : "s")"
    }

    /// Short reps/time summary across rounds, e.g. "8→6→4 reps" (single exercise only).
    var roundsDetail: String {
        guard !rounds.isEmpty, let firstSlot = exercises.first else { return "" }
        if isSuperset { return "\(exercises.count) exercises" }
        let isTimed = firstSlot.isTimeBased
        let vals: [String] = rounds.map { r in
            let t = r.targets.first
            if isTimed { return "\(t?.targetTime ?? 0)s" }
            return "\(t?.targetReps ?? 0)"
        }
        let joined = vals.joined(separator: "→")
        return isTimed ? joined : "\(joined) reps"
    }

    // MARK: - Structural mutations (keep rounds' targets aligned to exercise slots)

    /// Adds an exercise slot and a matching target to every round.
    mutating func addExercise(_ exercise: Exercise) {
        exercises.append(DraftExerciseInSet(exercise: exercise))
        if rounds.isEmpty {
            rounds = [DraftRound(targets: [DraftTarget()])]
        } else {
            for i in rounds.indices { rounds[i].targets.append(DraftTarget()) }
        }
    }

    /// Removes an exercise slot and its aligned target from every round.
    mutating func removeExercise(at index: Int) {
        guard index < exercises.count else { return }
        exercises.remove(at: index)
        for i in rounds.indices where index < rounds[i].targets.count {
            rounds[i].targets.remove(at: index)
        }
        if exercises.isEmpty { rounds = [] }
    }

    /// Appends a round, copying the previous round's targets/rest as a starting point.
    mutating func addRound() {
        guard !exercises.isEmpty else { return }
        if let last = rounds.last {
            let copies = last.targets.map { t in
                DraftTarget(targetReps: t.targetReps,
                            targetTime: t.targetTime,
                            targetWeight: t.targetWeight,
                            effortLevel: t.effortLevel)
            }
            rounds.append(DraftRound(restSeconds: last.restSeconds, targets: copies))
        } else {
            rounds.append(DraftRound(targets: exercises.map { _ in DraftTarget() }))
        }
    }

    mutating func removeRound(at index: Int) {
        guard rounds.count > 1, index < rounds.count else { return }
        rounds.remove(at: index)
    }
}

// MARK: - CreateWorkoutViewModel

@MainActor
@Observable
final class CreateWorkoutViewModel {

    // MARK: - Form State

    var workoutName: String = ""
    var workoutDescription: String = ""
    var draftSets: [DraftWorkoutSet] = []

    // MARK: - UI State

    var errorMessage: String? = nil
    var isSaving: Bool = false

    // Track whether we're editing an existing workout
    private var editingWorkout: Workout? = nil
    var isEditing: Bool { editingWorkout != nil }

    // MARK: - Init

    init() {}

    /// Create-mode with pre-seeded draft state (e.g. from AI generation).
    init(prefilled: MappedWorkout) {
        self.workoutName = prefilled.name
        self.workoutDescription = prefilled.summary
        self.draftSets = prefilled.sets
    }

    /// Loads an existing workout into draft state for editing.
    init(editing workout: Workout) {
        self.editingWorkout = workout
        self.workoutName = workout.name
        self.workoutDescription = workout.workoutDescription

        self.draftSets = workout.sortedSets.compactMap { set -> DraftWorkoutSet? in
            // Build slots, skipping exercises whose underlying Exercise was deleted.
            var draftExercises: [DraftExerciseInSet] = []
            var keptSlotOrders: [Int] = []
            for slot in set.sortedExercises {
                guard let exercise = slot.exercise else { continue }
                draftExercises.append(DraftExerciseInSet(exercise: exercise, isTimeBased: slot.isTimeBased))
                keptSlotOrders.append(slot.order)
            }
            guard !draftExercises.isEmpty else { return nil }

            // Rebuild each round's targets aligned to the kept slots.
            var draftRounds: [DraftRound] = set.sortedRounds.map { round in
                let targets: [DraftTarget] = keptSlotOrders.map { slotOrder in
                    guard let target = round.target(forSlot: slotOrder) else { return DraftTarget() }
                    return DraftTarget(
                        targetReps: target.targetReps ?? 8,
                        targetTime: target.targetTime ?? 30,
                        targetWeight: target.targetWeight,
                        effortLevel: target.effortLevel ?? 0.75
                    )
                }
                return DraftRound(restSeconds: round.restSeconds, targets: targets)
            }
            if draftRounds.isEmpty {
                draftRounds = [DraftRound(targets: draftExercises.map { _ in DraftTarget() })]
            }

            var draft = DraftWorkoutSet()
            draft.exercises = draftExercises
            draft.rounds = draftRounds
            return draft
        }
    }

    // MARK: - Validation

    var isValid: Bool {
        guard !workoutName.trimmingCharacters(in: .whitespaces).isEmpty, !draftSets.isEmpty else { return false }
        return draftSets.allSatisfy { !$0.exercises.isEmpty && !$0.rounds.isEmpty }
    }

    var totalSetCount: Int { draftSets.reduce(0) { $0 + $1.rounds.count } }

    var estimatedDurationMinutes: Int {
        var totalSeconds = 0
        for set in draftSets {
            for round in set.rounds {
                totalSeconds += set.exercises.count * 45   // ~45s of work per exercise per round
                totalSeconds += round.restSeconds
            }
        }
        return max(1, totalSeconds / 60)
    }

    // MARK: - Set Management

    func addSet(_ draft: DraftWorkoutSet) { draftSets.append(draft) }

    func updateSet(_ draft: DraftWorkoutSet) {
        guard let index = draftSets.firstIndex(where: { $0.id == draft.id }) else { return }
        draftSets[index] = draft
    }

    func removeSet(at offsets: IndexSet) { draftSets.remove(atOffsets: offsets) }
    func moveSets(from source: IndexSet, to destination: Int) {
        draftSets.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Save (create or update)

    @discardableResult
    func save(context: ModelContext) -> Bool {
        let trimmedName = workoutName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a workout name."
            return false
        }
        guard !draftSets.isEmpty else {
            errorMessage = "Add at least one set before saving."
            return false
        }

        isSaving = true
        defer { isSaving = false }

        if let existing = editingWorkout {
            return update(existing, trimmedName: trimmedName, context: context)
        } else {
            return create(trimmedName: trimmedName, context: context)
        }
    }

    // MARK: - Private helpers

    private func create(trimmedName: String, context: ModelContext) -> Bool {
        let workout = Workout(name: trimmedName)
        workout.workoutDescription = workoutDescription
        workout.estimatedDuration = estimatedDurationMinutes
        buildSets(into: &workout.sets, context: context)
        context.insert(workout)
        return persistSave(context: context)
    }

    private func update(_ workout: Workout, trimmedName: String, context: ModelContext) -> Bool {
        workout.name = trimmedName
        workout.workoutDescription = workoutDescription
        workout.estimatedDuration = estimatedDurationMinutes

        // Delete old sets (cascade removes their exercises/rounds/targets)
        for set in workout.sets { context.delete(set) }
        workout.sets = []

        buildSets(into: &workout.sets, context: context)
        return persistSave(context: context)
    }

    private func buildSets(into sets: inout [WorkoutSet], context: ModelContext) {
        for (setIndex, draft) in draftSets.enumerated() {
            guard !draft.exercises.isEmpty, !draft.rounds.isEmpty else { continue }

            // Exercise slots
            let slots: [ExerciseInSet] = draft.exercises.enumerated().map { i, draftEx in
                let eis = ExerciseInSet(exercise: draftEx.exercise, isTimeBased: draftEx.isTimeBased, order: i)
                context.insert(eis)
                return eis
            }

            // Rounds with per-exercise targets
            let rounds: [SetRound] = draft.rounds.enumerated().map { rIndex, draftRound in
                let targets: [ExerciseTarget] = draft.exercises.enumerated().map { i, draftEx in
                    let dt = i < draftRound.targets.count ? draftRound.targets[i] : DraftTarget()
                    let target = ExerciseTarget(
                        order: i,
                        exerciseName: draftEx.exercise.name,
                        targetReps: draftEx.isTimeBased ? nil : dt.targetReps,
                        targetTime: draftEx.isTimeBased ? dt.targetTime : nil,
                        targetWeight: dt.targetWeight,
                        effortLevel: dt.effortLevel
                    )
                    context.insert(target)
                    return target
                }
                let round = SetRound(order: rIndex, restSeconds: draftRound.restSeconds, targets: targets)
                context.insert(round)
                return round
            }

            let set = WorkoutSet(exercises: slots, rounds: rounds, order: setIndex)
            context.insert(set)
            sets.append(set)
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
