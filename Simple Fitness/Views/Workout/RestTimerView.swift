import SwiftUI

struct RestTimerView: View {
    let secondsRemaining: Int
    let totalSeconds: Int
    let onSkip: () -> Void

    private var progress: Double {
        guard totalSeconds > 0 else { return 1 }
        return 1.0 - Double(secondsRemaining) / Double(totalSeconds)
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Label
            Text("Rest")
                .font(.sfHeadline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(1.5)

            // Ring timer
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.sfSurface, lineWidth: 10)
                    .frame(width: 220, height: 220)

                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.sfAccent,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 220, height: 220)
                    .animation(.linear(duration: 1), value: progress)

                // Time remaining
                VStack(spacing: 4) {
                    Text(secondsRemaining.timerFormatted)
                        .font(.sfTimer)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))

                    Text("remaining")
                        .font(.sfCaption)
                        .foregroundStyle(.secondary)
                }
            }

            // Skip button
            Button("Skip Rest") {
                onSkip()
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(maxWidth: 200)

            Spacer()

            // Upcoming set preview
            Text("Next set coming up…")
                .font(.sfCaption)
                .foregroundStyle(.secondary)
                .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    RestTimerView(secondsRemaining: 45, totalSeconds: 90, onSkip: {})
}
