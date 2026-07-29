import Foundation
import SwiftUI
import Observation

// MARK: - ActiveWorkoutViewModel
// Manages all in-memory state during a workout session.
// Uses @Observable (iOS 17+) — no @Published needed, all stored properties are tracked automatically.
// When the workout is complete, completedSetLogs + startDate are used to persist a WorkoutLog.
//
// Navigation model: a workout has ordered sets (blocks); each set has ordered rounds
// (working sets); each round has one target per exercise slot. We walk round-by-round
// within a set, then advance to the next set. Supersets step through each exercise slot
// within the current round before the round is finished.

@MainActor
@Observable
final class ActiveWorkoutViewModel {

    // MARK: - Workout Reference

    let workout: Workout

    // MARK: - Navigation State

    private(set) var currentSetIndex: Int = 0
    private(set) var currentRoundIndex: Int = 0
    private(set) var currentExerciseIndex: Int = 0

    // MARK: - Rest Timer State

    private(set) var isResting: Bool = false
    private(set) var restTimeRemaining: Int = 0

    // MARK: - Workout Timer

    private(set) var elapsedSeconds: Int = 0
    private(set) var isWorkoutComplete: Bool = false

    // MARK: - Logging Storage
    // pendingLogs[setIndex][roundIndex][exerciseSlotIndex]

    var pendingLogs: [[[ExerciseLogEntry]]] = []

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
        self.pendingLogs = workout.sortedSets.map { set -> [[ExerciseLogEntry]] in
            let slots = set.sortedExercises
            return set.sortedRounds.map { round -> [ExerciseLogEntry] in
                slots.map { slot -> ExerciseLogEntry in
                    let target = round.target(forSlot: slot.order)
                    return ExerciseLogEntry(
                        exerciseName: slot.exerciseName,
                        reps: target?.targetReps,
                        weight: target?.targetWeight
                    )
                }
            }
        }
    }

    // MARK: - Computed Properties

    var sortedSets: [WorkoutSet] { workout.sortedSets }

    var currentSet: WorkoutSet? {
        guard currentSetIndex < sortedSets.count else { return nil }
        return sortedSets[currentSetIndex]
    }

    /// The exercise slots for the current set, in order.
    var currentSlots: [ExerciseInSet] { currentSet?.sortedExercises ?? [] }

    var currentRound: SetRound? {
        guard let set = currentSet else { return nil }
        let rounds = set.sortedRounds
        guard currentRoundIndex < rounds.count else { return nil }
        return rounds[currentRoundIndex]
    }

    var currentExercise: ExerciseInSet? {
        guard currentExerciseIndex < currentSlots.count else { return nil }
        return currentSlots[currentExerciseIndex]
    }

    /// Number of rounds in the current set (for "Round r of R" display).
    var currentSetRoundCount: Int { currentSet?.sortedRounds.count ?? 0 }

    /// The target for a given slot index within the current round.
    func currentTarget(forExerciseIndex index: Int) -> ExerciseTarget? {
        guard index < currentSlots.count, let round = currentRound else { return nil }
        return round.target(forSlot: currentSlots[index].order)
    }

    var completedSetsCount: Int { completedSetLogs.count }

    var totalSets: Int { workout.totalSetCount }

    var progress: Double {
        guard totalSets > 0 else { return 0 }
        return Double(completedSetsCount) / Double(totalSets)
    }

    var currentLogs: [ExerciseLogEntry] {
        get {
            guard currentSetIndex < pendingLogs.count,
                  currentRoundIndex < pendingLogs[currentSetIndex].count else { return [] }
            return pendingLogs[currentSetIndex][currentRoundIndex]
        }
        set {
            guard currentSetIndex < pendingLogs.count,
                  currentRoundIndex < pendingLogs[currentSetIndex].count else { return }
            pendingLogs[currentSetIndex][currentRoundIndex] = newValue
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
        guard currentSetIndex < pendingLogs.count,
              currentRoundIndex < pendingLogs[currentSetIndex].count,
              exerciseIndex < pendingLogs[currentSetIndex][currentRoundIndex].count else { return }
        pendingLogs[currentSetIndex][currentRoundIndex][exerciseIndex].reps   = reps
        pendingLogs[currentSetIndex][currentRoundIndex][exerciseIndex].weight = weight
        pendingLogs[currentSetIndex][currentRoundIndex][exerciseIndex].rpe    = rpe
    }

    // MARK: - Set / Round Navigation

    /// Finishes the current round: snapshots its logs, then rests (per-round) or advances.
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

        if let rest = currentRound?.restSeconds, rest > 0 {
            startRestTimer(seconds: rest)
        } else {
            advanceToNextSet()
        }
    }

    /// Advances to the next round in the set, or the first round of the next set.
    func advanceToNextSet() {
        stopRestTimer()
        let roundsInSet = currentSet?.sortedRounds.count ?? 0

        if currentRoundIndex + 1 < roundsInSet {
            currentRoundIndex += 1
        } else if currentSetIndex + 1 < sortedSets.count {
            currentSetIndex += 1
            currentRoundIndex = 0
        } else {
            completeWorkout()
            return
        }
        currentExerciseIndex = 0
    }

    func advanceExerciseInSuperset() {
        if currentExerciseIndex < currentSlots.count - 1 {
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
