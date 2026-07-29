import Foundation

// MARK: - WorkoutGenerationRequest
// The typed input to workout generation. Deliberately a plain value type:
// a future program planner constructs one of these per program-day slot
// (with an added slotContext) and calls the same generation pipeline.

/// What the workout should focus on. Drives library filtering and prompt wording.
enum WorkoutFocus: String, CaseIterable, Identifiable, Sendable {
    case pushDay, pullDay, legDay, upperBody, lowerBody, fullBody, core, arms

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pushDay:   return "Push Day"
        case .pullDay:   return "Pull Day"
        case .legDay:    return "Leg Day"
        case .upperBody: return "Upper Body"
        case .lowerBody: return "Lower Body"
        case .fullBody:  return "Full Body"
        case .core:      return "Core"
        case .arms:      return "Arms"
        }
    }

    /// Muscle groups this focus targets — used to filter the exercise library
    /// fed to the model (keeps the prompt inside the on-device context window).
    var muscleGroups: [MuscleGroup] {
        switch self {
        case .pushDay:   return [.chest, .shoulders, .triceps]
        case .pullDay:   return [.back, .biceps, .forearms]
        case .legDay:    return [.quadriceps, .hamstrings, .glutes, .calves, .legs]
        case .upperBody: return [.chest, .back, .shoulders, .biceps, .triceps, .forearms]
        case .lowerBody: return [.quadriceps, .hamstrings, .glutes, .calves, .legs, .core]
        case .fullBody:  return MuscleGroup.allCases
        case .core:      return [.core]
        case .arms:      return [.biceps, .triceps, .forearms, .shoulders]
        }
    }
}

/// How hard the workout should be. Maps to effort-% and rest guidance in the prompt.
enum WorkoutIntensity: String, CaseIterable, Identifiable, Sendable {
    case light, moderate, hard, maxEffort

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light:     return "Light"
        case .moderate:  return "Moderate"
        case .hard:      return "Hard"
        case .maxEffort: return "Max"
        }
    }

    /// Effort range as % of 1RM, used in the prompt and for mapper defaults.
    var effortPercentRange: ClosedRange<Int> {
        switch self {
        case .light:     return 50...65
        case .moderate:  return 60...75
        case .hard:      return 70...85
        case .maxEffort: return 80...95
        }
    }

    /// Rest guidance passed to the model.
    var restGuidance: String {
        switch self {
        case .light:     return "short rests (30–60s)"
        case .moderate:  return "moderate rests (60–90s)"
        case .hard:      return "full rests (90–150s)"
        case .maxEffort: return "long rests (2–3 min) between heavy sets"
        }
    }
}

/// Everything the generator needs to design one workout.
struct WorkoutGenerationRequest: Sendable {
    var focus: WorkoutFocus = .fullBody
    var goal: TrainingGoal = .strengthGain
    var targetDurationMinutes: Int = 45
    var intensity: WorkoutIntensity = .moderate
    var notes: String = ""
}
