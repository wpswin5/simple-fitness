import SwiftUI
import Charts
import SwiftData

// MARK: - Supporting Types

enum ProgressTimeRange: String, CaseIterable {
    case oneMonth    = "1M"
    case threeMonths = "3M"
    case sixMonths   = "6M"
    case allTime     = "All"

    var days: Int? {
        switch self {
        case .oneMonth:    return 30
        case .threeMonths: return 90
        case .sixMonths:   return 180
        case .allTime:     return nil
        }
    }
}

struct ExerciseDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let maxWeight: Double
}

// MARK: - Progress Dashboard

struct ProgressDashboardView: View {
    @Query(
        filter: #Predicate<WorkoutLog> { $0.isComplete == true },
        sort: \WorkoutLog.startDate, order: .reverse
    ) private var logs: [WorkoutLog]

    @State private var selectedExerciseName: String? = nil
    @State private var selectedRange: ProgressTimeRange = .threeMonths
    @State private var isPickerPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if logs.isEmpty {
                    emptyState
                } else {
                    logList
                }
            }
            .navigationTitle("Progress")
            .sheet(isPresented: $isPickerPresented) {
                ExerciseNamePickerSheet(
                    names: allExerciseNames,
                    selected: $selectedExerciseName
                )
            }
        }
    }

    // MARK: - Main Content

    private var logList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                summaryStrip
                exerciseProgressSection
                historySection
            }
            .padding(Spacing.md)
        }
    }

    // MARK: - Summary Strip

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryItem(value: "\(logs.count)",          label: "Workouts",   icon: "dumbbell.fill")
            Divider().frame(height: 40)
            summaryItem(value: totalDurationFormatted,   label: "Total Time", icon: "clock.fill")
            Divider().frame(height: 40)
            summaryItem(value: currentStreakText,        label: "Streak",     icon: "flame.fill")
        }
        .padding(Spacing.md)
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func summaryItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.sfCaption)
                .foregroundStyle(Color.sfAccent)
            Text(value)
                .font(.sfHeadline)
            Text(label)
                .font(.sfCaption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Exercise Progress Section

    private var exerciseProgressSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Exercise Progress")

            // Exercise picker button
            Button(action: { isPickerPresented = true }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exercise")
                            .font(.sfCaption2)
                            .foregroundStyle(.secondary)
                        Text(selectedExerciseName ?? "Select an exercise")
                            .font(.sfSubhead)
                            .foregroundStyle(selectedExerciseName != nil ? Color.primary : Color.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sfAccent)
                }
                .padding(Spacing.md)
                .background(Color.sfSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)

            if selectedExerciseName != nil {
                // Time range segmented control
                timeRangePicker

                // Stats row
                statsRow

                // Chart
                strengthChart
            }
        }
    }

    private var timeRangePicker: some View {
        HStack(spacing: 0) {
            ForEach(ProgressTimeRange.allCases, id: \.self) { range in
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { selectedRange = range } }) {
                    Text(range.rawValue)
                        .font(.sfCaption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xs)
                        .foregroundStyle(selectedRange == range ? Color.white : Color.primary)
                        .background(selectedRange == range ? Color.sfAccent : Color.sfSurface)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private var statsRow: some View {
        HStack(spacing: Spacing.xs) {
            statCard(title: "Max Weight", value: maxWeightDisplay, delta: maxWeightDelta)
            statCard(title: "Max Reps",   value: maxRepsDisplay,   delta: maxRepsDelta)
            statCard(title: "Avg RPE",    value: avgRPEDisplay,    delta: nil)
        }
    }

    private func statCard(title: String, value: String, delta: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.sfCaption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.sfHeadline)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let delta = delta {
                Text(delta)
                    .font(.sfCaption2)
                    .foregroundStyle(Color.sfAccent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private var strengthChart: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Strength Trend")
                .font(.sfSubhead)

            if filteredDataPoints.isEmpty {
                VStack(spacing: Spacing.xs) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.sfAccent.opacity(0.5))
                    Text("No data in this period")
                        .font(.sfCaption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 140)
            } else {
                Chart(filteredDataPoints) { point in
                    AreaMark(
                        x: .value("Date",   point.date),
                        y: .value("Weight", point.maxWeight)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.sfAccent.opacity(0.25), Color.sfAccent.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date",   point.date),
                        y: .value("Weight", point.maxWeight)
                    )
                    .foregroundStyle(Color.sfAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date",   point.date),
                        y: .value("Weight", point.maxWeight)
                    )
                    .foregroundStyle(Color.sfAccent)
                    .symbolSize(28)
                }
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                        AxisValueLabel(format: xAxisFormat)
                            .font(.sfCaption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                        AxisValueLabel {
                            if let w = value.as(Double.self) {
                                Text("\(Int(w))")
                                    .font(.sfCaption2)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(Spacing.md)
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("History")
            ForEach(logs) { log in
                WorkoutLogCard(log: log)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 52))
                .foregroundStyle(Color.sfAccent.opacity(0.6))
            VStack(spacing: Spacing.xs) {
                Text("No data yet")
                    .font(.sfHeadline)
                Text("Complete a workout to see your progress here.")
                    .font(.sfCallout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Spacing.xl)
    }

    // MARK: - Shared Helper

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sfSubhead)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.5)
    }

    // MARK: - Data Derivation

    /// All unique exercise names that appear in completed logs
    private var allExerciseNames: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for log in logs {
            for setLog in log.setLogs {
                for exLog in setLog.exerciseLogs {
                    let name = exLog.exerciseName
                    if seen.insert(name).inserted {
                        names.append(name)
                    }
                }
            }
        }
        return names.sorted()
    }

    /// All data points for the selected exercise across all time (sorted oldest → newest)
    private var allDataPoints: [ExerciseDataPoint] {
        guard let name = selectedExerciseName else { return [] }
        var points: [ExerciseDataPoint] = []
        for log in logs {
            guard let date = log.completedDate else { continue }
            let weights = log.setLogs
                .flatMap { $0.exerciseLogs }
                .filter { $0.exerciseName == name }
                .compactMap { $0.weight }
            guard let maxW = weights.max() else { continue }
            points.append(ExerciseDataPoint(date: date, maxWeight: maxW))
        }
        return points.sorted { $0.date < $1.date }
    }

    /// Data points filtered to the selected time range
    private var filteredDataPoints: [ExerciseDataPoint] {
        guard let days = selectedRange.days else { return allDataPoints }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return allDataPoints.filter { $0.date >= cutoff }
    }

    /// All exercise logs for the selected exercise within the current time range
    private var filteredExerciseLogs: [ExerciseLog] {
        guard let name = selectedExerciseName else { return [] }
        let cutoff: Date
        if let days = selectedRange.days {
            cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        } else {
            cutoff = .distantPast
        }
        return logs
            .filter { ($0.completedDate ?? .distantPast) >= cutoff }
            .flatMap { $0.setLogs }
            .flatMap { $0.exerciseLogs }
            .filter { $0.exerciseName == name }
    }

    // MARK: - Stats

    private var maxWeightDisplay: String {
        guard let max = filteredExerciseLogs.compactMap(\.weight).max() else { return "—" }
        return "\(max.weightFormatted) lbs"
    }

    private var maxRepsDisplay: String {
        guard let max = filteredExerciseLogs.compactMap(\.reps).max() else { return "—" }
        return "\(max) reps"
    }

    private var avgRPEDisplay: String {
        let rpes = filteredExerciseLogs.compactMap(\.rpe)
        guard !rpes.isEmpty else { return "—" }
        return String(format: "%.1f / 10", rpes.reduce(0, +) / Double(rpes.count))
    }

    private var maxWeightDelta: String? {
        let curr = filteredExerciseLogs.compactMap(\.weight).max() ?? 0
        let prev  = previousPeriodLogs.compactMap(\.weight).max() ?? 0
        guard curr > 0, prev > 0, curr != prev else { return nil }
        let diff = curr - prev
        return diff > 0 ? "+\(diff.weightFormatted) lbs" : "\(diff.weightFormatted) lbs"
    }

    private var maxRepsDelta: String? {
        let curr = filteredExerciseLogs.compactMap(\.reps).max() ?? 0
        let prev  = previousPeriodLogs.compactMap(\.reps).max() ?? 0
        guard curr > 0, prev > 0, curr != prev else { return nil }
        let diff = curr - prev
        return diff > 0 ? "+\(diff) reps" : "\(diff) reps"
    }

    private var previousPeriodLogs: [ExerciseLog] {
        guard let name = selectedExerciseName, let days = selectedRange.days else { return [] }
        let end   = Calendar.current.date(byAdding: .day, value: -days,     to: Date()) ?? .distantPast
        let start = Calendar.current.date(byAdding: .day, value: -days * 2, to: Date()) ?? .distantPast
        return logs
            .filter {
                guard let d = $0.completedDate else { return false }
                return d >= start && d < end
            }
            .flatMap { $0.setLogs }
            .flatMap { $0.exerciseLogs }
            .filter { $0.exerciseName == name }
    }

    // MARK: - Chart Helpers

    private var yDomain: ClosedRange<Double> {
        guard !filteredDataPoints.isEmpty else { return 0...100 }
        let minW = (filteredDataPoints.map(\.maxWeight).min() ?? 0)  * 0.92
        let maxW = (filteredDataPoints.map(\.maxWeight).max() ?? 100) * 1.05
        return minW...maxW
    }

    private var xAxisFormat: Date.FormatStyle {
        switch selectedRange {
        case .oneMonth:              return .dateTime.day().month(.abbreviated)
        case .threeMonths, .sixMonths: return .dateTime.month(.abbreviated)
        case .allTime:               return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

    // MARK: - Summary Helpers

    private var totalDurationFormatted: String {
        let total = logs.reduce(0) { $0 + $1.durationSeconds }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private var currentStreakText: String {
        var streak = 0
        var checkDate = Calendar.current.startOfDay(for: Date())
        for _ in 0..<365 {
            let hasWorkout = logs.contains { log in
                guard let completed = log.completedDate else { return false }
                return Calendar.current.isDate(completed, inSameDayAs: checkDate)
            }
            if hasWorkout {
                streak += 1
                checkDate = Calendar.current.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else { break }
        }
        return "\(streak)d"
    }
}

// MARK: - Exercise Name Picker Sheet

private struct ExerciseNamePickerSheet: View {
    let names: [String]
    @Binding var selected: String?
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [String] {
        search.isEmpty ? names : names.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.self) { name in
                Button(action: { selected = name; dismiss() }) {
                    HStack {
                        Text(name)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        if selected == name {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.sfAccent)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Select Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sfAccent)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ProgressDashboardView()
        .modelContainer(for: [WorkoutLog.self, WorkoutSetLog.self, ExerciseLog.self], inMemory: true)
}
