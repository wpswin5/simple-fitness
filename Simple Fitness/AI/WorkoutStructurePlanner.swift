import Foundation

// MARK: - WorkoutStructurePlanner
// Decides a workout's SHAPE deterministically, in Swift, before the model is
// ever called: how many blocks per phase, how many sets, what rep range, how
// much rest. The model is then told these numbers explicitly rather than being
// asked to derive them — small on-device models are unreliable at that kind of
// lookup/arithmetic, and this keeps duration genuinely driving the output.
//
// Structure follows the shape common to mainstream strength programs:
//   warmup (light prep) → main lifts (heavy compounds) → finishers (isolation/core)
//
// A future program planner can reuse this per day-slot.

struct WorkoutStructurePlan: Sendable {
    var warmupBlocks: Int
    var mainBlocks: Int
    var finisherBlocks: Int

    var setsPerMainBlock: Int
    var mainRepRange: ClosedRange<Int>
    var mainRestSeconds: Int
    var mainEffortRange: ClosedRange<Int>

    var finisherRepRange: ClosedRange<Int>
    var finisherRestSeconds: Int

    var totalBlocks: Int { warmupBlocks + mainBlocks + finisherBlocks }
}

enum WorkoutStructurePlanner {

    // Schema bounds — these MUST stay in sync with the @Guide .count ranges in
    // GeneratedWorkoutDTOs, since the model physically cannot exceed them.
    static let warmupRange = 1...2
    static let mainRange = 2...6
    static let finisherRange = 1...3

    /// Rough seconds of work for one set of one exercise (matches the estimate
    /// heuristic in CreateWorkoutViewModel).
    private static let workSecondsPerSet = 45

    static func plan(for request: WorkoutGenerationRequest) -> WorkoutStructurePlan {
        let goal = goalProfile(request.goal)
        let restScale = intensityRestScale(request.intensity)
        let mainRest = Int((Double(goal.restSeconds) * restScale).rounded())

        // Phase counts that don't depend on the time budget.
        let warmupBlocks = request.targetDurationMinutes <= 30 ? 1 : 2
        let finisherBlocks: Int
        switch request.targetDurationMinutes {
        case ..<35:  finisherBlocks = 1
        case ..<75:  finisherBlocks = 2
        default:     finisherBlocks = 3
        }

        // Time model: budget out warmup + finishers, spend the remainder on main work.
        let warmupSeconds = warmupBlocks * 2 * (30 + 30)              // ~2 easy sets each
        let finisherSeconds = finisherBlocks * 2 * (40 + goal.finisherRest)
        let mainSecondsPerBlock = goal.sets * (workSecondsPerSet + mainRest)

        let available = (request.targetDurationMinutes * 60) - warmupSeconds - finisherSeconds
        let rawMainBlocks = Double(available) / Double(max(mainSecondsPerBlock, 1))
        let mainBlocks = Int(rawMainBlocks.rounded()).clamped(to: mainRange)

        return WorkoutStructurePlan(
            warmupBlocks: warmupBlocks.clamped(to: warmupRange),
            mainBlocks: mainBlocks,
            finisherBlocks: finisherBlocks.clamped(to: finisherRange),
            setsPerMainBlock: goal.sets,
            mainRepRange: goal.reps,
            mainRestSeconds: mainRest,
            mainEffortRange: request.intensity.effortPercentRange,
            finisherRepRange: goal.finisherReps,
            finisherRestSeconds: goal.finisherRest
        )
    }

    // MARK: - Goal profiles
    // Set/rep/rest schemes drawn from the conventions of mainstream programs
    // (low-rep heavy work for strength, moderate-rep volume for hypertrophy, etc).

    private struct GoalProfile {
        var sets: Int
        var reps: ClosedRange<Int>
        var restSeconds: Int
        var finisherReps: ClosedRange<Int>
        var finisherRest: Int
    }

    private static func goalProfile(_ goal: TrainingGoal) -> GoalProfile {
        switch goal {
        case .strengthGain:
            return GoalProfile(sets: 5, reps: 3...6, restSeconds: 150, finisherReps: 8...12, finisherRest: 60)
        case .hypertrophy:
            return GoalProfile(sets: 4, reps: 8...12, restSeconds: 90, finisherReps: 12...15, finisherRest: 45)
        case .endurance:
            return GoalProfile(sets: 3, reps: 15...20, restSeconds: 45, finisherReps: 15...25, finisherRest: 30)
        case .athleticism:
            return GoalProfile(sets: 4, reps: 5...8, restSeconds: 120, finisherReps: 10...15, finisherRest: 45)
        case .weightLoss:
            return GoalProfile(sets: 3, reps: 12...15, restSeconds: 45, finisherReps: 15...20, finisherRest: 30)
        case .conditioning:
            return GoalProfile(sets: 3, reps: 12...20, restSeconds: 40, finisherReps: 15...20, finisherRest: 30)
        }
    }

    /// Higher intensity → heavier loads → longer rests.
    private static func intensityRestScale(_ intensity: WorkoutIntensity) -> Double {
        switch intensity {
        case .light:     return 0.7
        case .moderate:  return 1.0
        case .hard:      return 1.25
        case .maxEffort: return 1.5
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
