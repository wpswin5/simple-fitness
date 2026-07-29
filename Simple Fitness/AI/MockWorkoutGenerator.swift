import Foundation

#if DEBUG
// MARK: - MockWorkoutGenerator
// Deterministic stand-in for the on-device model. Used by SwiftUI previews,
// for driving the full generation flow where Apple Intelligence is unavailable,
// and later as the stub for generation-quality eval harnesses.
//
// It honours the structure plan (block counts scale with duration) so the mock
// exercises the same mapper paths the live model does.

struct MockWorkoutGenerator: WorkoutGenerating {
    var delay: Duration = .seconds(1.5)

    func generate(_ request: WorkoutGenerationRequest, library: [LibraryExercise]) async throws -> GeneratedWorkout {
        try await Task.sleep(for: delay)

        let plan = WorkoutStructurePlanner.plan(for: request)

        let warmupPool = [
            ("Push-Up", "chest"), ("Band Pull-Apart", "shoulders"),
        ]
        let mainPool = [
            ("Bench Press", "chest"), ("Overhead Press", "shoulders"),
            ("Incline DB Press", "chest"), ("Back Squat", "quadriceps"),
            ("Bent-Over Row", "back"), ("Romanian Deadlift", "hamstrings"),
        ]

        // Warmup: light, straight sets.
        let warmup = (0..<plan.warmupBlocks).map { i -> GeneratedWarmupBlock in
            let (name, group) = warmupPool[i % warmupPool.count]
            return GeneratedWarmupBlock(
                exercise: GeneratedExerciseSlot(exerciseName: name, muscleGroup: group, isTimeBased: false),
                sets: (0..<2).map { _ in
                    GeneratedRound(
                        target: GeneratedTarget(reps: 12, durationSeconds: nil, targetWeightLbs: nil, effortPercent: 45),
                        partnerTarget: nil,
                        restSeconds: 30
                    )
                }
            )
        }

        // Main lifts: straight sets with an ascending-weight progression.
        let main = (0..<plan.mainBlocks).map { i -> GeneratedMainBlock in
            let (name, group) = mainPool[i % mainPool.count]
            let baseWeight = 135.0 - Double(i * 20)
            return GeneratedMainBlock(
                exercise: GeneratedExerciseSlot(exerciseName: name, muscleGroup: group, isTimeBased: false),
                supersetPartner: nil,
                sets: (0..<plan.setsPerMainBlock).map { s in
                    GeneratedRound(
                        target: GeneratedTarget(
                            reps: max(plan.mainRepRange.lowerBound, plan.mainRepRange.upperBound - s * 2),
                            durationSeconds: nil,
                            targetWeightLbs: baseWeight + Double(s * 10),
                            effortPercent: min(plan.mainEffortRange.upperBound, plan.mainEffortRange.lowerBound + s * 5)
                        ),
                        partnerTarget: nil,
                        restSeconds: plan.mainRestSeconds
                    )
                }
            )
        }

        // Finishers: a superset, then a timed core hold.
        var finishers: [GeneratedFinisherBlock] = [
            GeneratedFinisherBlock(
                exercise: GeneratedExerciseSlot(exerciseName: "Lateral Raise", muscleGroup: "shoulders", isTimeBased: false),
                supersetPartner: GeneratedExerciseSlot(exerciseName: "Tricep Dip", muscleGroup: "triceps", isTimeBased: false),
                sets: (0..<2).map { _ in
                    GeneratedRound(
                        target: GeneratedTarget(reps: plan.finisherRepRange.lowerBound, durationSeconds: nil, targetWeightLbs: 20, effortPercent: 60),
                        partnerTarget: GeneratedTarget(reps: plan.finisherRepRange.lowerBound, durationSeconds: nil, targetWeightLbs: nil, effortPercent: 60),
                        restSeconds: plan.finisherRestSeconds
                    )
                }
            )
        ]
        if plan.finisherBlocks > 1 {
            finishers.append(
                GeneratedFinisherBlock(
                    exercise: GeneratedExerciseSlot(exerciseName: "Plank", muscleGroup: "core", isTimeBased: true),
                    supersetPartner: nil,
                    sets: (0..<2).map { s in
                        GeneratedRound(
                            target: GeneratedTarget(reps: nil, durationSeconds: 45 + s * 15, targetWeightLbs: nil, effortPercent: 60),
                            partnerTarget: nil,
                            restSeconds: plan.finisherRestSeconds
                        )
                    }
                )
            )
        }
        if plan.finisherBlocks > 2 {
            finishers.append(
                GeneratedFinisherBlock(
                    exercise: GeneratedExerciseSlot(exerciseName: "Cable Fly", muscleGroup: "chest", isTimeBased: false),
                    supersetPartner: nil,
                    sets: (0..<2).map { _ in
                        GeneratedRound(
                            target: GeneratedTarget(reps: plan.finisherRepRange.upperBound, durationSeconds: nil, targetWeightLbs: 30, effortPercent: 55),
                            partnerTarget: nil,
                            restSeconds: plan.finisherRestSeconds
                        )
                    }
                )
            )
        }

        return GeneratedWorkout(
            name: "Sample \(request.focus.displayName)",
            summary: "Mock \(request.focus.displayName) workout (\(request.intensity.displayName), ~\(request.targetDurationMinutes) min, \(plan.totalBlocks) blocks).",
            warmup: warmup,
            mainLifts: main,
            finishers: finishers
        )
    }
}
#endif
