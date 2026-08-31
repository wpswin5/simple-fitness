import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var vm: ActiveWorkoutViewModel

    @State private var showingQuitConfirm = false
    @State private var showingSaveError = false
    @State private var showingOverview = false
    @FocusState private var fieldFocused: Bool

    init(workout: Workout) {
        _vm = State(wrappedValue: ActiveWorkoutViewModel(workout: workout))
    }

    // MARK: - Body

    var body: some View {
        Group {
            if vm.isResting {
                RestTimerView(
                    secondsRemaining: vm.restTimeRemaining,
                    totalSeconds: vm.currentRound?.restSeconds ?? 60,
                    nextUp: vm.nextUp,
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { vm.refresh() }
        }
        .confirmationDialog("Quit Workout?", isPresented: $showingQuitConfirm, titleVisibility: .visible) {
            Button("Quit Workout", role: .destructive) {
                RestNotifier.cancel()
                dismiss()
            }
            Button("Keep Going", role: .cancel) { }
        } message: {
            Text("Your progress won't be saved if you quit now.")
        }
        .alert("Couldn't Save Workout", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text("Your workout couldn't be saved due to a storage error. Please try again.")
        }
        .sheet(isPresented: $showingOverview) {
            WorkoutOverviewView(vm: vm)
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

                    // Exercise cards (one per exercise slot in the current round)
                    if let set = vm.currentSet {
                        ForEach(Array(vm.currentSlots.enumerated()), id: \.offset) { index, slot in
                            ExerciseLogCard(
                                exercise: slot,
                                target: vm.currentTarget(forExerciseIndex: index),
                                logEntry: binding(for: index),
                                isCurrent: index == vm.currentExerciseIndex,
                                isSuperset: set.isSuperset,
                                slotLabel: set.isSuperset ? Self.slotLetter(index) : nil,
                                focus: $fieldFocused
                            )
                        }
                    }

                    // Action button
                    actionButton
                        .padding(.top, Spacing.xs)
                }
                .padding(Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
        }
        .background(Color(.systemBackground))
    }

    /// "A", "B", "C" … for superset slot labels.
    static func slotLetter(_ index: Int) -> String {
        guard index >= 0, index < 26 else { return "\(index + 1)" }
        return String(UnicodeScalar(UInt8(65 + index)))
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

            // Workout overview (scroll the whole workout without losing your place)
            Button {
                showingOverview = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.sfSurface)
                    .clipShape(Circle())
            }
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

                if vm.currentSetRoundCount > 1 {
                    Text("Round \(vm.currentRoundIndex + 1) of \(vm.currentSetRoundCount)")
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
               vm.currentExerciseIndex < vm.currentSlots.count - 1 {
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

// MARK: - Workout Overview
// Read-only scroll of the whole workout with completed/current markers. Shown as a
// sheet, so the timer keeps running and the workout position is untouched.

struct WorkoutOverviewView: View {
    let vm: ActiveWorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(Array(vm.sortedSets.enumerated()), id: \.element.id) { setIndex, set in
                        setCard(setIndex: setIndex, set: set)
                    }
                }
                .padding(Spacing.md)
            }
            .navigationTitle(vm.workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func setCard(setIndex: Int, set: WorkoutSet) -> some View {
        let slots = set.sortedExercises
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Text("Set \(setIndex + 1)").font(.sfSubhead).fontWeight(.semibold)
                if set.isSuperset {
                    Text("Superset")
                        .font(.sfCaption2).fontWeight(.bold)
                        .foregroundStyle(Color.sfAccent)
                        .padding(.horizontal, Spacing.xs).padding(.vertical, 2)
                        .background(Color.sfAccent.opacity(0.12)).clipShape(Capsule())
                }
                Spacer()
            }

            // Exercise legend (letters map to A/B in the round rows)
            ForEach(Array(slots.enumerated()), id: \.element.id) { i, eis in
                HStack(spacing: Spacing.xs) {
                    if set.isSuperset {
                        Text(ActiveWorkoutView.slotLetter(i))
                            .font(.sfCaption2).fontWeight(.bold).foregroundStyle(.secondary)
                            .frame(width: 16)
                    }
                    Text(eis.exerciseName).font(.sfCallout)
                    Spacer()
                }
            }

            Divider()

            ForEach(Array(set.sortedRounds.enumerated()), id: \.element.id) { rIndex, round in
                roundRow(setIndex: setIndex, roundIndex: rIndex, round: round, set: set)
            }
        }
        .padding(Spacing.md)
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func roundRow(setIndex: Int, roundIndex: Int, round: SetRound, set: WorkoutSet) -> some View {
        let global = vm.globalRoundIndex(setIndex: setIndex, roundIndex: roundIndex)
        let done = global < vm.completedSetsCount
        let current = global == vm.completedSetsCount
        let slots = set.sortedExercises
        return HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: done ? "checkmark.circle.fill" : (current ? "arrowtriangle.right.circle.fill" : "circle"))
                .font(.system(size: 18))
                .foregroundStyle(done || current ? Color.sfAccent : Color.sfMuted)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(slots.enumerated()), id: \.element.id) { i, eis in
                    HStack(spacing: 4) {
                        Text(set.isSuperset ? "\(roundIndex + 1)\(ActiveWorkoutView.slotLetter(i))" : "\(roundIndex + 1)")
                            .font(.sfCaption2).fontWeight(.semibold).foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .leading)
                        Text(round.target(forSlot: eis.order)?.displaySummary ?? "—")
                            .font(.sfCaption)
                            .foregroundStyle(done ? .secondary : .primary)
                    }
                }
            }

            Spacer()

            if current {
                Text("Current").font(.sfCaption2).fontWeight(.semibold).foregroundStyle(Color.sfAccent)
            } else {
                Label("\(round.restSeconds)s", systemImage: "timer")
                    .font(.sfCaption2).foregroundStyle(.secondary)
            }
        }
        .opacity(done ? 0.6 : 1)
    }
}

// MARK: - Exercise Log Card

struct ExerciseLogCard: View {
    let exercise: ExerciseInSet
    let target: ExerciseTarget?
    @Binding var logEntry: ExerciseLogEntry
    let isCurrent: Bool
    let isSuperset: Bool
    var slotLabel: String? = nil
    var focus: FocusState<Bool>.Binding

    @State private var repsText: String = ""
    @State private var weightText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Exercise name + target
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        if let slotLabel {
                            Text(slotLabel)
                                .font(.sfCaption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(isCurrent ? Color.sfAccent : Color.sfMuted)
                                .clipShape(Circle())
                        }
                        Text(exercise.exerciseName)
                            .font(.sfHeadline)
                            .foregroundStyle(isCurrent ? Color.sfAccent : .primary)
                    }

                    if let target {
                        Text("Target: \(target.displaySummary)")
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
                logField(icon: "scalemass", placeholder: "Weight", suffix: "lbs", text: $weightText) { val in
                    logEntry.weight = Double(val)
                }
                logField(icon: "repeat", placeholder: "Reps", suffix: "reps", text: $repsText) { val in
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
                    .focused(focus)
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
