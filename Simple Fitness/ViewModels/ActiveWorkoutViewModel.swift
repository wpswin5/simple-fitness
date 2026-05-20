import Foundation
import SwiftUI
import Observation

// MARK: - ActiveWorkoutViewModel
// Manages all in-memory state during a workout session.
// Uses @Observable (iOS 17+) — no @Published needed, all stored properties are tracked automatically.
// When the workout is complete, completedSetLogs + startDate are used to persist a WorkoutLog.

@MainActor
@Observable
final class ActiveWorkoutViewModel {

    // MARK: - Workout Reference

    let workout: Workout

    // MARK: - Navigation State

    private(set) var currentSetIndex: Int = 0
    private(set) var currentRepetition: Int = 1   // which round (when setRepetitions > 1)
    private(set) var currentExerciseIndex: Int = 0

    // MARK: - Rest Timer State

    private(set) var isResting: Bool = false
    private(set) var restTimeRemaining: Int = 0

    // MARK: - Workout Timer

    private(set) var elapsedSeconds: Int = 0
    private(set) var isWorkoutComplete: Bool = false

    // MARK: - Logging Storage
    // Outer array indexed by absolute set index (repetition * sets + setIndex)
    // Inner array indexed by exercise-in-set index

    var pendingLogs: [[ExerciseLogEntry]] = []

    // Holds confirmed set logs until the workout is saved
    private(set) var completedSetLogs: [WorkoutSetLog] = []

    // MARK: - Timers (nonisolated(unsafe) so deinit can invalidate them safely)

    nonisolated(unsafe) private var restTimer: Timer?
    nonisolated(unsafe) private var workoutTimer: Timer?

    // MARK: - Start Date

    private(set) var startDate: Date = Date()

    // MARK: - Init

    init(workout: Workout) {
        self.workout = workout
        let totalSets = workout.sortedSets.count * workout.setRepetitions
        self.pendingLogs = (0..<totalSets).map { i in
            let setIndex = i % workout.sortedSets.count
            let set = workout.sortedSets[setIndex]
            return set.exercises.map { ex in
                ExerciseLogEntry(exerciseName: ex.exerciseName, reps: ex.targetReps)
            }
        }
    }

    // MARK: - Computed Properties

    var sortedSets: [WorkoutSet] { workout.sortedSets }

    var currentSet: WorkoutSet? {
        guard currentSetIndex < sortedSets.count else { return nil }
        return sortedSets[currentSetIndex]
    }

    var currentExercise: ExerciseInSet? {
        guard let set = currentSet, currentExerciseIndex < set.exercises.count else { return nil }
        return set.exercises[currentExerciseIndex]
    }

    var completedSetsCount: Int { completedSetLogs.count }

    var totalSets: Int { workout.sortedSets.count * workout.setRepetitions }

    var progress: Double {
        guard totalSets > 0 else { return 0 }
        return Double(completedSetsCount) / Double(totalSets)
    }

    var absoluteSetIndex: Int {
        (currentRepetition - 1) * sortedSets.count + currentSetIndex
    }

    var currentLogs: [ExerciseLogEntry] {
        get {
            guard absoluteSetIndex < pendingLogs.count else { return [] }
            return pendingLogs[absoluteSetIndex]
        }
        set {
            guard absoluteSetIndex < pendingLogs.count else { return }
            pendingLogs[absoluteSetIndex] = newValue
        }
    }

    // MARK: - Workout Lifecycle

    func startWorkout() {
        startDate = Date()
        startWorkoutTimer()
    }

    func completeWorkout() {
        stopRestTimer()
        stopWorkoutTimer()
        isWorkoutComplete = true
    }

    // MARK: - Log Update

    func updateLog(exerciseIndex: Int, reps: Int?, weight: Double?, rpe: Double?) {
        guard absoluteSetIndex < pendingLogs.count,
              exerciseIndex < pendingLogs[absoluteSetIndex].count else { return }
        pendingLogs[absoluteSetIndex][exerciseIndex].reps   = reps
        pendingLogs[absoluteSetIndex][exerciseIndex].weight = weight
        pendingLogs[absoluteSetIndex][exerciseIndex].rpe    = rpe
    }

    // MARK: - Set Navigation

    func finishCurrentSet() {
        let logs = currentLogs.map { entry in
            ExerciseLog(
                exerciseName: entry.exerciseName,
                reps: entry.reps,
                weight: entry.weight,
                rpe: entry.rpe
            )
        }
        let setLog = WorkoutSetLog(setOrder: completedSetsCount, exerciseLogs: logs)
        completedSetLogs.append(setLog)
        currentExerciseIndex = 0

        if let rest = currentSet?.restSeconds, rest > 0 {
            startRestTimer(seconds: rest)
        } else {
            advanceToNextSet()
        }
    }

    func advanceToNextSet() {
        stopRestTimer()
        let nextSetIndex = currentSetIndex + 1

        if nextSetIndex < sortedSets.count {
            currentSetIndex = nextSetIndex
        } else if currentRepetition < workout.setRepetitions {
            currentRepetition += 1
            currentSetIndex = 0
        } else {
            completeWorkout()
            return
        }
        currentExerciseIndex = 0
    }

    func advanceExerciseInSuperset() {
        guard let set = currentSet else { return }
        if currentExerciseIndex < set.exercises.count - 1 {
            currentExerciseIndex += 1
        } else {
            finishCurrentSet()
        }
    }

    // MARK: - Rest Timer

    func startRestTimer(seconds: Int) {
        restTimeRemaining = seconds
        isResting = true
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.restTimeRemaining > 1 {
                    self.restTimeRemaining -= 1
                } else {
                    self.stopRestTimer()
                    self.advanceToNextSet()
                }
            }
        }
    }

    func skipRest() {
        stopRestTimer()
        advanceToNextSet()
    }

    private func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        isResting = false
        restTimeRemaining = 0
    }

    // MARK: - Workout Timer

    private func startWorkoutTimer() {
        elapsedSeconds = 0
        workoutTimer?.invalidate()
        workoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.elapsedSeconds += 1
            }
        }
    }

    private func stopWorkoutTimer() {
        workoutTimer?.invalidate()
        workoutTimer = nil
    }

    deinit {
        restTimer?.invalidate()
        workoutTimer?.invalidate()
    }
}
