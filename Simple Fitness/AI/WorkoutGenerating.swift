import Foundation
import FoundationModels

// MARK: - Provider seam
// The generation UI depends only on this protocol. Today the sole live
// implementation is the on-device Foundation Model; when Apple's server /
// Private Cloud Compute APIs stabilize (currently beta), or if a remote
// provider tier is added, they slot in here without touching the UI or mapper.

/// A compact, SwiftData-free snapshot of one library exercise, safe to hand
/// to any generator implementation (and cheap to include in a prompt).
struct LibraryExercise: Sendable {
    var name: String
    var muscleGroup: MuscleGroup
    var equipment: String

    init(_ exercise: Exercise) {
        self.name = exercise.name
        self.muscleGroup = exercise.muscleGroup
        self.equipment = exercise.equipment
    }
}

/// Errors surfaced to the user, mapped from provider-specific failures.
enum WorkoutGenerationError: LocalizedError {
    case blockedBySafety
    case contextTooLarge
    case modelUnavailable
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .blockedBySafety:
            return "That request couldn't be processed. Try rewording your notes."
        case .contextTooLarge:
            return "The request was too large. Try shorter notes."
        case .modelUnavailable:
            return "Apple Intelligence isn't available right now. Try again in a moment."
        case .generationFailed:
            return "Couldn't generate a workout. Please try again."
        }
    }
}

protocol WorkoutGenerating: Sendable {
    /// Designs one workout for the request, preferring exercises from `library`.
    func generate(_ request: WorkoutGenerationRequest, library: [LibraryExercise]) async throws -> GeneratedWorkout
}

// MARK: - Availability

/// UI-friendly wrapper around SystemLanguageModel availability.
enum GenerationAvailability: Equatable {
    case available
    case appleIntelligenceOff
    case deviceNotEligible
    case modelDownloading

    static var current: GenerationAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceOff
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.modelNotReady):
            return .modelDownloading
        case .unavailable:
            return .deviceNotEligible
        }
    }

    /// Short explanation for non-available states, shown in the generation UI.
    var explanation: String? {
        switch self {
        case .available:
            return nil
        case .appleIntelligenceOff:
            return "Turn on Apple Intelligence in Settings to generate workouts."
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence."
        case .modelDownloading:
            return "The on-device model is still downloading. Try again shortly."
        }
    }
}
