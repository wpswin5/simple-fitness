import Foundation
import UserNotifications

// MARK: - RestNotifier
// Schedules a local notification (with sound) for when a rest period ends, so the
// user is prompted even if the app is backgrounded or the phone is locked.
//
// Audio behavior: `UNNotificationSound` MIXES with other audio — music and podcasts
// keep playing, and a notification sound never pauses them. We deliberately do NOT
// touch `AVAudioSession` (a `.playback` session would duck/pause other audio).
//
// Foreground is intentionally left to default behavior (iOS suppresses the banner/
// sound while the app is active): if the user is watching the rest screen the UI
// already advances at 0, so a foreground alert would just be a redundant double-beep.

nonisolated enum RestNotifier {
    private static let identifier = "rest-over"

    /// Ask once (first workout). No-op if already decided.
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Schedule the rest-over alert for `date`. Replaces any pending one.
    static func scheduleRestOver(at date: Date) {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Time for your next set."
        content.sound = .default   // mixes with other audio; does not pause music

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.add(request)
    }

    /// Cancel a pending/delivered rest-over alert (rest skipped, finished early, or quit).
    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
