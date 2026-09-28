import Foundation
import ActivityKit

// MARK: - RestActivityAttributes
// Shared between the app (which starts/ends the Live Activity) and the widget
// extension (which renders it on the Lock Screen / Dynamic Island).
//
// IMPORTANT: this file must belong to BOTH targets. After creating the widget
// extension, select this file in Xcode and tick the widget target under
// "Target Membership" in the File Inspector.

nonisolated struct RestActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// When the rest period ends — drives the live countdown via Text(timerInterval:).
        var endDate: Date
        /// e.g. "Set 2 of 9"
        var nextUpLabel: String
        /// e.g. "Bench Press"
        var nextUpTitle: String
    }

    /// Static for the life of the activity.
    var workoutName: String
}
