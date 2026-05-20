import Foundation
import SwiftData

// MARK: - WorkoutDataManager
// All write operations go through here so we have a single, consistent
// place to add validation, logging, or future cloud sync hooks.

@MainActor
final class WorkoutDataManager {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Exercises

    func createExercise(name: String, muscleGroup: MuscleGroup, equipment: String = "") -> Exercise {
        let exercise = Exercise(name: name, muscleGroup: muscleGroup, equipment: equipment)
        context.insert(exercise)
        save()
        return exercise
    }

    func deleteExercise(_ exercise: Exercise) {
        context.delete(exercise)
        save()
    }

    func fetchAllExercises() throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor)
    }

    // MARK: - Workouts

    func createWorkout(name: String, sets: [WorkoutSet] = [], setRepetitions: Int = 1) -> Workout {
        let workout = Workout(name: name, sets: sets, setRepetitions: setRepetitions)
        context.insert(workout)
        save()
        return workout
    }

    func deleteWorkout(_ workout: Workout) {
        context.delete(workout)
        save()
    }

    func fetchAllWorkouts() throws -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.createdDate, order: .reverse)])
        return try context.fetch(descriptor)
    }

    // MARK: - Programs

    func createProgram(name: String, weeks: [ProgramWeek] = [], goal: TrainingGoal, difficulty: DifficultyLevel = .intermediate) -> Program {
        let program = Program(name: name, weeks: weeks, targetGoal: goal, difficultyLevel: difficulty)
        context.insert(program)
        save()
        return program
    }

    func deleteProgram(_ program: Program) {
        context.delete(program)
        save()
    }

    // MARK: - Workout Logs

    /// Call when a workout is complete to persist the full log.
    func saveWorkoutLog(
        workout: Workout,
        startDate: Date,
        durationSeconds: Int,
        setLogs: [WorkoutSetLog],
        notes: String = ""
    ) -> WorkoutLog {
        let log = WorkoutLog(workout: workout, startDate: startDate)
        log.completedDate = Date()
        log.durationSeconds = durationSeconds
        log.setLogs = setLogs
        log.notes = notes
        log.isComplete = true
        context.insert(log)
        save()
        return log
    }

    func fetchRecentWorkoutLogs(limit: Int = 20) throws -> [WorkoutLog] {
        var descriptor = FetchDescriptor<WorkoutLog>(
            predicate: #Predicate { $0.isComplete == true },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func fetchLogs(for workout: Workout) throws -> [WorkoutLog] {
        let workoutID = workout.id
        let descriptor = FetchDescriptor<WorkoutLog>(
            predicate: #Predicate { $0.workoutName == workoutID },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - User Profile

    func fetchOrCreateUserProfile(email: String) throws -> UserProfile {
        let descriptor = FetchDescriptor<UserProfile>()
        let all = try context.fetch(descriptor)
        if let existing = all.first { return existing }
        let profile = UserProfile(email: email, name: "")
        context.insert(profile)
        save()
        return profile
    }

    // MARK: - Persistence

    @discardableResult
    func save() -> Error? {
        do {
            try context.save()
            return nil
        } catch {
            return error
        }
    }
}
