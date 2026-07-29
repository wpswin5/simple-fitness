import Foundation
import SwiftData

// MARK: - Versioned Schema
// The current models are declared as V1, establishing a migration baseline while
// there are no public users. Future model changes should add a `SimpleFitnessSchemaV2`
// (with the changed model definitions) plus a `MigrationStage` in the plan below —
// so updates MIGRATE the store instead of wiping it.
//
// The destructive store-reset in Simple_FitnessApp remains only as a last-resort
// catch if a store is somehow unreadable even with the migration plan.

enum SimpleFitnessSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            // Strength
            Exercise.self,
            ExerciseInSet.self,
            ExerciseTarget.self,
            SetRound.self,
            WorkoutSet.self,
            Workout.self,
            // Programs
            ProgramDay.self,
            ProgramDayActivity.self,
            ProgramWeek.self,
            Program.self,
            // User
            UserProfile.self,
            ProgramRegistration.self,
            // Logging
            WorkoutLog.self,
            WorkoutSetLog.self,
            ExerciseLog.self,
            // Cardio
            CardioLog.self,
            CardioSplit.self,
            SwimSet.self,
            CardioTemplate.self,
            CardioTemplateInterval.self,
        ]
    }
}

// MARK: - Migration Plan

enum SimpleFitnessMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SimpleFitnessSchemaV1.self]
    }

    /// Empty for now — V1 is the baseline. When the schema changes, add a V2 and a
    /// `MigrationStage.lightweight` (or `.custom`) from V1 → V2 here.
    static var stages: [MigrationStage] {
        []
    }
}
