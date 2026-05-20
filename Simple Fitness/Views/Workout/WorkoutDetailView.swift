import SwiftUI

struct WorkoutDetailView: View {
    let workout: Workout

    @State private var activeWorkout: Workout? = nil
    @State private var showingEdit = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                headerSection
                setsSection
            }
            .padding(Spacing.md)
        }
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
                    .foregroundStyle(Color.sfAccent)
            }
        }
        .safeAreaInset(edge: .bottom) {
            startBar
        }
        .fullScreenCover(item: $activeWorkout) { w in
            ActiveWorkoutView(workout: w)
        }
        .sheet(isPresented: $showingEdit) {
            CreateWorkoutView(editing: workout)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !workout.workoutDescription.isEmpty {
                Text(workout.workoutDescription)
                    .font(.sfCallout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Spacing.sm) {
                infoChip(
                    icon: "list.bullet",
                    label: "\(workout.sortedSets.count) set\(workout.sortedSets.count == 1 ? "" : "s")"
                )
                if workout.setRepetitions > 1 {
                    infoChip(icon: "repeat", label: "×\(workout.setRepetitions) rounds")
                }
                infoChip(
                    icon: "dumbbell",
                    label: "\(workout.exerciseCount) exercise\(workout.exerciseCount == 1 ? "" : "s")"
                )
                if workout.estimatedDuration > 0 {
                    infoChip(icon: "clock", label: "~\(workout.estimatedDuration)m")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.sfCaption)
                .foregroundStyle(Color.sfAccent)
            Text(label)
                .font(.sfCaption)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(Color.sfSurface)
        .clipShape(Capsule())
    }

    // MARK: - Sets

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(workout.setRepetitions > 1
                 ? "Sets  ·  \(workout.setRepetitions)× rounds"
                 : "Sets")
                .font(.sfSubhead)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)

            if workout.sortedSets.isEmpty {
                HStack {
                    Spacer()
                    Text("No sets configured.")
                        .font(.sfCallout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(Spacing.xl)
                .background(Color.sfSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            } else {
                ForEach(Array(workout.sortedSets.enumerated()), id: \.element.id) { index, set in
                    setCard(index: index, set: set)
                }
            }
        }
    }

    private func setCard(index: Int, set: WorkoutSet) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Set header
            HStack {
                HStack(spacing: Spacing.xs) {
                    Text("Set \(index + 1)")
                        .font(.sfSubhead)
                        .fontWeight(.semibold)
                    if set.isSuperset {
                        Text("Superset")
                            .font(.sfCaption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.sfAccent)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.sfAccent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Spacer()
                Label("\(set.restSeconds)s rest", systemImage: "timer")
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Exercises
            VStack(spacing: Spacing.xs) {
                ForEach(set.exercises, id: \.id) { eis in
                    exerciseRow(eis: eis)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func exerciseRow(eis: ExerciseInSet) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "dumbbell.fill")
                .font(.sfCaption2)
                .foregroundStyle(Color.sfAccent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(eis.exerciseName)
                    .font(.sfCallout)
                    .foregroundStyle(.primary)
                if let muscleGroup = eis.exercise?.muscleGroup {
                    Text(muscleGroup.displayName)
                        .font(.sfCaption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let time = eis.targetTime {
                Text("\(time)s")
                    .font(.sfCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.sfAccent)
            } else if let reps = eis.targetReps {
                Text("\(reps) reps")
                    .font(.sfCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.sfAccent)
            }
        }
    }

    // MARK: - Start Bar

    private var startBar: some View {
        Button {
            activeWorkout = workout
        } label: {
            Label("Start Workout", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .background(.ultraThinMaterial)
    }
}
