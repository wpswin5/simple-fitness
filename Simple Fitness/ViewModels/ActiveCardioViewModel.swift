import Foundation
import SwiftUI
import Observation

// MARK: - ActiveCardioViewModel
// Drives a guided cardio session by walking a template's ordered segments.
// Time-based segments auto-advance when their duration elapses; distance/open
// segments are advanced manually via the "Next Segment" button. On completion,
// buildLog() produces a CardioLog (splits mirror the segments) for the view to persist.

@MainActor
@Observable
final class ActiveCardioViewModel {

    let template: CardioTemplate
    private(set) var segments: [CardioTemplateInterval]

    // MARK: - State

    private(set) var currentIndex: Int = 0
    private(set) var elapsedSeconds: Int = 0     // whole-session timer
    private(set) var segmentElapsed: Int = 0     // time in the current segment
    private(set) var isComplete: Bool = false
    private(set) var startDate: Date = Date()

    nonisolated(unsafe) private var timer: Timer?

    // MARK: - Init

    init(template: CardioTemplate) {
        self.template = template
        self.segments = template.sortedIntervals
    }

    // MARK: - Computed

    var currentSegment: CardioTemplateInterval? {
        guard currentIndex < segments.count else { return nil }
        return segments[currentIndex]
    }

    var upNextSegment: CardioTemplateInterval? {
        let next = currentIndex + 1
        guard next < segments.count else { return nil }
        return segments[next]
    }

    var totalSegments: Int { segments.count }
    var isLastSegment: Bool { currentIndex >= segments.count - 1 }

    /// Target duration of the current segment if it is time-based.
    var currentSegmentDuration: Int? {
        guard let d = currentSegment?.durationSeconds, d > 0 else { return nil }
        return d
    }

    /// Countdown remaining for timed segments; nil for distance/open segments.
    var segmentRemaining: Int? {
        guard let dur = currentSegmentDuration else { return nil }
        return max(0, dur - segmentElapsed)
    }

    var progress: Double {
        guard totalSegments > 0 else { return 0 }
        return Double(currentIndex) / Double(totalSegments)
    }

    // MARK: - Lifecycle

    func start() {
        startDate = Date()
        elapsedSeconds = 0
        segmentElapsed = 0
        startTimer()
    }

    func advance() {
        if currentIndex + 1 < segments.count {
            currentIndex += 1
            segmentElapsed = 0
        } else {
            complete()
        }
    }

    func complete() {
        stopTimer()
        isComplete = true
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard !isComplete else { return }
        elapsedSeconds += 1
        segmentElapsed += 1
        if let dur = currentSegmentDuration, segmentElapsed >= dur {
            advance()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Persistence

    /// Builds a CardioLog (plus splits) for the completed session.
    /// The caller is responsible for inserting the log and its splits into the context.
    func buildLog() -> CardioLog {
        let log = CardioLog(cardioType: template.cardioType, date: Date())
        log.durationSeconds = elapsedSeconds
        log.distanceUnit = template.distanceUnit
        log.isIntervalWorkout = true
        log.notes = template.notes

        let totalDistance = segments.reduce(0.0) { $0 + ($1.distanceValue ?? 0) }
        if totalDistance > 0 { log.distanceValue = totalDistance }

        log.splits = segments.enumerated().map { idx, seg in
            let split = CardioSplit(order: idx, label: seg.label, isRest: seg.isRest)
            split.durationSeconds = seg.durationSeconds
            split.distanceValue = seg.distanceValue
            return split
        }
        return log
    }

    deinit {
        timer?.invalidate()
    }
}
