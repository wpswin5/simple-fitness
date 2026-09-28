import ActivityKit
import WidgetKit
import SwiftUI

struct RestActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            // Lock Screen / banner presentation
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REST · \(context.attributes.workoutName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(context.state.nextUpLabel.isEmpty ? "Rest" : "Up next · \(context.state.nextUpLabel)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if !context.state.nextUpTitle.isEmpty {
                        Text(context.state.nextUpTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                RestCountdown(endDate: context.state.endDate, isStale: context.isStale)
                    .font(.system(.title, design: .rounded).monospacedDigit())
                    .fontWeight(.bold)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 92)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.4))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Rest", systemImage: "timer").font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(endDate: context.state.endDate, isStale: context.isStale)
                        .font(.system(.title3, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(width: 68)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.nextUpTitle.isEmpty {
                        Text("Up next: \(context.state.nextUpTitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                RestCountdown(endDate: context.state.endDate, isStale: context.isStale)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }
}


/// Self-updating countdown to `endDate`. The app can't end the activity while it's
/// suspended, so once rest is over (stale) show "Go" instead of a frozen 0:00.
/// The range is clamped: `Date()...endDate` traps if the view renders after `endDate`.
private struct RestCountdown: View {
    let endDate: Date
    let isStale: Bool

    var body: some View {
        let now = Date()
        if isStale || endDate <= now {
            Text("Go")
        } else {
            Text(timerInterval: now...endDate, countsDown: true)
        }
    }
}
