import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.miles.rawValue

    private var distanceUnit: Binding<DistanceUnit> {
        Binding(
            get: { DistanceUnit(rawValue: distanceUnitRaw) ?? .miles },
            set: { distanceUnitRaw = $0.rawValue }
        )
    }

    @State private var showingResetConfirm = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                // App info
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("App")
                }

                // Preferences
                Section {
                    HStack {
                        Text("Weight Unit")
                        Spacer()
                        Text("lbs")
                            .foregroundStyle(.secondary)
                    }
                    Picker("Distance Unit", selection: distanceUnit) {
                        ForEach(DistanceUnit.allCases, id: \.self) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    HStack {
                        Text("Rest Timer Sound")
                        Spacer()
                        Text("On")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Distance unit applies to all cardio logs.")
                }

                // Account (Phase 2)
                Section {
                    Label("Sign in with Auth0", systemImage: "person.circle")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Account")
                } footer: {
                    Text("Cloud sync and sharing coming in a future update.")
                }

                // Data Management
                Section {
                    Button(role: .destructive) {
                        showingResetConfirm = true
                    } label: {
                        Label("Reset All Data", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Deletes all local workouts and logs. Cannot be undone.")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Reset All Data?", isPresented: $showingResetConfirm, titleVisibility: .visible) {
                Button("Reset Everything", role: .destructive) {
                    resetAllData()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all workouts, programs, and history.")
            }
        }
    }

    private func resetAllData() {
        deleteAll(ExerciseLog.self)
        deleteAll(WorkoutSetLog.self)
        deleteAll(WorkoutLog.self)
        deleteAll(ExerciseInSet.self)
        deleteAll(WorkoutSet.self)
        deleteAll(Workout.self)
        deleteAll(ProgramDayActivity.self)
        deleteAll(ProgramDay.self)
        deleteAll(ProgramWeek.self)
        deleteAll(Program.self)
        deleteAll(ProgramRegistration.self)
        deleteAll(UserProfile.self)
        deleteAll(Exercise.self)
        deleteAll(CardioSplit.self)
        deleteAll(SwimSet.self)
        deleteAll(CardioLog.self)
        deleteAll(CardioTemplateInterval.self)
        deleteAll(CardioTemplate.self)
        try? modelContext.save()
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        guard let items = try? modelContext.fetch(FetchDescriptor<T>()) else { return }
        items.forEach { modelContext.delete($0) }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Workout.self], inMemory: true)
}
