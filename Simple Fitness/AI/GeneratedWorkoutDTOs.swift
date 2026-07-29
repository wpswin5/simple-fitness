import Foundation
import FoundationModels

// MARK: - Generated Workout DTOs
// @Generable types the language model fills in via guided generation.
//
// Design notes (learned from the first live runs):
// - Phases are SEPARATE ARRAYS, not a free-for-all block list. The model
//   cannot skip the warmup or the finisher because the schema requires them,
//   which is what gives every workout the warmup → main → finisher shape.
// - Each phase has its own block type purely so its `sets` count can be guided
//   differently (a warmup set and a heavy main set are not the same thing).
// - A superset is an OPTIONAL PARTNER, not an `exercises` array with a max of
//   2. The earlier array shape invited the model to fill it every time, making
//   every block a superset; an optional field makes supersetting an
//   affirmative choice, which it should be.
// - The .count ranges here are the hard ceiling on what WorkoutStructurePlanner
//   can ask for — keep the two in sync.

@Generable(description: "A complete strength workout, ordered warmup → main lifts → finishers")
struct GeneratedWorkout: Sendable {
    @Guide(description: "Short, motivating workout name, 2–4 words. No quotes.")
    var name: String

    @Guide(description: "One-sentence description of the workout's focus and structure")
    var summary: String

    @Guide(description: "Warmup blocks: light activation and movement prep that rehearses the day's main lifts", .count(1...2))
    var warmup: [GeneratedWarmupBlock]

    @Guide(description: "Main lifts: the heaviest compound work, hardest exercise first", .count(2...6))
    var mainLifts: [GeneratedMainBlock]

    @Guide(description: "Finishers: isolation burnouts, core, or mobility work to end the session", .count(1...3))
    var finishers: [GeneratedFinisherBlock]
}

@Generable(description: "A warmup block: one light exercise for a couple of easy sets")
struct GeneratedWarmupBlock: Sendable {
    var exercise: GeneratedExerciseSlot

    @Guide(description: "1–2 light, high-rep sets. Never heavy.", .count(1...2))
    var sets: [GeneratedRound]
}

@Generable(description: "A main lift block: one compound exercise for several working sets")
struct GeneratedMainBlock: Sendable {
    var exercise: GeneratedExerciseSlot

    @Guide(description: "Almost always leave this out — main lifts should be straight sets so they can be loaded heavy. Only pair an antagonist exercise here if the user explicitly asked for supersets.")
    var supersetPartner: GeneratedExerciseSlot?

    @Guide(description: "The working sets. Vary reps and weight across sets when it fits the goal, for example ascending weight with descending reps.", .count(3...5))
    var sets: [GeneratedRound]
}

@Generable(description: "A finisher block: isolation, core, or mobility work at the end of the session")
struct GeneratedFinisherBlock: Sendable {
    var exercise: GeneratedExerciseSlot

    @Guide(description: "Optional second exercise to superset with. Supersets are a good fit for finishers.")
    var supersetPartner: GeneratedExerciseSlot?

    @Guide(description: "2–3 higher-rep sets with short rests", .count(2...3))
    var sets: [GeneratedRound]
}

@Generable(description: "One exercise")
struct GeneratedExerciseSlot: Sendable {
    @Guide(description: "Exercise name. Use a name from the provided library EXACTLY as written when a suitable one exists.")
    var exerciseName: String

    @Guide(description: "Primary muscle group this exercise trains", .anyOf(MuscleGroup.allCases.map(\.rawValue)))
    var muscleGroup: String

    @Guide(description: "True only for timed holds like planks, where duration replaces reps")
    var isTimeBased: Bool
}

@Generable(description: "One set within a block")
struct GeneratedRound: Sendable {
    @Guide(description: "The target for this block's main exercise")
    var target: GeneratedTarget

    @Guide(description: "The target for the superset partner. Include this only when the block has a superset partner.")
    var partnerTarget: GeneratedTarget?

    @Guide(description: "Rest in seconds after this set", .range(20...240))
    var restSeconds: Int
}

@Generable(description: "The target for one exercise in one set")
struct GeneratedTarget: Sendable {
    @Guide(description: "Target repetitions. Omit for timed exercises.", .range(1...30))
    var reps: Int?

    // Capped at 2 minutes: the model reliably takes the top of whatever range it
    // is given, and a 5-minute plank is not a real prescription.
    @Guide(description: "Target hold duration in seconds. Only for timed exercises like planks.", .range(10...120))
    var durationSeconds: Int?

    @Guide(description: "Target weight in pounds. Only for barbell, dumbbell, EZ bar, or machine exercises — always omit for bodyweight exercises.")
    var targetWeightLbs: Double?

    @Guide(description: "Effort as percent of one-rep max", .range(40...100))
    var effortPercent: Int
}
