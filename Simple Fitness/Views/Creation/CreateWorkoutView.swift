import SwiftUI
import SwiftData

struct CreateWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var vm: CreateWorkoutViewModel

    @State private var showingAddSet = false
    @State private var editingDraft: DraftWorkoutSet? = nil
    @State private var showingError = false

    init(editing workout: Workout? = nil) {
        _vm = State(wrappedValue: workout.map { CreateWorkoutViewModel(editing: $0) } ?? CreateWorkoutViewModel())
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Workout Info Card
                    infoSection

                    // Sets
                    setsSection

                    // Rounds (setRepetitions)
                    if vm.draftSets.count > 0 {
                        roundsSection
                    }

                    // Summary
                    if !vm.draftSets.isEmpty {
                        summaryCard
                    }
                }
                .padding(Spacing.md)
            }
            .navigationTitle(vm.isEditing ? "Edit Workout" : "New Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveWorkout()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(vm.isValid ? Color.sfAccent : .secondary)
                    .disabled(!vm.isValid)
                }
            }
            .sheet(isPresented: $showingAddSet) {
                AddSetView { newDraft in
                    vm.addSet(newDraft)
                }
            }
            .sheet(item: $editingDraft) { draft in
                AddSetView(existingDraft: draft) { updatedDraft in
                    vm.updateSet(updatedDraft)
                }
            }
            .alert("Missing Info", isPresented: $showingError, presenting: vm.errorMessage) { _ in
                Button("OK", role: .cancel) { vm.errorMessage = nil }
            } message: { msg in
                Text(msg)
            }
        }
    }

    // MARK: - Workout Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Workout Details")

            VStack(spacing: 0) {
                // Name field
                HStack {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField("Workout name", text: $vm.workoutName)
                        .font(.sfSubhead)
                        .autocorrectionDisabled()
                }
                .padding(Spacing.md)

                Divider().padding(.leading, Spacing.md + 20)

                // Description field
                HStack(alignment: .top) {
                    Image(systemName: "text.alignleft")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                        .padding(.top, 2)
                    TextField("Description (optional)", text: $vm.workoutDescription, axis: .vertical)
                        .font(.sfCallout)
                        .lineLimit(1...3)
                        .autocorrectionDisabled()
                }
                .padding(Spacing.md)
            }
            .background(Color.sfSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    // MARK: - Sets Section

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                sectionHeader("Sets")
                Spacer()
                if !vm.draftSets.isEmpty {
                    Text("\(vm.draftSets.count) set\(vm.draftSets.count == 1 ? "" : "s")")
                        .font(.sfCaption)
                        .foregroundStyle(.secondary)
                }
            }

            if vm.draftSets.isEmpty {
                emptySetPlaceholder
            } else {
                setList
            }

            // Add Set button
            Button {
                showingAddSet = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.sfAccent)
                    Text("Add Set")
                        .foregroundStyle(Color.sfAccent)
                        .fontWeight(.semibold)
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

    private var emptySetPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: Spacing.sm) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.sfAccent.opacity(0.5))
                Text("No sets yet. Tap below to add your first.")
                    .font(.sfCallout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(Spacing.xl)
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    @ViewBuilder
    private var setList: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(Array(vm.draftSets.enumerated()), id: \.element.id) { index, draft in
                setRow(index: index, draft: draft)
            }
        }
    }

    private func setRow(index: Int, draft: DraftWorkoutSet) -> some View {
        HStack(spacing: Spacing.sm) {
            // Set number badge
            Text("\(index + 1)")
                .font(.sfCaption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(draft.isSuperset ? Color.sfAccent.opacity(0.8) : Color.sfAccent)
                .clipShape(Circle())

            // Set info
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.displayName)
                    .font(.sfSubhead)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: Spacing.xs) {
                    if draft.isSuperset {
                        Label("Superset", systemImage: "arrow.triangle.2.circlepath")
                            .font(.sfCaption2)
                            .foregroundStyle(Color.sfAccent)
                    }
                    Text(draft.displayReps)
                        .font(.sfCaption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.sfCaption)
                        .foregroundStyle(.secondary)
                    Text("Rest \(draft.restSeconds)s")
                        .font(.sfCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Edit button
            Button {
                editingDraft = draft
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.sfSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Delete button
            Button {
                withAnimation {
                    if let i = vm.draftSets.firstIndex(where: { $0.id == draft.id }) {
                        vm.draftSets.remove(at: i)
                    }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sfDanger)
                    .frame(width: 32, height: 32)
                    .background(Color.sfSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.sm)
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Rounds Section

    private var roundsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Rounds")

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeat all sets")
                        .font(.sfSubhead)
                    Text(vm.setRepetitions == 1
                         ? "Complete each set once"
                         : "Complete all sets \(vm.setRepetitions) times")
                        .font(.sfCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: Spacing.md) {
                    Button {
                        if vm.setRepetitions > 1 { vm.setRepetitions -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(vm.setRepetitions > 1 ? Color.sfAccent : .secondary)
                    }
                    .buttonStyle(.plain)

                    Text("\(vm.setRepetitions)×")
                        .font(.sfCounter)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .center)

                    Button {
                        if vm.setRepetitions < 10 { vm.setRepetitions += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.sfAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.md)
            .background(Color.sfSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryItem(
                icon: "list.number",
                value: "\(vm.draftSets.count * vm.setRepetitions)",
                label: "Total Sets"
            )
            Divider().frame(height: 36)
            summaryItem(
                icon: "dumbbell",
                value: "\(vm.draftSets.reduce(0) { $0 + $1.exercises.count })",
                label: "Exercises"
            )
            Divider().frame(height: 36)
            summaryItem(
                icon: "clock",
                value: "~\(vm.estimatedDurationMinutes)m",
                label: "Est. Time"
            )
        }
        .padding(Spacing.md)
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func summaryItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.sfCaption)
                .foregroundStyle(Color.sfAccent)
            Text(value)
                .font(.sfSubhead)
                .fontWeight(.semibold)
            Text(label)
                .font(.sfCaption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sfSubhead)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.5)
    }

    private func saveWorkout() {
        if vm.save(context: modelContext) {
            dismiss()
        } else {
            showingError = vm.errorMessage != nil
        }
    }
}

#Preview {
    CreateWorkoutView()
        .modelContainer(for: [
            Exercise.self, ExerciseInSet.self, WorkoutSet.self, Workout.self
        ], inMemory: true)
}
