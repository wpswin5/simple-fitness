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

/// Snapshot of the next set to be worked, shown on the rest screen.
struct NextUpInfo: Equatable {
    var label: String
    var title: String
    var detail: String
    var isSuperset: Bool
}

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

    // Single 0.5s UI ticker; actual time comes from the wall clock so backgrounding
    // or locking the phone never freezes the elapsed/rest counters.
    nonisolated(unsafe) private var ticker: Timer?
    private var restEndDate: Date?

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

    /// Global 0-based index of a (set, round) across the whole workout — used to
    /// mark rounds as completed/current/upcoming in the overview.
    func globalRoundIndex(setIndex: Int, roundIndex: Int) -> Int {
        var idx = 0
        for i in 0..<setIndex where i < sortedSets.count {
            idx += sortedSets[i].sortedRounds.count
        }
        return idx + roundIndex
    }

    /// The set/round that will be worked next (used on the rest screen).
    /// nil when the current round is the last in the workout.
    var nextUp: NextUpInfo? {
        let roundsInSet = currentSet?.sortedRounds.count ?? 0
        var setIdx = currentSetIndex
        var roundIdx = currentRoundIndex
        if roundIdx + 1 < roundsInSet {
            roundIdx += 1
        } else if setIdx + 1 < sortedSets.count {
            setIdx += 1
            roundIdx = 0
        } else {
            return nil
        }
        guard setIdx < sortedSets.count else { return nil }
        let set = sortedSets[setIdx]
        let slots = set.sortedExercises
        guard roundIdx < set.sortedRounds.count else { return nil }
        let round = set.sortedRounds[roundIdx]
        let title = slots.map { $0.exerciseName }.joined(separator: " + ")
        let detail = slots.first.flatMap { round.target(forSlot: $0.order)?.displaySummary } ?? ""
        // completedSetsCount was already incremented when the current round finished.
        return NextUpInfo(
            label: "Set \(completedSetsCount + 1) of \(totalSets)",
            title: title,
            detail: detail,
            isSuperset: set.isSuperset
        )
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
        elapsedSeconds = 0
        RestNotifier.requestAuthorizationIfNeeded()
        startTicker()
    }

    func completeWorkout() {
        RestNotifier.cancel()
        RestActivityController.end()
        stopTicker()
        isResting = false
        restEndDate = nil
        isWorkoutComplete = true
    }

    /// Recompute elapsed + rest from the wall clock. Called every tick and when the
    /// app returns to the foreground, so backgrounding/locking never loses time.
    func refresh() {
        guard !isWorkoutComplete else { return }
        elapsedSeconds = max(0, Int(Date().timeIntervalSince(startDate)))
        if isResting, let end = restEndDate {
            let remaining = end.timeIntervalSinceNow
            if remaining <= 0 {
                finishResting()
            } else {
                restTimeRemaining = Int(remaining.rounded(.up))
            }
        }
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

    // MARK: - Rest (wall-clock)

    func startRestTimer(seconds: Int) {
        let end = Date().addingTimeInterval(TimeInterval(seconds))
        restEndDate = end
        restTimeRemaining = seconds
        isResting = true
        RestNotifier.scheduleRestOver(at: end)
        let next = nextUp
        RestActivityController.start(
            workoutName: workout.name,
            endDate: end,
            nextUpLabel: next?.label ?? "",
            nextUpTitle: next?.title ?? "Next set"
        )
    }

    func skipRest() {
        RestNotifier.cancel()
        finishResting()
    }

    /// Ends rest and advances. Called on skip and when the rest interval elapses.
    private func finishResting() {
        RestNotifier.cancel()
        RestActivityController.end()
        restEndDate = nil
        isResting = false
        restTimeRemaining = 0
        advanceToNextSet()
    }

    // MARK: - Ticker

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    deinit {
        ticker?.invalidate()
        RestNotifier.cancel()
        RestActivityController.end()
    }
}
