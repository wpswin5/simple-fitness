import Foundation
import SwiftData

// MARK: - ExerciseResolver
// Resolves free-text exercise names against the library, creating new Exercise
// entities (isCustom) for genuine gaps and tracking them for cleanup. Shared by
// AI generation (GeneratedWorkoutMapper) and CSV import (WorkoutCSV).

@MainActor
struct ExerciseResolver {
    private var byName: [String: Exercise]
    private let context: ModelContext
    private(set) var createdExercises: [Exercise] = []

    init(library: [Exercise], context: ModelContext) {
        self.context = context
        self.byName = Dictionary(
            library.map { (ExerciseResolver.normalize($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Resolves a name to a draft slot, matching case-insensitively and creating a
    /// new Exercise when no match exists. Returns nil only for a blank name.
    mutating func resolve(name: String, muscleGroup: MuscleGroup?, isTimeBased: Bool) -> DraftExerciseInSet? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        let key = ExerciseResolver.normalize(cleanName)

        let exercise: Exercise
        if let existing = byName[key] {
            exercise = existing
        } else {
            let created = Exercise(name: cleanName, muscleGroup: muscleGroup ?? .fullBody)
            context.insert(created)
            byName[key] = created
            createdExercises.append(created)
            exercise = created
        }
        return DraftExerciseInSet(exercise: exercise, isTimeBased: isTimeBased)
    }

    /// Whether a name already resolves to a library exercise (no creation).
    func contains(_ name: String) -> Bool {
        byName[ExerciseResolver.normalize(name)] != nil
    }

    /// Lowercased, whitespace-collapsed key for name matching.
    static func normalize(_ name: String) -> String {
        name.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
