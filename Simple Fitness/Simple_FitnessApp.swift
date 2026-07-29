//
//  Simple_FitnessApp.swift
//  Simple Fitness
//
//  Created by Will Swindell on 5/17/26.
//

import SwiftUI
import SwiftData

@main
struct Simple_FitnessApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            Exercise.self,
            ExerciseInSet.self,
            ExerciseTarget.self,
            SetRound.self,
            WorkoutSet.self,
            Workout.self,
            ProgramDay.self,
            ProgramDayActivity.self,
            ProgramWeek.self,
            Program.self,
            UserProfile.self,
            ProgramRegistration.self,
            WorkoutLog.self,
            WorkoutSetLog.self,
            ExerciseLog.self,
            // Cardio
            CardioLog.self,
            CardioSplit.self,
            SwimSet.self,
            CardioTemplate.self,
            CardioTemplateInterval.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Pre-release MVP: no versioned migration plan yet. If the persistent store
            // is incompatible with the current schema (e.g. after a model change), wipe
            // the store and rebuild it once rather than hard-crashing every launch.
            // DEBUG seed data repopulates automatically.
            Self.deleteStoreFiles(for: config)
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer after resetting store: \(error)")
            }
        }
    }

    /// Removes the SwiftData store files backing a configuration so a fresh, empty
    /// store can be created. Used as a destructive fallback on schema mismatch.
    private static func deleteStoreFiles(for config: ModelConfiguration) {
        let fm = FileManager.default
        let storeURL = config.url
        // SwiftData/Core Data keeps sidecar files alongside the .store (WAL/SHM).
        let sidecars = [
            storeURL,
            storeURL.deletingPathExtension().appendingPathExtension("store-wal"),
            storeURL.deletingPathExtension().appendingPathExtension("store-shm"),
        ]
        for url in sidecars {
            try? fm.removeItem(at: url)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppNavigation()
                .modelContainer(modelContainer)
        }
    }
}
