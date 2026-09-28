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
                Text(timerInterval: Date()...context.state.endDate, countsDown: true)
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
                    Text(timerInterval: Date()...context.state.endDate, countsDown: true)
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
                Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }
}

