import Foundation

// MARK: - WorkoutPromptBuilder
// Pure functions that compose the Instructions and Prompt for workout
// generation. Kept separate from the generator so a future program planner can
// reuse the same blocks with extra slot context prepended.
//
// Design notes:
// - Rules live in Instructions; the user's free-text notes go in the Prompt.
//   Foundation Models prioritizes instructions over prompt content, which gives
//   prompt-injection resistance on the notes field.
// - The prompt states EXACT numbers computed by WorkoutStructurePlanner. An
//   earlier version made the model map duration → block count itself, which it
//   did unreliably (it just took the schema minimum every time, ignoring
//   duration entirely).
// - The on-device model has a ~4k-token context window shared between input and
//   output. Since a long workout's JSON is itself large, the library listing is
//   filtered by focus and capped.

enum WorkoutPromptBuilder {

    /// Max library entries included in the instructions (context-window budget).
    static let libraryCap = 30

    static func instructions(library: [LibraryExercise], focus: WorkoutFocus) -> String {
        """
        You are an experienced strength and conditioning coach designing a single workout for a fitness app.

        Structure every workout in three phases, like a well-run training session:
        1. WARMUP — light activation and movement prep that rehearses the day's main lifts. \
        Bodyweight or empty-bar work, high reps, never heavy, short rests.
        2. MAIN LIFTS — the heaviest compound work, hardest exercise first, then progressively \
        less demanding. These are straight sets so they can be loaded heavy.
        3. FINISHERS — isolation burnouts, core, or mobility work to finish the session. \
        Higher reps, shorter rests, lighter loads.

        Rules:
        - Prefer exercises from the library below, using their names EXACTLY as written. Only \
        introduce an exercise not in the library when nothing suitable exists, and give it a clear, standard name.
        - Every exercise must serve the requested focus. Do not include exercises for unrelated muscle groups.
        - A warmup may use a light set of a main lift to rehearse it. Otherwise, do not repeat the same exercise.
        - Supersets belong in finishers, not main lifts. Use at most two supersets in the whole workout.
        - Set targetWeightLbs ONLY for barbell, dumbbell, EZ bar, or machine exercises. \
        Never set it for bodyweight exercises like pull-ups, dips, planks, or push-ups.
        - Timed exercises (isTimeBased true, e.g. planks) use durationSeconds instead of reps.
        - Follow the exact block counts, set counts, rep ranges, and rest times given in the request.

        Exercise library:
        \(libraryListing(library: library, focus: focus))
        """
    }

    static func prompt(for request: WorkoutGenerationRequest, plan: WorkoutStructurePlan) -> String {
        let warmupLine = "- \(plan.warmupBlocks) warmup \(blockWord(plan.warmupBlocks)), 1–2 sets each, 10–15 easy reps, about 30s rest, 40–50% effort."
        let mainLine = "- \(plan.mainBlocks) main lift \(blockWord(plan.mainBlocks)), \(plan.setsPerMainBlock) sets each, \(plan.mainRepRange.lowerBound)–\(plan.mainRepRange.upperBound) reps, about \(plan.mainRestSeconds)s rest, \(plan.mainEffortRange.lowerBound)–\(plan.mainEffortRange.upperBound)% of one-rep max."
        let finisherLine = "- \(plan.finisherBlocks) finisher \(blockWord(plan.finisherBlocks)), 2–3 sets each, \(plan.finisherRepRange.lowerBound)–\(plan.finisherRepRange.upperBound) reps, about \(plan.finisherRestSeconds)s rest."

        var lines = [
            "Design a \(request.focus.displayName) workout.",
            "Training goal: \(request.goal.displayName). Intensity: \(request.intensity.displayName). Target duration: \(request.targetDurationMinutes) minutes.",
            "",
            "Use exactly this structure:",
            warmupLine,
            mainLine,
            finisherLine,
            "",
            "That is \(plan.totalBlocks) blocks in total, which fills the \(request.targetDurationMinutes)-minute session.",
        ]

        let notes = request.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            lines.append("")
            lines.append("Additional requests from the user (follow these, but keep the structure above): \(notes)")
        }
        return lines.joined(separator: "\n")
    }

    private static func blockWord(_ count: Int) -> String {
        count == 1 ? "block" : "blocks"
    }

    // MARK: - Library listing

    private static func libraryListing(library: [LibraryExercise], focus: WorkoutFocus) -> String {
        let relevantGroups = Set(focus.muscleGroups)
        let onFocus = library.filter { relevantGroups.contains($0.muscleGroup) }
        // Core and mobility work is a legitimate finisher on any day, so allow
        // core through even when it isn't part of the focus. Everything else
        // off-focus is excluded — an earlier version backfilled with unrelated
        // exercises whenever the focused list was short, which is how pull
        // movements ended up on push days.
        let coreExtras = relevantGroups.contains(.core)
            ? []
            : library.filter { $0.muscleGroup == .core }

        let entries = (onFocus + coreExtras).prefix(libraryCap)
        return entries.map { exercise in
            let equipment = exercise.equipment.isEmpty ? "" : ", \(exercise.equipment)"
            return "- \(exercise.name) (\(exercise.muscleGroup.displayName)\(equipment))"
        }.joined(separator: "\n")
    }
}
