import SwiftUI

struct WorkoutSummaryView: View {
    let workoutName: String
    let durationSeconds: Int
    let completedSets: Int
    let totalSets: Int
    let onDismiss: () -> Void

    private var completionPercent: Int {
        guard totalSets > 0 else { return 100 }
        return Int(Double(completedSets) / Double(totalSets) * 100)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.sfAccent)
                .padding(.bottom, Spacing.md)

            // Title
            Text("Workout Complete")
                .font(.sfTitle)
                .padding(.bottom, Spacing.xs)

            Text(workoutName)
                .font(.sfCallout)
                .foregroundStyle(.secondary)

            Spacer().frame(height: Spacing.xl)

            // Stats grid
            HStack(spacing: Spacing.lg) {
                statItem(value: durationSeconds.timerFormatted, label: "Duration")
                Divider().frame(height: 40)
                statItem(value: "\(completedSets)", label: "Sets Done")
                Divider().frame(height: 40)
                statItem(value: "\(completionPercent)%", label: "Complete")
            }
            .padding(Spacing.lg)
            .background(Color.sfSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .padding(.horizontal, Spacing.md)

            Spacer()

            // Motivational note
            Text(motivationalNote)
                .font(.sfCallout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            Spacer()

            // Done button
            Button("Done") {
                onDismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.sfCounter)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(label)
                .font(.sfCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var motivationalNote: String {
        let notes = [
            "Consistency beats intensity every time.",
            "One more session than last week. That's progress.",
            "The work you put in today is the result you see tomorrow.",
            "You showed up. That's 90% of it.",
            "Rest well. You've earned it.",
        ]
        return notes[completedSets % notes.count]
    }
}

#Preview {
    WorkoutSummaryView(
        workoutName: "Push Day",
        durationSeconds: 2820,
        completedSets: 4,
        totalSets: 4,
        onDismiss: {}
    )
}
