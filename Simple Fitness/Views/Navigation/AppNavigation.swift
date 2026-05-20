import SwiftUI
import SwiftData

struct AppNavigation: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: Tab = .home

    enum Tab: Int {
        case home, workouts, programs, progress, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home",     systemImage: "house.fill") }
                .tag(Tab.home)

            WorkoutListView()
                .tabItem { Label("Workouts", systemImage: "dumbbell.fill") }
                .tag(Tab.workouts)

            ProgramsListView()
                .tabItem { Label("Programs", systemImage: "calendar.badge.clock") }
                .tag(Tab.programs)

            ProgressDashboardView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(Color.sfAccent)
        .onAppear { seedIfNeeded() }
    }

    private func seedIfNeeded() {
        #if DEBUG
        SeedDataManager(context: modelContext).seedIfNeeded()
        #endif
    }
}

#Preview {
    AppNavigation()
        .modelContainer(for: [
            Exercise.self, ExerciseInSet.self, WorkoutSet.self, Workout.self,
            WorkoutLog.self, WorkoutSetLog.self, ExerciseLog.self,
            Program.self, ProgramWeek.self, ProgramDay.self,
            UserProfile.self, ProgramRegistration.self
        ], inMemory: true)
}
