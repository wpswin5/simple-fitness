import Foundation
import FoundationModels

// MARK: - FoundationModelWorkoutGenerator
// Live WorkoutGenerating implementation backed by the on-device Apple
// Foundation Model. Stateless: a fresh session per generation, no transcript
// carried between requests. All output shaping is delegated to guided
// generation (GeneratedWorkout's @Generable schema).

struct FoundationModelWorkoutGenerator: WorkoutGenerating {

    func generate(_ request: WorkoutGenerationRequest, library: [LibraryExercise]) async throws -> GeneratedWorkout {
        guard GenerationAvailability.current == .available else {
            throw WorkoutGenerationError.modelUnavailable
        }

        // The workout's shape is decided in Swift, then handed to the model as
        // explicit numbers — see WorkoutStructurePlanner.
        let plan = WorkoutStructurePlanner.plan(for: request)

        let session = LanguageModelSession(
            instructions: WorkoutPromptBuilder.instructions(library: library, focus: request.focus)
        )

        do {
            let response = try await session.respond(
                to: WorkoutPromptBuilder.prompt(for: request, plan: plan),
                generating: GeneratedWorkout.self,
                options: GenerationOptions(temperature: 0.7)
            )
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            if case .guardrailViolation = error {
                throw WorkoutGenerationError.blockedBySafety
            }
            if case .exceededContextWindowSize = error {
                throw WorkoutGenerationError.contextTooLarge
            }
            throw WorkoutGenerationError.generationFailed
        } catch let error as WorkoutGenerationError {
            throw error
        } catch {
            throw WorkoutGenerationError.generationFailed
        }
    }
}
