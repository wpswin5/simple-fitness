import Foundation
import SwiftData

// MARK: - GeneratedWorkoutMapper
// Bridges model output (GeneratedWorkout DTOs) into the editor's draft types,
// flattening the three phases into ordered draft sets: warmup → main → finishers.
//
// Defensive by design. Live testing showed the on-device model treats the
// GENERATION SCHEMA as binding and the prompt's numbers as a suggestion — it
// would take the top of any .count/.range it was given and ignore the requested
// block/set counts, so duration barely moved the output. Everything we can
// check deterministically is therefore enforced here rather than asked for:
// - block counts per phase are trimmed to the WorkoutStructurePlan
// - main-lift set counts are trimmed/padded to the plan (this is what actually
//   makes duration drive the result)
// - weight is stripped from bodyweight exercises
// - supersets are capped, and dropped from main lifts before finishers
// - exercises are de-duplicated within the main lifts
// - numbers are clamped to sane ranges
// Outputs drafts, the same currency a future program planner will assemble.

struct MappedWorkout {
    var name: String
    var summary: String
    var sets: [DraftWorkoutSet]
    /// Exercises created because no library match existed. Tracked so the caller
    /// can delete any that end up unreferenced (e.g. user cancels the editor).
    var createdExercises: [Exercise]
}

@MainActor
enum GeneratedWorkoutMapper {

    /// Most supersets allowed in one workout (finishers get priority).
    private static let maxSupersets = 2

    static func map(
        _ generated: GeneratedWorkout,
        library: [Exercise],
        plan: WorkoutStructurePlan,
        context: ModelContext
    ) -> MappedWorkout {
        var resolver = ExerciseResolver(library: library, context: context)

        // Finishers are mapped first so they win the superset budget, then the
        // phases are re-ordered for the final workout.
        var supersetBudget = maxSupersets

        let finisherDrafts: [DraftWorkoutSet] = generated.finishers
            .prefix(plan.finisherBlocks)
            .compactMap { block in
                draftSet(
                    exercise: block.exercise,
                    partner: block.supersetPartner,
                    rounds: block.sets,
                    allowSuperset: consume(&supersetBudget, block.supersetPartner != nil),
                    setCount: nil,        // 2–3 sets is already tight enough
                    resolver: &resolver
                )
            }

        // Main lifts drive the session's length, so their block and set counts
        // are forced to the plan.
        var usedMainExerciseIDs: Set<String> = []
        let mainDrafts: [DraftWorkoutSet] = generated.mainLifts
            .compactMap { block -> DraftWorkoutSet? in
                guard let draft = draftSet(
                    exercise: block.exercise,
                    partner: block.supersetPartner,
                    rounds: block.sets,
                    allowSuperset: consume(&supersetBudget, block.supersetPartner != nil),
                    setCount: plan.setsPerMainBlock,
                    resolver: &resolver
                ) else { return nil }
                // Drop a main lift that repeats one already programmed.
                guard let primaryID = draft.exercises.first?.exercise.id,
                      !usedMainExerciseIDs.contains(primaryID) else { return nil }
                usedMainExerciseIDs.insert(primaryID)
                return draft
            }
            .prefix(plan.mainBlocks)
            .map { $0 }

        let warmupDrafts: [DraftWorkoutSet] = generated.warmup
            .prefix(plan.warmupBlocks)
            .compactMap { block in
                draftSet(
                    exercise: block.exercise,
                    partner: nil,         // warmups are always straight sets
                    rounds: block.sets,
                    allowSuperset: false,
                    setCount: nil,
                    resolver: &resolver
                )
            }

        let name = generated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return MappedWorkout(
            name: name.isEmpty ? "Generated Workout" : name,
            summary: generated.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            sets: warmupDrafts + mainDrafts + finisherDrafts,
            createdExercises: resolver.createdExercises
        )
    }

    /// Spends one unit of the superset budget if this block wants a partner.
    private static func consume(_ budget: inout Int, _ wantsSuperset: Bool) -> Bool {
        guard wantsSuperset, budget > 0 else { return false }
        budget -= 1
        return true
    }

    // MARK: - Block mapping

    /// - Parameter setCount: when non-nil, the block's sets are forced to exactly
    ///   this many — trimming extras, or padding by repeating the last set (which
    ///   is a legitimate prescription, and the only volume repair we can make
    ///   without inventing exercises).
    private static func draftSet(
        exercise: GeneratedExerciseSlot,
        partner: GeneratedExerciseSlot?,
        rounds: [GeneratedRound],
        allowSuperset: Bool,
        setCount: Int?,
        resolver: inout ExerciseResolver
    ) -> DraftWorkoutSet? {
        guard !rounds.isEmpty else { return nil }
        guard let primary = resolver.resolve(slot: exercise) else { return nil }

        var slots = [primary]
        let partnerSlot = allowSuperset ? partner.flatMap { resolver.resolve(slot: $0) } : nil
        // Guard against the model supersetting an exercise with itself.
        if let partnerSlot, partnerSlot.exercise.id != primary.exercise.id {
            slots.append(partnerSlot)
        }

        var draftRounds: [DraftRound] = rounds.map { round in
            var targets = [draftTarget(from: round.target, slot: slots[0])]
            if slots.count > 1 {
                // Fall back to the primary's target if the model omitted the partner's.
                targets.append(draftTarget(from: round.partnerTarget ?? round.target, slot: slots[1]))
            }
            return DraftRound(restSeconds: round.restSeconds.clamped(to: 15...300), targets: targets)
        }

        if let setCount, setCount > 0 {
            if draftRounds.count > setCount {
                draftRounds = Array(draftRounds.prefix(setCount))
            } else if let last = draftRounds.last {
                while draftRounds.count < setCount { draftRounds.append(last) }
            }
        }

        var draft = DraftWorkoutSet()
        draft.exercises = slots
        draft.rounds = draftRounds
        return draft
    }

    private static func draftTarget(from source: GeneratedTarget, slot: DraftExerciseInSet) -> DraftTarget {
        var target = DraftTarget()
        if slot.isTimeBased {
            target.targetTime = (source.durationSeconds ?? 30).clamped(to: 5...600)
            target.targetReps = nil
        } else {
            target.targetReps = (source.reps ?? 8).clamped(to: 1...50)
            target.targetTime = nil
        }

        // The model repeatedly assigns weight to bodyweight movements despite
        // being told not to; equipment is authoritative, so enforce it here.
        if isBodyweight(slot.exercise) {
            target.targetWeight = nil
        } else if let weight = source.targetWeightLbs, weight > 0 {
            target.targetWeight = min(weight, 2000)
        } else {
            target.targetWeight = nil
        }

        target.effortLevel = (Double(source.effortPercent) / 100.0).clamped(to: 0.4...1.0)
        return target
    }

    private static func isBodyweight(_ exercise: Exercise) -> Bool {
        exercise.equipment.localizedCaseInsensitiveContains("bodyweight")
    }

}

// MARK: - AI DTO adapter for the shared ExerciseResolver

private extension ExerciseResolver {
    /// Resolves a model-generated slot by unpacking it into the primitive resolve.
    mutating func resolve(slot: GeneratedExerciseSlot) -> DraftExerciseInSet? {
        resolve(
            name: slot.exerciseName,
            muscleGroup: MuscleGroup(rawValue: slot.muscleGroup),
            isTimeBased: slot.isTimeBased
        )
    }
}

// MARK: - Clamping

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
