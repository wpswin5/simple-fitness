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
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppNavigation()
                .modelContainer(modelContainer)
        }
    }
}
