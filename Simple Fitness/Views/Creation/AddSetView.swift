import SwiftUI

// MARK: - AddSetView
// Sheet for configuring a single workout set before adding it to the workout.
// Supports single exercises and supersets, each performed for one or more rounds
// with per-round targets (reps/time, weight, effort) and per-round rest.

struct AddSetView: View {
    @Environment(\.dismiss) private var dismiss

    // Pass an existing draft to edit, or nil to create new
    var existingDraft: DraftWorkoutSet? = nil
    var onSave: (DraftWorkoutSet) -> Void

    @State private var draft: DraftWorkoutSet
    @State private var showingExercisePicker = false

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
                    exerciseSection

                    if !draft.exercises.isEmpty {
                        roundsSection
                    }

                    Button(existingDraft == nil ? "Add Set" : "Update Set") {
                        onSave(draft)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(draft.exercises.isEmpty || draft.rounds.isEmpty)
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
                    draft.addExercise(exercise)
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(draftEx.exercise.name)
                    .font(.sfHeadline)
                Text(draftEx.exercise.muscleGroup.displayName)
                    .font(.sfCaption)
                    .foregroundStyle(Color.sfAccent)
            }

            Spacer()

            // Timed vs reps toggle (applies to this exercise across all rounds)
            Toggle(isOn: binding(isTimeBased: index)) {
                Text("Timed")
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.button)
            .tint(Color.sfAccent)

            Button {
                draft.removeExercise(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.sfMuted)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.md)
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Rounds Section

    private var roundsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Sets", badge: nil, trailing: draft.rounds.count > 1 ? "\(draft.rounds.count) sets" : nil)

            ForEach(Array(draft.rounds.enumerated()), id: \.element.id) { roundIndex, _ in
                roundCard(roundIndex: roundIndex)
            }

            HStack(spacing: Spacing.sm) {
                Button {
                    draft.addRound()
                } label: {
                    Label("Add Set", systemImage: "plus.circle.fill")
                        .font(.sfSubhead)
                        .foregroundStyle(Color.sfAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.sfAccent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func roundCard(roundIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header: Set number + delete
            HStack {
                Text("Set \(roundIndex + 1)")
                    .font(.sfSubhead)
                    .fontWeight(.semibold)
                Spacer()
                if draft.rounds.count > 1 {
                    Button {
                        draft.removeRound(at: roundIndex)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sfDanger)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Per-exercise targets for this round
            ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { exIndex, ex in
                if exIndex < draft.rounds[roundIndex].targets.count {
                    targetEditor(roundIndex: roundIndex, exIndex: exIndex, draftEx: ex)
                    if draft.isSuperset && exIndex < draft.exercises.count - 1 {
                        Divider()
                    }
                }
            }

            Divider()

            // Rest for this round
            restPicker(roundIndex: roundIndex)
        }
        .padding(Spacing.md)
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func targetEditor(roundIndex: Int, exIndex: Int, draftEx: DraftExerciseInSet) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if draft.isSuperset {
                Text(draftEx.exercise.name)
                    .font(.sfCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.sfAccent)
            }

            // Reps or Duration + Weight, side by side
            HStack(spacing: Spacing.md) {
                if draftEx.isTimeBased {
                    stepperRow(
                        label: "Time",
                        value: binding(time: roundIndex, exIndex),
                        range: 5...600,
                        step: 5,
                        format: { "\($0)s" }
                    )
                } else {
                    stepperRow(
                        label: "Reps",
                        value: binding(reps: roundIndex, exIndex),
                        range: 1...50,
                        step: 1,
                        format: { "\($0)" }
                    )
                }

                weightField(roundIndex: roundIndex, exIndex: exIndex)
            }

            // Effort level
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Effort")
                        .font(.sfCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(draft.rounds[roundIndex].targets[exIndex].effortLevel * 100))% of 1RM")
                        .font(.sfCaption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.sfAccent)
                }
                Slider(value: binding(effort: roundIndex, exIndex), in: 0.4...1.0, step: 0.05)
                    .tint(Color.sfAccent)
            }
        }
    }

    private func weightField(roundIndex: Int, exIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weight")
                .font(.sfCaption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField("—", text: binding(weight: roundIndex, exIndex))
                    .keyboardType(.decimalPad)
                    .font(.sfSubhead)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .frame(minWidth: 44)
                Text("lbs")
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
    }

    private func restPicker(roundIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Rest after this set")
                .font(.sfCaption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 3), spacing: Spacing.xs) {
                ForEach(restOptions, id: \.seconds) { option in
                    let isSelected = draft.rounds[roundIndex].restSeconds == option.seconds
                    Button(option.label) {
                        draft.rounds[roundIndex].restSeconds = option.seconds
                    }
                    .font(.sfCaption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xs)
                    .background(isSelected ? Color.sfAccent : Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    .animation(.easeOut(duration: 0.15), value: isSelected)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, badge: String?, trailing: String? = nil) -> some View {
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
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bindings into draft.rounds[roundIndex].targets[exIndex]

    private func binding(reps roundIndex: Int, _ exIndex: Int) -> Binding<Int> {
        Binding(
            get: { draft.rounds[roundIndex].targets[exIndex].targetReps ?? 8 },
            set: { draft.rounds[roundIndex].targets[exIndex].targetReps = $0 }
        )
    }

    private func binding(time roundIndex: Int, _ exIndex: Int) -> Binding<Int> {
        Binding(
            get: { draft.rounds[roundIndex].targets[exIndex].targetTime ?? 30 },
            set: { draft.rounds[roundIndex].targets[exIndex].targetTime = $0 }
        )
    }

    private func binding(effort roundIndex: Int, _ exIndex: Int) -> Binding<Double> {
        Binding(
            get: { draft.rounds[roundIndex].targets[exIndex].effortLevel },
            set: { draft.rounds[roundIndex].targets[exIndex].effortLevel = $0 }
        )
    }

    private func binding(weight roundIndex: Int, _ exIndex: Int) -> Binding<String> {
        Binding(
            get: {
                if let w = draft.rounds[roundIndex].targets[exIndex].targetWeight, w > 0 {
                    return w.weightFormatted
                }
                return ""
            },
            set: { draft.rounds[roundIndex].targets[exIndex].targetWeight = Double($0) }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.sfCaption)
                .foregroundStyle(.secondary)
            HStack(spacing: Spacing.sm) {
                Button {
                    if value.wrappedValue - step >= range.lowerBound {
                        value.wrappedValue -= step
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.sfAccent)
                }
                .buttonStyle(.plain)

                Text(format(value.wrappedValue))
                    .font(.sfSubhead)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .center)

                Button {
                    if value.wrappedValue + step <= range.upperBound {
                        value.wrappedValue += step
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.sfAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
