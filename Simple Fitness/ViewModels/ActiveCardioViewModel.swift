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

    // Time comes from the wall clock (the timer only drives the UI), so a locked phone
    // or backgrounded app never freezes the session; missed segments catch up on return.
    @ObservationIgnored nonisolated(unsafe) private var timer: Timer?
    @ObservationIgnored private var segmentStartDate: Date = Date()
    @ObservationIgnored private var hasStarted = false
    /// Actual time spent in each segment, recorded as it ends (nil = not reached).
    @ObservationIgnored private var actualDurations: [Int?] = []

    // MARK: - Init

    init(template: CardioTemplate) {
        self.template = template
        self.segments = template.sortedIntervals
        self.actualDurations = Array(repeating: nil, count: segments.count)
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
        guard !hasStarted else { return }
        hasStarted = true
        startDate = Date()
        segmentStartDate = startDate
        elapsedSeconds = 0
        segmentElapsed = 0
        startTimer()
    }

    /// Manual advance ("Next Segment"): the next segment starts now.
    func advance() {
        moveToNextSegment(startingAt: Date())
    }

    private func moveToNextSegment(startingAt date: Date) {
        if currentIndex < actualDurations.count {
            actualDurations[currentIndex] = max(0, Int(date.timeIntervalSince(segmentStartDate).rounded()))
        }
        if currentIndex + 1 < segments.count {
            currentIndex += 1
            segmentStartDate = date
            segmentElapsed = 0
        } else {
            complete(at: date)
        }
    }

    /// Recompute from the wall clock. Called every tick and on returning to the foreground.
    func refresh() {
        guard hasStarted, !isComplete else { return }
        let now = Date()
        // Timed segments that ended while we weren't ticking advance back-to-back,
        // each starting exactly when the previous one ended.
        while !isComplete, let dur = currentSegmentDuration,
              now.timeIntervalSince(segmentStartDate) >= TimeInterval(dur) {
            moveToNextSegment(startingAt: segmentStartDate.addingTimeInterval(TimeInterval(dur)))
        }
        guard !isComplete else { return }
        let elapsed = max(0, Int(now.timeIntervalSince(startDate)))
        if elapsed != elapsedSeconds { elapsedSeconds = elapsed }
        let segElapsed = max(0, Int(now.timeIntervalSince(segmentStartDate)))
        if segElapsed != segmentElapsed { segmentElapsed = segElapsed }
    }

    /// `date` is when the session actually ended — for a timed final segment that
    /// finished while the phone was locked, that's its end, not when the app woke up.
    func complete(at date: Date = Date()) {
        guard !isComplete else { return }
        elapsedSeconds = max(0, Int(date.timeIntervalSince(startDate)))
        stopTimer()
        isComplete = true
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
            // Prefer the measured time (distance/open segments have no planned duration).
            split.durationSeconds = idx < actualDurations.count ? actualDurations[idx] ?? seg.durationSeconds : seg.durationSeconds
            split.distanceValue = seg.distanceValue
            return split
        }
        return log
    }

    deinit {
        timer?.invalidate()
    }
}
