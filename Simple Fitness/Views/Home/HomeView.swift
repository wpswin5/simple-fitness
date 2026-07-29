import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<WorkoutLog> { $0.isComplete == true },
        sort: \WorkoutLog.startDate, order: .reverse
    ) private var recentLogs: [WorkoutLog]

    @Query(sort: \Workout.createdDate, order: .reverse) private var workouts: [Workout]

    @Query(sort: \ProgramRegistration.startDate, order: .reverse) private var registrations: [ProgramRegistration]

    @State private var activeWorkout: Workout?
    @State private var cardioToStart: CardioTemplate?
    @State private var cardioToLog: CardioTemplate?
    @State private var showingLogCardio = false

    // MARK: - Active Program

    private var activeRegistration: ProgramRegistration? {
        registrations.first { $0.isActive }
    }

    /// Today's scheduled activities for the current program week.
    private var todaysActivities: [ProgramDayActivity] {
        guard let reg = activeRegistration, let program = reg.program else { return [] }
        let weekIndex = reg.currentWeek - 1
        let sortedWeeks = program.sortedWeeks
        guard weekIndex < sortedWeeks.count else { return [] }
        let week = sortedWeeks[weekIndex]
        let weekday = Calendar.current.component(.weekday, from: Date())
        let dayMap: [Int: DayOfWeek] = [
            1: .sunday, 2: .monday, 3: .tuesday, 4: .wednesday,
            5: .thursday, 6: .friday, 7: .saturday
        ]
        guard let today = dayMap[weekday],
              let day = week.days.first(where: { $0.dayOfWeek == today }) else { return [] }
        return day.sortedActivities
    }

    private var todaysProgramWorkout: Workout? {
        todaysActivities.compactMap { $0.workout }.first
    }

    private var todaysProgramCardio: CardioTemplate? {
        todaysActivities.compactMap { $0.cardioTemplate }.first
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    headerSection

                    // Program today section (takes priority over quick start)
                    if let reg = activeRegistration, let program = reg.program {
                        programTodaySection(reg: reg, program: program)
                    } else if let quickStart = workouts.first {
                        quickStartSection(workout: quickStart)
                    }

                    if !recentLogs.isEmpty {
                        recentHistorySection
                    }
                }
                .padding(Spacing.md)
            }
            .navigationTitle("Simple Fitness")
            .navigationBarTitleDisplayMode(.large)
            .fullScreenCover(item: $activeWorkout) { workout in
                ActiveWorkoutView(workout: workout)
            }
            .fullScreenCover(item: $cardioToStart) { template in
                ActiveCardioView(template: template)
            }
            .sheet(isPresented: $showingLogCardio) {
                LogCardioView(prefillType: cardioToLog?.cardioType)
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(.sfTitle)
                .foregroundStyle(.primary)
            Text(subtitleText)
                .font(.sfCallout)
                .foregroundStyle(.secondary)
        }
    }

    private func programTodaySection(reg: ProgramRegistration, program: Program) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                sectionHeader("Today")
                Spacer()
                Text("\(program.name) · Week \(reg.currentWeek)")
                    .font(.sfCaption)
                    .foregroundStyle(Color.sfAccent)
            }

            let workout = todaysProgramWorkout
            let cardio = todaysProgramCardio

            if workout == nil && cardio == nil {
                // Rest day card
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.sfAccent.opacity(0.7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest Day")
                            .font(.sfHeadline)
                        Text("Recovery is part of the program.")
                            .font(.sfCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .cardStyle()
            } else {
                if let workout {
                    WorkoutCard(workout: workout) { activeWorkout = workout }
                }
                if let cardio {
                    cardioTodayCard(cardio)
                }
            }
        }
    }

    private func cardioTodayCard(_ template: CardioTemplate) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: template.cardioType.icon)
                .font(.system(size: 22))
                .foregroundStyle(Color.sfAccent)
                .frame(width: 44, height: 44)
                .background(Color.sfAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name.isEmpty ? template.displayName : template.name)
                    .font(.sfHeadline)
                Text(template.displayName)
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if template.isStructured {
                Button("Start") { cardioToStart = template }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: 90)
            } else {
                Button("Log") { cardioToLog = template; showingLogCardio = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: 90)
            }
        }
        .cardStyle()
    }

    private func quickStartSection(workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Quick Start")
            WorkoutCard(workout: workout) {
                activeWorkout = workout
            }
        }
    }

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Recent Workouts")
            ForEach(recentLogs.prefix(5)) { log in
                WorkoutLogCard(log: log)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sfSubhead)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.5)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning."
        case 12..<17: return "Good afternoon."
        default:     return "Good evening."
        }
    }

    private var subtitleText: String {
        if let reg = activeRegistration, let program = reg.program {
            return "\(program.name) · Week \(reg.currentWeek) of \(program.weeks.count)"
        }
        if recentLogs.isEmpty { return "Ready to start your first workout?" }
        guard let last = recentLogs.first, let completed = last.completedDate else {
            return "Let's train."
        }
        let days = Calendar.current.dateComponents([.day], from: completed, to: Date()).day ?? 0
        switch days {
        case 0:  return "Great work today. Rest up."
        case 1:  return "Yesterday: \(last.workoutName). Keep it going."
        default: return "\(days) days since your last workout. Time to move."
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [
            Workout.self, WorkoutSet.self, ExerciseInSet.self, Exercise.self,
            WorkoutLog.self, WorkoutSetLog.self, ExerciseLog.self,
            Program.self, ProgramWeek.self, ProgramDay.self, ProgramDayActivity.self,
            ProgramRegistration.self
        ], inMemory: true)
}
