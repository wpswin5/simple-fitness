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
        let pushWorkout = Workout(name: "Push Day")
        pushWorkout.workoutDescription = "Chest, shoulders, triceps"
        pushWorkout.estimatedDuration = 55
        pushWorkout.sets = [
            // Showcase: a classic ascending-weight progression on bench.
            variableSet(benchPress, order: 0, rounds: [
                (reps: 8, weight: 135, effort: 0.72, rest: 120),
                (reps: 6, weight: 155, effort: 0.78, rest: 150),
                (reps: 4, weight: 185, effort: 0.85, rest: 180),
            ]),
            uniformSet([inclineDB], reps: 10, weight: 50,  effort: 0.70, rest: 90,  rounds: 3, order: 1),
            uniformSet([ohPress],   reps: 8,  weight: 95,  effort: 0.70, rest: 90,  rounds: 3, order: 2),
            // Superset: lateral raise + tricep dip
            uniformSet([lateralRaise, tricepDip], reps: 12, effort: 0.60, rest: 60, rounds: 3, order: 3),
        ]
        context.insert(pushWorkout)

        // MARK: Pull Workout
        let pullWorkout = Workout(name: "Pull Day")
        pullWorkout.workoutDescription = "Back and biceps"
        pullWorkout.estimatedDuration = 50
        pullWorkout.sets = [
            uniformSet([pullUp],  reps: 8,  effort: 0.80, rest: 120, rounds: 3, order: 0),
            uniformSet([bentRow], reps: 8,  weight: 135, effort: 0.75, rest: 90,  rounds: 3, order: 1),
            uniformSet([curlEZ],  reps: 12, weight: 60,  effort: 0.65, rest: 60,  rounds: 3, order: 2),
        ]
        context.insert(pullWorkout)

        // MARK: Legs Workout
        let legsWorkout = Workout(name: "Leg Day")
        legsWorkout.workoutDescription = "Lower body strength"
        legsWorkout.estimatedDuration = 60
        legsWorkout.sets = [
            variableSet(squat, order: 0, rounds: [
                (reps: 5, weight: 225, effort: 0.80, rest: 180),
                (reps: 5, weight: 245, effort: 0.83, rest: 180),
                (reps: 5, weight: 265, effort: 0.86, rest: 180),
            ]),
            uniformSet([rdl],   reps: 8,  weight: 185, effort: 0.70, rest: 120, rounds: 3, order: 1),
            uniformSet([lunge], reps: 12, effort: 0.60, rest: 60,  rounds: 3, order: 2),
            uniformSet([plank], effort: 0.0, rest: 60, rounds: 3, order: 3, time: 60),
        ]
        context.insert(legsWorkout)

        // MARK: Full Body (Quick) — 3-round circuit
        let fullBody = Workout(name: "Full Body Express")
        fullBody.workoutDescription = "3-round circuit, 30 min"
        fullBody.estimatedDuration = 30
        fullBody.sets = [
            uniformSet([squat],     reps: 10, weight: 135, effort: 0.60, rest: 45, rounds: 3, order: 0),
            uniformSet([benchPress], reps: 10, weight: 115, effort: 0.60, rest: 45, rounds: 3, order: 1),
            uniformSet([bentRow],   reps: 10, weight: 95,  effort: 0.60, rest: 45, rounds: 3, order: 2),
            uniformSet([plank], effort: 0.0, rest: 60, rounds: 3, order: 3, time: 45),
        ]
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

    /// A block of `rounds` identical rounds over one or more exercises (superset when >1).
    private func uniformSet(
        _ exercises: [Exercise],
        reps: Int? = nil,
        weight: Double? = nil,
        effort: Double,
        rest: Int,
        rounds: Int,
        order: Int,
        time: Int? = nil
    ) -> WorkoutSet {
        let slots: [ExerciseInSet] = exercises.enumerated().map { i, ex in
            let s = ExerciseInSet(exercise: ex, isTimeBased: time != nil, order: i)
            context.insert(s)
            return s
        }
        let setRounds: [SetRound] = (0..<rounds).map { rIndex in
            let targets: [ExerciseTarget] = slots.map { slot in
                let t = ExerciseTarget(
                    order: slot.order,
                    exerciseName: slot.exerciseName,
                    targetReps: time != nil ? nil : reps,
                    targetTime: time,
                    targetWeight: weight,
                    effortLevel: effort
                )
                context.insert(t)
                return t
            }
            let round = SetRound(order: rIndex, restSeconds: rest, targets: targets)
            context.insert(round)
            return round
        }
        let set = WorkoutSet(exercises: slots, rounds: setRounds, order: order)
        context.insert(set)
        return set
    }

    /// A single-exercise block whose rounds vary in reps/weight/effort/rest.
    private func variableSet(
        _ exercise: Exercise,
        order: Int,
        rounds specs: [(reps: Int, weight: Double, effort: Double, rest: Int)]
    ) -> WorkoutSet {
        let slot = ExerciseInSet(exercise: exercise, isTimeBased: false, order: 0)
        context.insert(slot)
        let setRounds: [SetRound] = specs.enumerated().map { rIndex, spec in
            let t = ExerciseTarget(
                order: 0,
                exerciseName: exercise.name,
                targetReps: spec.reps,
                targetTime: nil,
                targetWeight: spec.weight,
                effortLevel: spec.effort
            )
            context.insert(t)
            let round = SetRound(order: rIndex, restSeconds: spec.rest, targets: [t])
            context.insert(round)
            return round
        }
        let set = WorkoutSet(exercises: [slot], rounds: setRounds, order: order)
        context.insert(set)
        return set
    }
}
