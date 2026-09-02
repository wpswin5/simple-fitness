// ─────────────────────────────────────────────────────────────────────────────
// REFERENCE FILE — do NOT leave this in the "Simple Fitness" app-source folder.
// It lives here (outside the app target) only so you can copy it.
//
// After you create the Widget Extension target ("RestActivity", with "Include
// Live Activity" checked), REPLACE the entire contents of the generated
// `RestActivityLiveActivity.swift` with everything below this comment block.
//
// Then:
//   1. Delete the sample `RestActivityAttributes` struct that Xcode generated
//      (this widget uses the SHARED one in Simple Fitness/RestActivityAttributes.swift).
//   2. Select Simple Fitness/RestActivityAttributes.swift → File Inspector →
//      tick the "RestActivity" target under Target Membership.
//   3. Set the RestActivity target's iOS Deployment Target to 26.4 (match the app).
//   4. The generated `RestActivityBundle.swift` (@main WidgetBundle) is fine as-is.
// ─────────────────────────────────────────────────────────────────────────────

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
