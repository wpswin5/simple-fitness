import SwiftUI
import SwiftData

struct ProgramDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let program: Program
    var registration: ProgramRegistration?

    @State private var activeWorkout: Workout? = nil
    @State private var showingLogCardio = false
    @State private var cardioToLog: CardioTemplate? = nil
    @State private var showingUnregisterConfirm = false
    @State private var showingEdit = false

    private var isRegistered: Bool { registration?.isActive == true }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                headerSection
                registrationSection
                scheduleSection
            }
            .padding(Spacing.md)
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
                    .foregroundStyle(Color.sfAccent)
            }
        }
        .fullScreenCover(item: $activeWorkout) { workout in
            ActiveWorkoutView(workout: workout)
        }
        .sheet(isPresented: $showingLogCardio) {
            LogCardioView(prefillType: cardioToLog?.cardioType)
        }
        .sheet(isPresented: $showingEdit) {
            CreateProgramView(editing: program)
        }
        .confirmationDialog("Unregister from Program?", isPresented: $showingUnregisterConfirm) {
            Button("Unregister", role: .destructive) { unregister() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your progress in this program will be lost.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !program.programDescription.isEmpty {
                Text(program.programDescription)
                    .font(.sfCallout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Spacing.lg) {
                infoChip(icon: "calendar",  label: "\(program.weeks.count) weeks")
                infoChip(icon: "target",    label: program.targetGoal.displayName)
                infoChip(icon: "chart.bar", label: program.difficultyLevel.displayName)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.sfCaption).foregroundStyle(Color.sfAccent)
            Text(label).font(.sfCaption).foregroundStyle(.primary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(Color.sfSurface)
        .clipShape(Capsule())
    }

    // MARK: - Registration Section

    private var registrationSection: some View {
        VStack(spacing: Spacing.sm) {
            if isRegistered, let reg = registration {
                VStack(spacing: Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("In Progress", systemImage: "bolt.fill")
                                .font(.sfCaption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.sfAccent)
                            Text("Week \(reg.currentWeek) of \(program.weeks.count)")
                                .font(.sfHeadline)
                        }
                        Spacer()
                        let progress = Double(reg.currentWeek - 1) / Double(max(program.weeks.count, 1))
                        ZStack {
                            Circle().stroke(Color.sfSurface, lineWidth: 5)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(Color.sfAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(Int(progress * 100))%")
                                .font(.sfCaption2).fontWeight(.bold)
                        }
                        .frame(width: 48, height: 48)
                    }

                    // Today's activities (supports multiple per day)
                    let todayItems = todayActivities(for: reg)
                    if !todayItems.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Today")
                                .font(.sfCaption)
                                .foregroundStyle(.secondary)
                            ForEach(Array(todayItems.enumerated()), id: \.offset) { _, plan in
                                HStack {
                                    switch plan {
                                    case .workout(let workout):
                                        HStack(spacing: Spacing.xs) {
                                            Image(systemName: "dumbbell.fill")
                                                .font(.sfCaption2).foregroundStyle(Color.sfAccent)
                                            Text(workout.name).font(.sfSubhead)
                                        }
                                        Spacer()
                                        Button("Start") { activeWorkout = workout }
                                            .buttonStyle(PrimaryButtonStyle())
                                            .frame(maxWidth: 100)
                                    case .cardio(let template):
                                        HStack(spacing: Spacing.xs) {
                                            Image(systemName: template.cardioType.icon)
                                                .font(.sfCaption2).foregroundStyle(Color.sfAccent)
                                            Text(template.displayName).font(.sfSubhead)
                                        }
                                        Spacer()
                                        Button("Log") {
                                            cardioToLog = template
                                            showingLogCardio = true
                                        }
                                        .buttonStyle(PrimaryButtonStyle())
                                        .frame(maxWidth: 100)
                                    case .rest:
                                        EmptyView()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.md)
                .background(Color.sfAccent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(Color.sfAccent.opacity(0.25), lineWidth: 1)
                )

                Button("Unregister") { showingUnregisterConfirm = true }
                    .buttonStyle(SecondaryButtonStyle())

            } else {
                VStack(spacing: Spacing.xs) {
                    Button("Register for Program") { register() }
                        .buttonStyle(PrimaryButtonStyle())
                    Text("Track your progress week by week")
                        .font(.sfCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Schedule")
                .font(.sfSubhead)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)

            ForEach(program.sortedWeeks) { week in
                weekCard(week: week)
            }
        }
    }

    private func weekCard(week: ProgramWeek) -> some View {
        let isCurrentWeek = registration?.currentWeek == week.weekNumber && isRegistered

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Week \(week.weekNumber)")
                    .font(.sfHeadline)
                    .foregroundStyle(isCurrentWeek ? Color.sfAccent : .primary)
                if isCurrentWeek {
                    Label("Current", systemImage: "arrow.left")
                        .font(.sfCaption2)
                        .foregroundStyle(Color.sfAccent)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.sfAccent.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
                let activeDays = week.days.filter { !$0.activities.isEmpty }.count
                Text("\(activeDays) active \(activeDays == 1 ? "day" : "days")")
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 1) {
                ForEach(week.days.sorted { $0.dayOfWeek.sortOrder < $1.dayOfWeek.sortOrder }) { day in
                    dayRow(day: day)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .padding(Spacing.md)
        .background(isCurrentWeek ? Color.sfAccent.opacity(0.06) : Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(isCurrentWeek ? Color.sfAccent.opacity(0.3) : .clear, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func dayRow(day: ProgramDay) -> some View {
        let sorted = day.sortedActivities
        if sorted.isEmpty {
            // Rest day
            HStack {
                Text(day.dayOfWeek.shortName)
                    .font(.sfCaption).fontWeight(.semibold)
                    .foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "moon.fill").font(.sfCaption2).foregroundStyle(.secondary)
                    Text("Rest").font(.sfCallout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        } else {
            // One row per activity; day label only on first row
            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, activity in
                    HStack {
                        // Day abbreviation — only shown on the first activity row
                        if index == 0 {
                            Text(day.dayOfWeek.shortName)
                                .font(.sfCaption).fontWeight(.semibold)
                                .foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
                        } else {
                            Spacer().frame(width: 36)
                        }

                        // Activity content
                        if let workout = activity.workout {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "dumbbell.fill")
                                    .font(.sfCaption2).foregroundStyle(Color.sfAccent)
                                Text(workout.name).font(.sfCallout).foregroundStyle(.primary)
                            }
                        } else if let cardio = activity.cardioTemplate {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: cardio.cardioType.icon)
                                    .font(.sfCaption2).foregroundStyle(Color.sfAccent)
                                Text(cardio.displayName).font(.sfCallout).foregroundStyle(.primary)
                                if cardio.isIntervalWorkout {
                                    Text("Intervals")
                                        .font(.sfCaption2).foregroundStyle(Color.sfAccent)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.sfAccent.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                        }

                        Spacer()

                        // Per-activity action button (registered users only)
                        if isRegistered {
                            if let workout = activity.workout {
                                Button { activeWorkout = workout } label: {
                                    Image(systemName: "play.circle")
                                        .foregroundStyle(Color.sfAccent).font(.system(size: 20))
                                }
                                .buttonStyle(.plain)
                            } else if let cardio = activity.cardioTemplate {
                                Button {
                                    cardioToLog = cardio
                                    showingLogCardio = true
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Color.sfAccent).font(.system(size: 20))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))

                    if index < sorted.count - 1 {
                        Divider().padding(.leading, 36 + Spacing.sm * 2)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private enum TodaysPlan {
        case workout(Workout)
        case cardio(CardioTemplate)
        case rest
    }

    /// Returns all planned activities for today's slot in the current program week.
    private func todayActivities(for reg: ProgramRegistration) -> [TodaysPlan] {
        let weekIndex = reg.currentWeek - 1
        guard weekIndex < program.sortedWeeks.count else { return [] }
        let week = program.sortedWeeks[weekIndex]
        let todayDOW = Calendar.current.component(.weekday, from: Date())
        let dayMap: [Int: DayOfWeek] = [
            1: .sunday, 2: .monday, 3: .tuesday, 4: .wednesday,
            5: .thursday, 6: .friday, 7: .saturday
        ]
        guard let today = dayMap[todayDOW],
              let day = week.days.first(where: { $0.dayOfWeek == today }) else { return [] }

        return day.sortedActivities.compactMap { activity in
            if let workout = activity.workout { return .workout(workout) }
            if let cardio = activity.cardioTemplate { return .cardio(cardio) }
            return nil
        }
    }

    private func register() {
        let reg = ProgramRegistration(program: program)
        modelContext.insert(reg)
        try? modelContext.save()
    }

    private func unregister() {
        registration?.isActive = false
        try? modelContext.save()
    }
}

// MARK: - DayOfWeek sort order

extension DayOfWeek {
    var sortOrder: Int {
        switch self {
        case .monday:    return 0
        case .tuesday:   return 1
        case .wednesday: return 2
        case .thursday:  return 3
        case .friday:    return 4
        case .saturday:  return 5
        case .sunday:    return 6
        }
    }
}
