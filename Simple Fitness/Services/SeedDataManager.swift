import Foundation
import SwiftData

// MARK: - SeedDataManager
// Populates the database with sample workouts and exercises for development.
// Call seedIfNeeded() once on first launch.

@MainActor
final class SeedDataManager {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Seeds sample data only if no workouts exist yet.
    func seedIfNeeded() {
        do {
            let descriptor = FetchDescriptor<Workout>()
            let count = try context.fetchCount(descriptor)
            guard count == 0 else { return }
            seed()
        } catch {
            // Seed check failed silently — non-critical on launch
        }
    }

    private func seed() {
        // MARK: Exercises
        let benchPress  = makeExercise("Bench Press",       muscle: .chest,      equipment: "Barbell")
        let inclineDB   = makeExercise("Incline DB Press",  muscle: .chest,      equipment: "Dumbbell")
        let squat       = makeExercise("Back Squat",        muscle: .quadriceps, equipment: "Barbell")
        let rdl         = makeExercise("Romanian Deadlift", muscle: .hamstrings, equipment: "Barbell")
        let pullUp      = makeExercise("Pull-Up",           muscle: .back,       equipment: "Bodyweight")
        let bentRow     = makeExercise("Bent-Over Row",     muscle: .back,       equipment: "Barbell")
        let ohPress     = makeExercise("Overhead Press",    muscle: .shoulders,  equipment: "Barbell")
        let lateralRaise = makeExercise("Lateral Raise",   muscle: .shoulders,  equipment: "Dumbbell")
        let curlEZ      = makeExercise("EZ-Bar Curl",       muscle: .biceps,     equipment: "EZ Bar")
        let tricepDip   = makeExercise("Tricep Dip",        muscle: .triceps,    equipment: "Bodyweight")
        let plank       = makeExercise("Plank",             muscle: .core,       equipment: "Bodyweight")
        let lunge       = makeExercise("Walking Lunge",     muscle: .quadriceps, equipment: "Bodyweight")

        // MARK: Push Workout
        let pushWorkout = Workout(name: "Push Day", setRepetitions: 1)
        pushWorkout.workoutDescription = "Chest, shoulders, triceps"
        pushWorkout.estimatedDuration = 55

        let set1 = makeSet(exercises: [benchPress],   reps: 8,  effort: 0.75, rest: 120, order: 0)
        let set2 = makeSet(exercises: [inclineDB],    reps: 10, effort: 0.70, rest: 90,  order: 1)
        let set3 = makeSet(exercises: [ohPress],      reps: 8,  effort: 0.70, rest: 90,  order: 2)
        // Superset: lateral raise + tricep dip
        let set4 = makeSet(exercises: [lateralRaise, tricepDip], reps: 12, effort: 0.60, rest: 60, order: 3)

        pushWorkout.sets = [set1, set2, set3, set4]
        context.insert(pushWorkout)

        // MARK: Pull Workout
        let pullWorkout = Workout(name: "Pull Day", setRepetitions: 1)
        pullWorkout.workoutDescription = "Back and biceps"
        pullWorkout.estimatedDuration = 50

        let pSet1 = makeSet(exercises: [pullUp],   reps: 8,  effort: 0.80, rest: 120, order: 0)
        let pSet2 = makeSet(exercises: [bentRow],  reps: 8,  effort: 0.75, rest: 90,  order: 1)
        let pSet3 = makeSet(exercises: [curlEZ],   reps: 12, effort: 0.65, rest: 60,  order: 2)

        pullWorkout.sets = [pSet1, pSet2, pSet3]
        context.insert(pullWorkout)

        // MARK: Legs Workout
        let legsWorkout = Workout(name: "Leg Day", setRepetitions: 1)
        legsWorkout.workoutDescription = "Lower body strength"
        legsWorkout.estimatedDuration = 60

        let lSet1 = makeSet(exercises: [squat],  reps: 5,  effort: 0.80, rest: 180, order: 0)
        let lSet2 = makeSet(exercises: [rdl],    reps: 8,  effort: 0.70, rest: 120, order: 1)
        let lSet3 = makeSet(exercises: [lunge],  reps: 12, effort: 0.60, rest: 60,  order: 2)
        let lSet4 = makeSet(exercises: [plank],  reps: nil, effort: 0.0, rest: 60,  order: 3, time: 60)

        legsWorkout.sets = [lSet1, lSet2, lSet3, lSet4]
        context.insert(legsWorkout)

        // MARK: Full Body (Quick)
        let fullBody = Workout(name: "Full Body Express", setRepetitions: 3)
        fullBody.workoutDescription = "3-round circuit, 30 min"
        fullBody.estimatedDuration = 30

        let fbSet1 = makeSet(exercises: [squat],     reps: 10, effort: 0.60, rest: 45, order: 0)
        let fbSet2 = makeSet(exercises: [benchPress], reps: 10, effort: 0.60, rest: 45, order: 1)
        let fbSet3 = makeSet(exercises: [bentRow],   reps: 10, effort: 0.60, rest: 45, order: 2)
        let fbSet4 = makeSet(exercises: [plank], reps: nil, effort: 0.0, rest: 60, order: 3, time: 45)

        fullBody.sets = [fbSet1, fbSet2, fbSet3, fbSet4]
        context.insert(fullBody)

        do {
            try context.save()
        } catch {
            // Seed save failed — debug builds only, non-critical
        }
    }

    // MARK: - Helpers

    private func makeExercise(_ name: String, muscle: MuscleGroup, equipment: String) -> Exercise {
        let e = Exercise(name: name, muscleGroup: muscle, equipment: equipment)
        context.insert(e)
        return e
    }

    private func makeSet(
        exercises: [Exercise],
        reps: Int?,
        effort: Double,
        rest: Int,
        order: Int,
        time: Int? = nil
    ) -> WorkoutSet {
        let inSets = exercises.map { ex in
            let eis = ExerciseInSet(exercise: ex, targetReps: reps, targetTime: time, effortLevel: effort)
            context.insert(eis)
            return eis
        }
        let set = WorkoutSet(exercises: inSets, restSeconds: rest, order: order)
        context.insert(set)
        return set
    }
}
