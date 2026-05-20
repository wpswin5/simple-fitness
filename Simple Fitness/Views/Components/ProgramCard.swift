import SwiftUI

struct ProgramCard: View {
    let program: Program
    var isActive: Bool = false
    var currentWeek: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Spacing.xs) {
                        if isActive {
                            Label("Active", systemImage: "bolt.fill")
                                .font(.sfCaption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.sfAccent)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 2)
                                .background(Color.sfAccent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Text(program.difficultyLevel.displayName)
                            .font(.sfCaption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.sfSurface)
                            .clipShape(Capsule())
                    }

                    Text(program.name)
                        .font(.sfHeadline)
                        .foregroundStyle(.primary)

                    if !program.programDescription.isEmpty {
                        Text(program.programDescription)
                            .font(.sfCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()

                // Goal badge
                VStack(spacing: 2) {
                    Image(systemName: goalIcon(program.targetGoal))
                        .font(.system(size: 18))
                        .foregroundStyle(Color.sfAccent)
                    Text(program.targetGoal.displayName)
                        .font(.sfCaption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Stats row
            HStack(spacing: Spacing.lg) {
                statLabel(icon: "calendar", value: "\(program.weeks.count)", label: "weeks")
                statLabel(icon: "dumbbell", value: "\(totalWorkoutDays)", label: "workouts")
                if isActive, let week = currentWeek {
                    statLabel(icon: "flag", value: "Week \(week)", label: "current")
                }
            }

            // Progress bar (if active)
            if isActive, let week = currentWeek {
                let progress = Double(week - 1) / Double(max(program.weeks.count, 1))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.sfSurface)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.sfAccent)
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .cardStyle()
    }

    private var totalWorkoutDays: Int {
        program.weeks.reduce(0) { weekTotal, week in
            weekTotal + week.days.filter { !$0.isRestDay }.count
        }
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
                Text(label)
                    .font(.sfCaption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func goalIcon(_ goal: TrainingGoal) -> String {
        switch goal {
        case .strengthGain:   return "figure.strengthtraining.traditional"
        case .hypertrophy:    return "figure.arms.open"
        case .endurance:      return "figure.run"
        case .athleticism:    return "figure.mixed.cardio"
        case .weightLoss:     return "flame.fill"
        case .conditioning:   return "heart.fill"
        }
    }
}
