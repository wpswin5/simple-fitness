import SwiftUI
import SwiftData

// MARK: - ExercisePickerView
// Presented as a sheet from AddSetView. Lets the user search/filter exercises
// and select one to add to the set being configured.

struct ExercisePickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    var onSelect: (Exercise) -> Void

    @State private var searchText: String = ""
    @State private var selectedMuscle: MuscleGroup? = nil
    @State private var showingCreate = false

    // MARK: - Filtered Results

    private var filtered: [Exercise] {
        allExercises.filter { exercise in
            let matchesMuscle = selectedMuscle == nil || exercise.muscleGroup == selectedMuscle
            let matchesSearch = searchText.isEmpty ||
                exercise.name.localizedCaseInsensitiveContains(searchText) ||
                exercise.equipment.localizedCaseInsensitiveContains(searchText)
            return matchesMuscle && matchesSearch
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Muscle group filter chips
                muscleGroupFilter

                Divider()

                // Exercise list
                if filtered.isEmpty {
                    emptyState
                } else {
                    exerciseList
                }
            }
            .navigationTitle("Choose Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateExerciseView { newExercise in
                    onSelect(newExercise)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Muscle Filter

    private var muscleGroupFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                filterChip(label: "All", muscle: nil)
                ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                    filterChip(label: muscle.displayName, muscle: muscle)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func filterChip(label: String, muscle: MuscleGroup?) -> some View {
        let isSelected = selectedMuscle == muscle
        return Button(label) {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedMuscle = muscle
            }
        }
        .font(.sfCaption)
        .fontWeight(isSelected ? .semibold : .regular)
        .foregroundStyle(isSelected ? .white : Color.primary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(isSelected ? Color.sfAccent : Color.sfSurface)
        .clipShape(Capsule())
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Exercise List

    private var exerciseList: some View {
        List(filtered) { exercise in
            Button {
                onSelect(exercise)
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.sfSubhead)
                            .foregroundStyle(.primary)
                        HStack(spacing: Spacing.xs) {
                            Text(exercise.muscleGroup.displayName)
                                .font(.sfCaption)
                                .foregroundStyle(Color.sfAccent)
                            if !exercise.equipment.isEmpty {
                                Text("·")
                                    .font(.sfCaption)
                                    .foregroundStyle(.secondary)
                                Text(exercise.equipment)
                                    .font(.sfCaption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.sfAccent)
                        .font(.system(size: 20))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            VStack(spacing: Spacing.xs) {
                Text(searchText.isEmpty ? "No exercises found" : "No results for \"\(searchText)\"")
                    .font(.sfHeadline)
                Text("Tap + to create a new exercise.")
                    .font(.sfCallout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Spacing.xl)
    }
}

// MARK: - CreateExerciseView
// Minimal form to quickly create a new exercise.

struct CreateExerciseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var onCreate: (Exercise) -> Void

    @State private var name: String = ""
    @State private var selectedMuscle: MuscleGroup = .chest
    @State private var equipment: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise Name") {
                    TextField("e.g. Cable Fly", text: $name)
                        .autocorrectionDisabled()
                }

                Section("Muscle Group") {
                    Picker("Muscle Group", selection: $selectedMuscle) {
                        ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                            Text(muscle.displayName).tag(muscle)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }

                Section("Equipment (optional)") {
                    TextField("e.g. Barbell, Dumbbell, Cable", text: $equipment)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        saveAndReturn()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func saveAndReturn() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let exercise = Exercise(name: trimmed, muscleGroup: selectedMuscle, equipment: equipment)
        modelContext.insert(exercise)
        try? modelContext.save()
        onCreate(exercise)
        dismiss()
    }
}
