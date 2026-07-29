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
        // Versioned schema (see SchemaVersions.swift) so future model changes can
        // migrate the store instead of wiping it.
        let schema = Schema(versionedSchema: SimpleFitnessSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: SimpleFitnessMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            // Last-resort catch: if a store is somehow unreadable even with the
            // migration plan, wipe it and rebuild once rather than hard-crashing
            // every launch. This should be unreachable in normal operation now.
            Self.deleteStoreFiles(for: config)
            do {
                modelContainer = try ModelContainer(
                    for: schema,
                    migrationPlan: SimpleFitnessMigrationPlan.self,
                    configurations: [config]
                )
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
