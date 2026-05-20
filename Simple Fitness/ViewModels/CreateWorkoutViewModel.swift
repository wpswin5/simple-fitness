import Foundation
import SwiftUI
import SwiftData
import Observation

// MARK: - Draft Types
// Plain structs used during workout creation/editing. Converted to @Model objects on save.

struct DraftExerciseInSet: Identifiable {
    let id = UUID()
    var exercise: Exercise
    var targetReps: Int? = 8
    var targetTime: Int? = nil
    var effortLevel: Double = 0.75
    var isTimeBased: Bool = false

    var displaySummary: String {
        if isTimeBased, let t = targetTime { return "\(t)s" }
        if let r = targetReps { return "\(r) reps" }
        return "AMRAP"
    }
}

struct DraftWorkoutSet: Identifiable {
    let id = UUID()
    var exercises: [DraftExerciseInSet] = []
    var restSeconds: Int = 90

    var isSuperset: Bool { exercises.count > 1 }

    var displayName: String {
        switch exercises.count {
        case 0:  return "Empty Set"
        case 1:  return exercises[0].exercise.name
        default: return exercises.map { $0.exercise.name }.joined(separator: " + ")
        }
    }

    var displayReps: String {
        guard !exercises.isEmpty else { return "" }
        let summaries = exercises.map { $0.displaySummary }
        let unique = Array(NSOrderedSet(array: summaries)) as? [String] ?? summaries
        return unique.joined(separator: " / ")
    }
}

// MARK: - CreateWorkoutViewModel

@MainActor
@Observable
final class CreateWorkoutViewModel {

    // MARK: - Form State

    var workoutName: String = ""
    var workoutDescription: String = ""
    var setRepetitions: Int = 1
    var draftSets: [DraftWorkoutSet] = []

    // MARK: - UI State

    var errorMessage: String? = nil
    var isSaving: Bool = false

    // Track whether we're editing an existing workout
    private var editingWorkout: Workout? = nil
    var isEditing: Bool { editingWorkout != nil }

    // MARK: - Init

    init() {}

    /// Loads an existing workout into draft state for editing.
    init(editing workout: Workout) {
        self.editingWorkout = workout
        self.workoutName = workout.name
        self.workoutDescription = workout.workoutDescription
        self.setRepetitions = workout.setRepetitions

        self.draftSets = workout.sortedSets.compactMap { set -> DraftWorkoutSet? in
            let draftExercises: [DraftExerciseInSet] = set.exercises.compactMap { eis in
                // Skip exercises whose Exercise reference was deleted
                guard let exercise = eis.exercise else { return nil }
                return DraftExerciseInSet(
                    exercise: exercise,
                    targetReps: eis.targetReps ?? 8,
                    targetTime: eis.targetTime,
                    effortLevel: eis.effortLevel,
                    isTimeBased: eis.targetTime != nil
                )
            }
            guard !draftExercises.isEmpty else { return nil }
            var draft = DraftWorkoutSet()
            draft.exercises = draftExercises
            draft.restSeconds = set.restSeconds
            return draft
        }
    }

    // MARK: - Validation

    var isValid: Bool {
        !workoutName.trimmingCharacters(in: .whitespaces).isEmpty && !draftSets.isEmpty
    }

    var estimatedDurationMinutes: Int {
        let restTotal = draftSets.reduce(0) { $0 + $1.restSeconds }
        let exerciseTime = draftSets.reduce(0) { $0 + ($1.exercises.count * 45) }
        let totalSeconds = (exerciseTime + restTotal) * setRepetitions
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
        let workout = Workout(name: trimmedName, setRepetitions: setRepetitions)
        workout.workoutDescription = workoutDescription
        workout.estimatedDuration = estimatedDurationMinutes
        buildSets(into: &workout.sets, context: context)
        context.insert(workout)
        return persistSave(context: context)
    }

    private func update(_ workout: Workout, trimmedName: String, context: ModelContext) -> Bool {
        // Update scalar fields
        workout.name = trimmedName
        workout.workoutDescription = workoutDescription
        workout.setRepetitions = setRepetitions
        workout.estimatedDuration = estimatedDurationMinutes

        // Delete old sets (cascade removes their ExerciseInSet children)
        for set in workout.sets { context.delete(set) }
        workout.sets = []

        // Rebuild from current draft state
        buildSets(into: &workout.sets, context: context)
        return persistSave(context: context)
    }

    private func buildSets(into sets: inout [WorkoutSet], context: ModelContext) {
        for (index, draft) in draftSets.enumerated() {
            guard !draft.exercises.isEmpty else { continue }
            let exercisesInSet: [ExerciseInSet] = draft.exercises.map { draftEx in
                let eis = ExerciseInSet(
                    exercise: draftEx.exercise,
                    targetReps: draftEx.isTimeBased ? nil : draftEx.targetReps,
                    targetTime: draftEx.isTimeBased ? draftEx.targetTime : nil,
                    effortLevel: draftEx.effortLevel
                )
                context.insert(eis)
                return eis
            }
            let set = WorkoutSet(exercises: exercisesInSet, restSeconds: draft.restSeconds, order: index)
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
