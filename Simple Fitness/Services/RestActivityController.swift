import Foundation
import ActivityKit

// MARK: - RestActivityController
// Starts / ends the rest-countdown Live Activity. The Lock Screen countdown is
// driven by `Text(timerInterval:)` in the widget, so it ticks down on its own
// with no background updates from the app — we only start it (with the end date)
// and end it. No-ops safely when Live Activities are disabled or the widget
// extension isn't present yet.

nonisolated enum RestActivityController {

    static func start(workoutName: String, endDate: Date, nextUpLabel: String, nextUpTitle: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()   // never run two at once

        let attributes = RestActivityAttributes(workoutName: workoutName)
        let state = RestActivityAttributes.ContentState(
            endDate: endDate,
            nextUpLabel: nextUpLabel,
            nextUpTitle: nextUpTitle
        )
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: endDate),   // widget flips to "Go" at the end
                pushType: nil
            )
        } catch {
            // Live Activity couldn't start (disabled, or no widget extension yet) — ignore.
        }
    }

    static func end() {
        for activity in Activity<RestActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
