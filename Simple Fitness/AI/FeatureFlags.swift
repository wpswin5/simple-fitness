import Foundation

/// App-wide feature switches. Flip a value to toggle a feature everywhere it's gated.
enum FeatureFlags {

    /// AI workout generation (on-device Foundation Models).
    ///
    /// Parked while generation quality is revisited — notably superset variety
    /// (the current mapper caps supersets at 2 and drops them from main lifts
    /// first, so they rarely survive) and under-filled block counts on long
    /// sessions. Flipping this back to `true` restores the "Generate with AI"
    /// entry points in WorkoutListView. The underlying `AI/` code and the
    /// `GenerateWorkoutView` flow stay compiled either way, so re-enabling needs
    /// no other changes.
    static let aiWorkoutGeneration = false
}
