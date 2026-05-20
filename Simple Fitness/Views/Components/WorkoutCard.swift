import SwiftUI

struct WorkoutCard: View {
    let workout: Workout
    var onStart: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Header row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.name)
                        .font(.sfHeadline)
                        .foregroundStyle(.primary)

                    if !workout.workoutDescription.isEmpty {
                        Text(workout.workoutDescription)
                            .font(.sfCaption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let start = onStart {
                    Button(action: start) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.sfAccent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Stats row
            HStack(spacing: Spacing.lg) {
                statLabel(
                    icon: "list.bullet",
                    value: "\(workout.sortedSets.count)",
                    label: workout.sortedSets.count == 1 ? "set" : "sets"
                )
                if workout.setRepetitions > 1 {
                    statLabel(
                        icon: "repeat",
                        value: "×\(workout.setRepetitions)",
                        label: "rounds"
                    )
                }
                if workout.estimatedDuration > 0 {
                    statLabel(
                        icon: "clock",
                        value: "\(workout.estimatedDuration)",
                        label: "min"
                    )
                }
                statLabel(
                    icon: "dumbbell",
                    value: "\(workout.exerciseCount)",
                    label: workout.exerciseCount == 1 ? "exercise" : "exercises"
                )
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func statLabel(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.sfCaption)
                .foregroundStyle(Color.sfAccent)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.sfCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.sfCaption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Log Card

struct WorkoutLogCard: View {
    let log: WorkoutLog

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(log.workoutName)
                    .font(.sfSubhead)
                    .foregroundStyle(.primary)
                if let completed = log.completedDate {
                    Text(completed, style: .date)
                        .font(.sfCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(log.durationFormatted)
                    .font(.sfCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text("\(log.setLogs.count) sets")
                    .font(.sfCaption2)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }
}
