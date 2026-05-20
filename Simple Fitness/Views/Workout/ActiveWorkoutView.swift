import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var vm: ActiveWorkoutViewModel

    @State private var showingQuitConfirm = false
    @State private var showingSaveError = false

    init(workout: Workout) {
        _vm = State(wrappedValue: ActiveWorkoutViewModel(workout: workout))
    }

    // MARK: - Body

    var body: some View {
        Group {
            if vm.isResting {
                RestTimerView(
                    secondsRemaining: vm.restTimeRemaining,
                    totalSeconds: vm.currentSet?.restSeconds ?? 60,
                    onSkip: { vm.skipRest() }
                )
                .transition(.opacity)
            } else if vm.isWorkoutComplete {
                WorkoutSummaryView(
                    workoutName: vm.workout.name,
                    durationSeconds: vm.elapsedSeconds,
                    completedSets: vm.completedSetLogs.count,
                    totalSets: vm.totalSets
                ) {
                    saveAndDismiss()
                }
                .transition(.opacity)
            } else {
                activeContent
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.isResting)
        .animation(.easeInOut(duration: 0.25), value: vm.isWorkoutComplete)
        .onAppear { vm.startWorkout() }
        .confirmationDialog("Quit Workout?", isPresented: $showingQuitConfirm, titleVisibility: .visible) {
            Button("Quit Workout", role: .destructive) { dismiss() }
            Button("Keep Going", role: .cancel) { }
        } message: {
            Text("Your progress won't be saved if you quit now.")
        }
        .alert("Couldn't Save Workout", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text("Your workout couldn't be saved due to a storage error. Please try again.")
        }
    }

    // MARK: - Active Content

    private var activeContent: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar

            Divider()

            // Progress bar
            progressBar

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Set header
                    setHeader

                    // Exercise cards (one per exercise in set)
                    if let set = vm.currentSet {
                        ForEach(Array(set.exercises.enumerated()), id: \.offset) { index, exercise in
                            ExerciseLogCard(
                                exercise: exercise,
                                logEntry: binding(for: index),
                                isCurrent: index == vm.currentExerciseIndex,
                                isSuperset: set.isSuperset
                            )
                        }
                    }

                    // Action button
                    actionButton
                        .padding(.top, Spacing.xs)
                }
                .padding(Spacing.md)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                showingQuitConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.sfSurface)
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text(vm.workout.name)
                    .font(.sfHeadline)
                Text(vm.elapsedSeconds.timerFormatted)
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            // Invisible placeholder to center title
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.sfSurface)
                    .frame(height: 3)
                Rectangle()
                    .fill(Color.sfAccent)
                    .frame(width: geo.size.width * vm.progress, height: 3)
                    .animation(.spring(response: 0.4), value: vm.progress)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Set Header

    private var setHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Set \(vm.completedSetsCount + 1) of \(vm.totalSets)")
                    .font(.sfTitle)

                if let set = vm.currentSet, set.isSuperset {
                    Text("Superset")
                        .font(.sfCaption)
                        .foregroundStyle(Color.sfAccent)
                        .fontWeight(.semibold)
                }

                if vm.workout.setRepetitions > 1 {
                    Text("Round \(vm.currentRepetition) of \(vm.workout.setRepetitions)")
                        .font(.sfCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Group {
            if let set = vm.currentSet, set.isSuperset,
               vm.currentExerciseIndex < set.exercises.count - 1 {
                Button("Next Exercise →") {
                    vm.advanceExerciseInSuperset()
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button("Finish Set") {
                    vm.finishCurrentSet()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: - Binding helper

    private func binding(for index: Int) -> Binding<ExerciseLogEntry> {
        Binding(
            get: {
                guard index < vm.currentLogs.count else {
                    return ExerciseLogEntry(exerciseName: "")
                }
                return vm.currentLogs[index]
            },
            set: { newValue in
                vm.updateLog(
                    exerciseIndex: index,
                    reps: newValue.reps,
                    weight: newValue.weight,
                    rpe: newValue.rpe
                )
            }
        )
    }

    // MARK: - Save

    private func saveAndDismiss() {
        // Build WorkoutLog and insert into SwiftData
        let log = WorkoutLog(workout: vm.workout, startDate: vm.startDate)
        log.completedDate = Date()
        log.durationSeconds = vm.elapsedSeconds
        log.isComplete = true

        for setLog in vm.completedSetLogs {
            modelContext.insert(setLog)
            log.setLogs.append(setLog)
        }
        modelContext.insert(log)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            showingSaveError = true
        }
    }
}

// MARK: - Exercise Log Card

struct ExerciseLogCard: View {
    let exercise: ExerciseInSet
    @Binding var logEntry: ExerciseLogEntry
    let isCurrent: Bool
    let isSuperset: Bool

    @State private var repsText: String = ""
    @State private var weightText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Exercise name + target
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.exerciseName)
                        .font(.sfHeadline)
                        .foregroundStyle(isCurrent ? Color.sfAccent : .primary)

                    if let reps = exercise.targetReps {
                        Text("Target: \(reps) reps @ \(Int(exercise.effortLevel * 100))%")
                            .font(.sfCaption)
                            .foregroundStyle(.secondary)
                    } else if let time = exercise.targetTime {
                        Text("Target: \(time)s hold")
                            .font(.sfCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()

                if isSuperset && isCurrent {
                    Text("↓ Current")
                        .font(.sfCaption2)
                        .foregroundStyle(Color.sfAccent)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.sfAccent.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // Weight + Reps inputs
            HStack(spacing: Spacing.md) {
                logField(
                    icon: "scalemass",
                    placeholder: "Weight",
                    suffix: "lbs",
                    text: $weightText
                ) { val in
                    logEntry.weight = Double(val)
                }

                logField(
                    icon: "repeat",
                    placeholder: "Reps",
                    suffix: "reps",
                    text: $repsText
                ) { val in
                    logEntry.reps = Int(val)
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.sfSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(isCurrent ? Color.sfAccent.opacity(0.4) : .clear, lineWidth: 1.5)
                )
        )
        .onAppear {
            if let r = logEntry.reps   { repsText   = "\(r)" }
            if let w = logEntry.weight { weightText  = w.weightFormatted }
        }
    }

    private func logField(
        icon: String,
        placeholder: String,
        suffix: String,
        text: Binding<String>,
        onChange: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)
                Text(placeholder)
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .font(.sfCounter)
                    .fontWeight(.semibold)
                    .onChange(of: text.wrappedValue) { _, new in
                        onChange(new)
                    }
                Text(suffix)
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .frame(maxWidth: .infinity)
    }
}
