import SwiftUI
import SwiftData
import Combine

// MARK: - GenerateWorkoutView
// Parameter form for AI workout generation. Collects focus/goal/duration/
// intensity + free-text notes, runs the generator, then hands the mapped
// draft to CreateWorkoutView for review before saving (human-in-the-loop).

struct GenerateWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    // MARK: - Form state

    @State private var focus: WorkoutFocus = .fullBody
    @State private var goal: TrainingGoal = .strengthGain
    @State private var durationMinutes: Int = 45
    @State private var intensity: WorkoutIntensity = .moderate
    @State private var notes: String = ""

    // MARK: - Flow state

    @State private var isGenerating = false
    @State private var errorMessage: String? = nil
    @State private var editorPayload: EditorPayload? = nil
    @State private var pendingCreatedExercises: [Exercise] = []
    @State private var didSaveWorkout = false
    @State private var loadingMessageIndex = 0

    #if DEBUG
    @State private var useMockGenerator = false
    #endif

    private let availability = GenerationAvailability.current
    private let durationOptions = [20, 30, 45, 60, 75, 90]
    private let loadingMessages = [
        "Consulting your coach…",
        "Balancing the muscle groups…",
        "Loading the bar…",
        "Programming your sets…",
        "Dialing in the rest times…",
    ]
    private let loadingTimer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    private struct EditorPayload: Identifiable {
        let id = UUID()
        let mapped: MappedWorkout
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isGenerating {
                    generatingView
                } else {
                    formView
                }
            }
            .navigationTitle("Generate Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isGenerating)
                }
            }
            .alert("Generation Failed", isPresented: .constant(errorMessage != nil)) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .fullScreenCover(item: $editorPayload, onDismiss: handleEditorDismissed) { payload in
                CreateWorkoutView(prefilled: payload.mapped, onSaved: { didSaveWorkout = true })
            }
        }
        .interactiveDismissDisabled(isGenerating)
    }

    // MARK: - Form

    private var formView: some View {
        Form {
            Section("Focus") {
                Picker("Focus", selection: $focus) {
                    ForEach(WorkoutFocus.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                .tint(Color.sfAccent)

                Picker("Goal", selection: $goal) {
                    ForEach(TrainingGoal.allCases, id: \.self) { g in
                        Text(g.displayName).tag(g)
                    }
                }
                .tint(Color.sfAccent)
            }

            Section("Duration") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 3), spacing: Spacing.xs) {
                    ForEach(durationOptions, id: \.self) { minutes in
                        let isSelected = durationMinutes == minutes
                        Button("\(minutes) min") {
                            durationMinutes = minutes
                        }
                        .font(.sfSubhead)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(isSelected ? Color.sfAccent : Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                        .buttonStyle(.plain)
                        .animation(.easeOut(duration: 0.15), value: isSelected)
                    }
                }
                .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.sm,
                                          bottom: Spacing.sm, trailing: Spacing.sm))
            }

            Section("Intensity") {
                Picker("Intensity", selection: $intensity) {
                    ForEach(WorkoutIntensity.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.sm,
                                          bottom: Spacing.sm, trailing: Spacing.sm))
            }

            Section {
                TextField("e.g. Focus on incline work, no flat bench…", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Anything else? (optional)")
            }

            #if DEBUG
            Section {
                Toggle("Use sample generator (debug)", isOn: $useMockGenerator)
                    .tint(Color.sfAccent)
            } footer: {
                Text("Returns a canned workout without calling the on-device model.")
            }
            #endif

            Section {
                if let explanation = availabilityExplanation {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Text(explanation)
                            .font(.sfCaption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    generate()
                } label: {
                    Label("Generate Workout", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canGenerate)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
    }

    // MARK: - Generating state

    private var generatingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "wand.and.stars")
                .font(.system(size: 44))
                .foregroundStyle(Color.sfAccent)
                .symbolEffect(.pulse)
            ProgressView()
                .controlSize(.large)
                .tint(Color.sfAccent)
            Text(loadingMessages[loadingMessageIndex])
                .font(.sfCallout)
                .foregroundStyle(.secondary)
                .animation(.easeInOut(duration: 0.3), value: loadingMessageIndex)
                .contentTransition(.opacity)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onReceive(loadingTimer) { _ in
            guard isGenerating else { return }
            loadingMessageIndex = (loadingMessageIndex + 1) % loadingMessages.count
        }
    }

    // MARK: - Availability

    private var canGenerate: Bool {
        #if DEBUG
        if useMockGenerator { return true }
        #endif
        return availability == .available
    }

    private var availabilityExplanation: String? {
        #if DEBUG
        if useMockGenerator { return nil }
        #endif
        return availability.explanation
    }

    // MARK: - Generation

    private func makeGenerator() -> WorkoutGenerating {
        #if DEBUG
        if useMockGenerator { return MockWorkoutGenerator() }
        #endif
        return FoundationModelWorkoutGenerator()
    }

    private func generate() {
        isGenerating = true
        errorMessage = nil
        loadingMessageIndex = 0

        let request = WorkoutGenerationRequest(
            focus: focus,
            goal: goal,
            targetDurationMinutes: durationMinutes,
            intensity: intensity,
            notes: notes
        )
        let library = allExercises.map(LibraryExercise.init)
        let generator = makeGenerator()

        Task {
            do {
                let generated = try await generator.generate(request, library: library)
                // The same plan the generator prompted with — the mapper enforces
                // it, since the model treats the numbers as advisory.
                let plan = WorkoutStructurePlanner.plan(for: request)
                let mapped = GeneratedWorkoutMapper.map(generated, library: allExercises, plan: plan, context: modelContext)
                guard !mapped.sets.isEmpty else {
                    throw WorkoutGenerationError.generationFailed
                }
                pendingCreatedExercises = mapped.createdExercises
                editorPayload = EditorPayload(mapped: mapped)
            } catch {
                errorMessage = (error as? WorkoutGenerationError)?.errorDescription
                    ?? WorkoutGenerationError.generationFailed.errorDescription
            }
            isGenerating = false
        }
    }

    // MARK: - Editor handoff

    private func handleEditorDismissed() {
        cleanupOrphanedCreatedExercises()
        if didSaveWorkout {
            dismiss()
        }
        // If the user cancelled the editor, stay on the form so they can
        // tweak parameters and regenerate.
    }

    /// Deletes exercises the mapper created for this generation that ended up
    /// unreferenced (i.e. the user cancelled the editor without saving).
    private func cleanupOrphanedCreatedExercises() {
        guard !pendingCreatedExercises.isEmpty else { return }
        let slots = (try? modelContext.fetch(FetchDescriptor<ExerciseInSet>())) ?? []
        let referencedIDs = Set(slots.compactMap { $0.exercise?.id })
        var deletedAny = false
        for exercise in pendingCreatedExercises where !referencedIDs.contains(exercise.id) {
            modelContext.delete(exercise)
            deletedAny = true
        }
        if deletedAny {
            try? modelContext.save()
        }
        pendingCreatedExercises = []
    }
}

#Preview {
    GenerateWorkoutView()
        .modelContainer(for: [
            Exercise.self, ExerciseInSet.self, ExerciseTarget.self, SetRound.self,
            WorkoutSet.self, Workout.self
        ], inMemory: true)
}
