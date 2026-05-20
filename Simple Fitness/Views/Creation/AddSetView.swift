import SwiftUI

// MARK: - AddSetView
// Sheet for configuring a single workout set before adding it to the workout.
// Supports single exercises and supersets.

struct AddSetView: View {
    @Environment(\.dismiss) private var dismiss

    // Pass an existing draft to edit, or nil to create new
    var existingDraft: DraftWorkoutSet? = nil
    var onSave: (DraftWorkoutSet) -> Void

    @State private var draft: DraftWorkoutSet
    @State private var showingExercisePicker = false
    @State private var editingExerciseIndex: Int? = nil

    // MARK: - Rest options

    private let restOptions: [(label: String, seconds: Int)] = [
        ("30s", 30), ("45s", 45), ("60s", 60),
        ("90s", 90), ("2 min", 120), ("3 min", 180)
    ]

    // MARK: - Init

    init(existingDraft: DraftWorkoutSet? = nil, onSave: @escaping (DraftWorkoutSet) -> Void) {
        self.existingDraft = existingDraft
        self.onSave = onSave
        _draft = State(initialValue: existingDraft ?? DraftWorkoutSet())
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Exercise list
                    exerciseSection

                    // Rest time
                    restSection

                    // Save button
                    Button(existingDraft == nil ? "Add Set" : "Update Set") {
                        onSave(draft)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(draft.exercises.isEmpty)
                    .padding(.top, Spacing.xs)
                }
                .padding(Spacing.md)
            }
            .navigationTitle(existingDraft == nil ? "New Set" : "Edit Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView { exercise in
                    let draft = DraftExerciseInSet(exercise: exercise)
                    self.draft.exercises.append(draft)
                }
            }
        }
    }

    // MARK: - Exercise Section

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Exercises", badge: draft.exercises.count > 1 ? "Superset" : nil)

            if draft.exercises.isEmpty {
                emptyExercisePlaceholder
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { index, exercise in
                        exerciseRow(index: index, draftEx: exercise)
                    }
                }
            }

            Button {
                showingExercisePicker = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.sfAccent)
                    Text(draft.exercises.isEmpty ? "Select Exercise" : "Add to Superset")
                        .foregroundStyle(Color.sfAccent)
                    Spacer()
                }
                .font(.sfSubhead)
                .padding(Spacing.md)
                .background(Color.sfAccent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyExercisePlaceholder: some View {
        HStack {
            Image(systemName: "dumbbell")
                .foregroundStyle(.secondary)
            Text("No exercise selected")
                .font(.sfCallout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func exerciseRow(index: Int, draftEx: DraftExerciseInSet) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Name + remove button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draftEx.exercise.name)
                        .font(.sfHeadline)
                    Text(draftEx.exercise.muscleGroup.displayName)
                        .font(.sfCaption)
                        .foregroundStyle(Color.sfAccent)
                }
                Spacer()
                Button {
                    draft.exercises.remove(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.sfMuted)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
            }

            // Time-based toggle
            Toggle(isOn: binding(isTimeBased: index)) {
                Text("Timed exercise")
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)
            }
            .tint(Color.sfAccent)

            // Reps or Time stepper
            if draft.exercises[index].isTimeBased {
                stepperRow(
                    label: "Duration",
                    value: binding(time: index),
                    range: 10...300,
                    step: 5,
                    format: { "\($0)s" }
                )
            } else {
                stepperRow(
                    label: "Target Reps",
                    value: binding(reps: index),
                    range: 1...50,
                    step: 1,
                    format: { "\($0) reps" }
                )
            }

            // Effort level
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Effort")
                        .font(.sfCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(draft.exercises[index].effortLevel * 100))% of 1RM")
                        .font(.sfCaption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.sfAccent)
                }
                Slider(
                    value: binding(effort: index),
                    in: 0.4...1.0,
                    step: 0.05
                )
                .tint(Color.sfAccent)
            }
        }
        .padding(Spacing.md)
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Rest Section

    private var restSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Rest Between Sets", badge: nil)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 3), spacing: Spacing.xs) {
                ForEach(restOptions, id: \.seconds) { option in
                    let isSelected = draft.restSeconds == option.seconds
                    Button(option.label) {
                        draft.restSeconds = option.seconds
                    }
                    .font(.sfSubhead)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(isSelected ? Color.sfAccent : Color.sfSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    .animation(.easeOut(duration: 0.15), value: isSelected)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, badge: String?) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(title)
                .font(.sfSubhead)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)
            if let badge {
                Text(badge)
                    .font(.sfCaption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.sfAccent)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Color.sfAccent.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Bindings into draft.exercises[index]

    private func binding(reps index: Int) -> Binding<Int> {
        Binding(
            get: { draft.exercises[index].targetReps ?? 8 },
            set: { draft.exercises[index].targetReps = $0 }
        )
    }

    private func binding(time index: Int) -> Binding<Int> {
        Binding(
            get: { draft.exercises[index].targetTime ?? 30 },
            set: { draft.exercises[index].targetTime = $0 }
        )
    }

    private func binding(effort index: Int) -> Binding<Double> {
        Binding(
            get: { draft.exercises[index].effortLevel },
            set: { draft.exercises[index].effortLevel = $0 }
        )
    }

    private func binding(isTimeBased index: Int) -> Binding<Bool> {
        Binding(
            get: { draft.exercises[index].isTimeBased },
            set: { draft.exercises[index].isTimeBased = $0 }
        )
    }

    // MARK: - Generic Stepper Row

    private func stepperRow(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        format: (Int) -> String
    ) -> some View {
        HStack {
            Text(label)
                .font(.sfCaption)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: Spacing.sm) {
                Button {
                    if value.wrappedValue - step >= range.lowerBound {
                        value.wrappedValue -= step
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.sfAccent)
                }
                .buttonStyle(.plain)

                Text(format(value.wrappedValue))
                    .font(.sfSubhead)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .frame(minWidth: 70, alignment: .center)

                Button {
                    if value.wrappedValue + step <= range.upperBound {
                        value.wrappedValue += step
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.sfAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
