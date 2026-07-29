import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @State private var showingImporter = false
    @State private var importPayload: ImportPayload? = nil
    @State private var showingExportPicker = false
    @State private var importErrorMessage: String? = nil
    @State private var templateURL: URL? = nil

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

                // Import & Export
                Section {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import from CSV", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        showingExportPicker = true
                    } label: {
                        Label("Export a Workout", systemImage: "square.and.arrow.up")
                    }
                    if let templateURL {
                        ShareLink(item: templateURL) {
                            Label("Download Template", systemImage: "doc.text")
                        }
                    }
                    #if DEBUG
                    Button {
                        importPayload = ImportPayload(text: CSVTemplate.text)
                    } label: {
                        Label("Import Sample Template (debug)", systemImage: "ladybug")
                    }
                    #endif
                } header: {
                    Text("Import & Export")
                } footer: {
                    Text("Author workouts and programs in a spreadsheet, save as CSV, and import here. Download the template for the format.")
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
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                handleImport(result)
            }
            .sheet(item: $importPayload) { payload in
                ImportPreviewView(text: payload.text)
            }
            .sheet(isPresented: $showingExportPicker) {
                ExportWorkoutPicker()
            }
            .alert("Import Failed", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            ), presenting: importErrorMessage) { _ in
                Button("OK", role: .cancel) { importErrorMessage = nil }
            } message: { Text($0) }
            .onAppear {
                if templateURL == nil {
                    templateURL = CSVFile.temp(name: "SimpleFitness-Template.csv", contents: CSVTemplate.text)
                }
            }
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

    // MARK: - Import

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                importPayload = ImportPayload(text: text)
            } catch {
                importErrorMessage = "Couldn't read the file: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Import/Export helpers

/// Wraps imported file text so it can drive a `.sheet(item:)`.
struct ImportPayload: Identifiable {
    let id = UUID()
    let text: String
}

/// Writes CSV text to a temporary `.csv` file for sharing.
enum CSVFile {
    static func temp(name: String, contents: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try contents.data(using: .utf8)?.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Filesystem-safe version of a workout name for use as a filename.
    static func safeName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Workout" : trimmed
    }
}

// MARK: - Export picker

/// Lists workouts, each shareable as a CSV file.
struct ExportWorkoutPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Workout.name) private var workouts: [Workout]

    var body: some View {
        NavigationStack {
            List {
                if workouts.isEmpty {
                    Text("No workouts to export yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(workouts) { workout in
                        if let url = CSVFile.temp(name: "\(CSVFile.safeName(workout.name)).csv",
                                                  contents: WorkoutCSV.encode([workout])) {
                            ShareLink(item: url) {
                                Label(workout.name, systemImage: "dumbbell.fill")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Export a Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Workout.self], inMemory: true)
}
