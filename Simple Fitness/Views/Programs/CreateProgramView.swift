import SwiftUI
import SwiftData

struct CreateProgramView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var vm: CreateProgramViewModel
    @State private var pickingFor: (weekID: UUID, dayID: UUID)? = nil
    @State private var showingError = false

    init(editing program: Program? = nil) {
        _vm = State(wrappedValue: program.map { CreateProgramViewModel(editing: $0) } ?? CreateProgramViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    infoSection
                    weeksSection
                    if !vm.weeks.isEmpty {
                        summaryCard
                    }
                }
                .padding(Spacing.md)
            }
            .navigationTitle(vm.isEditing ? "Edit Program" : "New Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(vm.isValid ? Color.sfAccent : .secondary)
                        .disabled(!vm.isValid)
                }
            }
            .sheet(isPresented: Binding(
                get: { pickingFor != nil },
                set: { if !$0 { pickingFor = nil } }
            )) {
                if let picking = pickingFor,
                   let week = vm.weeks.first(where: { $0.id == picking.weekID }),
                   let day = week.days.first(where: { $0.id == picking.dayID }) {
                    DayActivitiesSheet(day: day) { updatedActivities in
                        vm.setActivities(updatedActivities, forDay: picking.dayID, inWeek: picking.weekID)
                        pickingFor = nil
                    }
                }
            }
            .alert("Missing Info", isPresented: $showingError, presenting: vm.errorMessage) { _ in
                Button("OK", role: .cancel) { vm.errorMessage = nil }
            } message: { msg in Text(msg) }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Program Details")

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "pencil").foregroundStyle(.secondary).frame(width: 20)
                    TextField("Program name", text: $vm.programName)
                        .font(.sfSubhead)
                        .autocorrectionDisabled()
                }
                .padding(Spacing.md)

                Divider().padding(.leading, Spacing.md + 20)

                HStack(alignment: .top) {
                    Image(systemName: "text.alignleft").foregroundStyle(.secondary).frame(width: 20).padding(.top, 2)
                    TextField("Description (optional)", text: $vm.programDescription, axis: .vertical)
                        .font(.sfCallout)
                        .lineLimit(1...3)
                        .autocorrectionDisabled()
                }
                .padding(Spacing.md)

                Divider().padding(.leading, Spacing.md + 20)

                HStack {
                    Image(systemName: "target").foregroundStyle(.secondary).frame(width: 20)
                    Text("Goal").font(.sfSubhead)
                    Spacer()
                    Picker("Goal", selection: $vm.targetGoal) {
                        ForEach(TrainingGoal.allCases, id: \.self) { goal in
                            Text(goal.displayName).tag(goal)
                        }
                    }
                    .tint(Color.sfAccent)
                }
                .padding(Spacing.md)

                Divider().padding(.leading, Spacing.md + 20)

                HStack {
                    Image(systemName: "chart.bar").foregroundStyle(.secondary).frame(width: 20)
                    Text("Difficulty").font(.sfSubhead)
                    Spacer()
                    Picker("Difficulty", selection: $vm.difficultyLevel) {
                        ForEach(DifficultyLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .tint(Color.sfAccent)
                }
                .padding(Spacing.md)
            }
            .background(Color.sfSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    // MARK: - Weeks Section

    private var weeksSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                sectionHeader("Schedule")
                Spacer()
                HStack(spacing: Spacing.sm) {
                    Button {
                        withAnimation { vm.removeLastWeek() }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(vm.weeks.count > 1 ? Color.sfAccent : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.weeks.count <= 1)

                    Text("\(vm.weeks.count)w")
                        .font(.sfSubhead)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .frame(minWidth: 32, alignment: .center)

                    Button {
                        withAnimation { vm.addWeek() }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(vm.weeks.count < 16 ? Color.sfAccent : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.weeks.count >= 16)
                }
            }

            if vm.weeks.count > 1 {
                Text("Tip: long-press a week to copy Week 1's schedule to it.")
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)
            }

            ForEach(vm.weeks) { week in
                weekEditor(week: week)
            }
        }
    }

    private func weekEditor(week: DraftProgramWeek) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Week \(week.weekNumber)")
                    .font(.sfHeadline)
                Spacer()
                Text("\(week.workoutDays) workout\(week.workoutDays == 1 ? "" : "s")")
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], Spacing.md)

            ForEach(week.days) { day in
                dayEditorRow(day: day, weekID: week.id)

                if day.dayOfWeek != week.days.last?.dayOfWeek {
                    Divider().padding(.leading, Spacing.md)
                }
            }
        }
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .contextMenu {
            if week.weekNumber > 1 {
                Button {
                    vm.copyWeekOne(to: week.id)
                } label: {
                    Label("Copy Week 1 Here", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private func dayEditorRow(day: DraftProgramDay, weekID: UUID) -> some View {
        Button {
            pickingFor = (weekID: weekID, dayID: day.id)
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(day.dayOfWeek.shortName)
                    .font(.sfCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)

                if day.isRestDay {
                    Text("Rest Day")
                        .font(.sfCallout)
                        .foregroundStyle(.tertiary)
                } else if day.activities.count == 1, let activity = day.activities.first {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: activity.icon)
                            .font(.sfCaption2)
                            .foregroundStyle(Color.sfAccent)
                        Text(activity.displayName)
                            .font(.sfCallout)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                } else {
                    // Multiple activities — show stacked icons + count
                    HStack(spacing: Spacing.xs) {
                        ForEach(day.activities.prefix(3)) { activity in
                            Image(systemName: activity.icon)
                                .font(.sfCaption2)
                                .foregroundStyle(Color.sfAccent)
                        }
                        Text("\(day.activities.count) activities")
                            .font(.sfCallout)
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.sfCaption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryItem(icon: "calendar",  value: "\(vm.totalWeeks)",       label: "Weeks")
            Divider().frame(height: 36)
            summaryItem(icon: "dumbbell",  value: "\(vm.totalWorkoutDays)", label: "Active Days")
            Divider().frame(height: 36)
            summaryItem(icon: "moon.fill", value: "\(vm.totalWeeks * 7 - vm.totalWorkoutDays)", label: "Rest Days")
        }
        .padding(Spacing.md)
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func summaryItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.sfCaption).foregroundStyle(Color.sfAccent)
            Text(value).font(.sfSubhead).fontWeight(.semibold)
            Text(label).font(.sfCaption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sfSubhead)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.5)
    }

    private func save() {
        if vm.save(context: modelContext) {
            dismiss()
        } else {
            showingError = vm.errorMessage != nil
        }
    }
}

// MARK: - Day Activities Sheet

/// Manages the list of activities for a single program day.
/// The user can add multiple workouts/cardio sessions and delete existing ones.
struct DayActivitiesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let day: DraftProgramDay
    let onSave: ([DraftProgramActivity]) -> Void

    @State private var activities: [DraftProgramActivity]
    @State private var showingPicker = false

    init(day: DraftProgramDay, onSave: @escaping ([DraftProgramActivity]) -> Void) {
        self.day = day
        self.onSave = onSave
        _activities = State(initialValue: day.activities.sorted { $0.order < $1.order })
    }

    var body: some View {
        NavigationStack {
            List {
                // Current activities
                if !activities.isEmpty {
                    Section {
                        ForEach(activities) { activity in
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: activity.icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.sfAccent)
                                    .frame(width: 28, height: 28)
                                    .background(Color.sfAccent.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(activity.displayName)
                                        .font(.sfSubhead)
                                    Text(activity.isWorkout ? "Strength" : "Cardio")
                                        .font(.sfCaption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { activities.remove(atOffsets: $0) }
                    } header: {
                        Text("Scheduled — \(activities.count) activit\(activities.count == 1 ? "y" : "ies")")
                    } footer: {
                        Text("Swipe to remove. Tap \"Add Activity\" to stack more on this day.")
                    }
                }

                // Add activity
                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add Activity", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.sfAccent)
                    }
                    .buttonStyle(.plain)
                }

                // Clear to rest day
                if !activities.isEmpty {
                    Section {
                        Button("Set as Rest Day", role: .destructive) {
                            activities = []
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(day.dayOfWeek.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.sfAccent)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ActivityPickerSheet { newActivity in
                    activities.append(newActivity)
                }
            }
        }
    }

    private func save() {
        let reordered = activities.enumerated().map { i, a in
            var updated = a; updated.order = i; return updated
        }
        onSave(reordered)
        dismiss()
    }
}

// MARK: - Activity Picker Sheet

/// Picks a single activity (workout or cardio) to add to a day.
/// Calls onAdd then dismisses itself — the caller appends to its list.
struct ActivityPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.miles.rawValue

    @Query(sort: \Workout.name) private var workouts: [Workout]
    @Query(sort: \CardioTemplate.name) private var allTemplates: [CardioTemplate]

    let onAdd: (DraftProgramActivity) -> Void

    @State private var searchText = ""
    @State private var cardioTarget: DraftCardioTemplate? = nil

    private var filteredWorkouts: [Workout] {
        searchText.isEmpty ? workouts : workouts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var savedTemplates: [CardioTemplate] {
        allTemplates.filter { $0.isTemplate }
    }

    private func draftFromTemplate(_ template: CardioTemplate) -> DraftCardioTemplate {
        var draft = DraftCardioTemplate(type: template.cardioType)
        draft.distanceUnit      = template.distanceUnit
        draft.isIntervalWorkout = template.isIntervalWorkout
        draft.notes             = template.notes
        if template.targetDurationSeconds > 0 {
            let total = template.targetDurationSeconds
            let h = total / 3600; let m = (total % 3600) / 60; let s = total % 60
            draft.targetHours   = h > 0 ? "\(h)" : ""
            draft.targetMinutes = m > 0 ? "\(m)" : ""
            draft.targetSeconds = s > 0 ? "\(s)" : ""
        }
        if let dist = template.targetDistance, dist > 0 {
            draft.targetDistance = String(format: "%.2f", dist)
        }
        draft.intervals = template.sortedIntervals.map { iv in
            var di = DraftInterval()
            di.label  = iv.label; di.isRest = iv.isRest
            if let d = iv.distanceValue, d > 0 { di.distanceText = String(format: "%.2f", d) }
            if let p = iv.paceSecondsPerUnit, p > 0 {
                di.paceMinutes = "\(p / 60)"; di.paceSeconds = p % 60 > 0 ? "\(p % 60)" : ""
            }
            return di
        }
        return draft
    }

    var body: some View {
        NavigationStack {
            if let target = Binding($cardioTarget) {
                CardioTargetFormView(
                    draft: target,
                    distanceUnit: DistanceUnit(rawValue: distanceUnitRaw) ?? .miles,
                    onAssign: { draft in
                        onAdd(DraftProgramActivity(cardioTemplate: draft))
                        dismiss()
                    }
                )
            } else {
                List {
                    // Saved templates from library
                    if !savedTemplates.isEmpty {
                        Section("From Library") {
                            ForEach(savedTemplates) { template in
                                Button {
                                    cardioTarget = draftFromTemplate(template)
                                } label: {
                                    HStack {
                                        Image(systemName: template.cardioType.icon)
                                            .foregroundStyle(Color.sfAccent).frame(width: 28)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(template.name.isEmpty ? template.displayName : template.name)
                                                .font(.sfSubhead).foregroundStyle(.primary)
                                            Text(template.displayName)
                                                .font(.sfCaption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.sfCaption).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Cardio — custom
                    Section("Cardio") {
                        ForEach(CardioType.allCases, id: \.self) { type in
                            Button {
                                var draft = DraftCardioTemplate(type: type)
                                draft.distanceUnit = DistanceUnit(rawValue: distanceUnitRaw) ?? .miles
                                cardioTarget = draft
                            } label: {
                                HStack {
                                    Image(systemName: type.icon)
                                        .foregroundStyle(Color.sfAccent).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(type.displayName)
                                            .font(.sfSubhead).foregroundStyle(.primary)
                                        Text("Set target distance or duration")
                                            .font(.sfCaption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.sfCaption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Strength workouts
                    Section("Strength") {
                        if workouts.isEmpty {
                            Text("No workouts created yet")
                                .font(.sfCallout).foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredWorkouts) { workout in
                                Button {
                                    onAdd(DraftProgramActivity(workout: workout))
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "dumbbell.fill")
                                            .foregroundStyle(Color.sfAccent).frame(width: 28)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(workout.name)
                                                .font(.sfSubhead).foregroundStyle(.primary)
                                            Text("\(workout.sortedSets.count) sets · ~\(workout.estimatedDuration)min")
                                                .font(.sfCaption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle")
                                            .foregroundStyle(Color.sfAccent)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Search workouts")
                .navigationTitle("Add Activity")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }
}

// MARK: - Cardio Target Form

/// Step 2 of the day picker: configure targets for a cardio day.
struct CardioTargetFormView: View {
    @Binding var draft: DraftCardioTemplate
    let distanceUnit: DistanceUnit
    let onAssign: (DraftCardioTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            // Activity type picker
            Section("Type") {
                Picker("Activity", selection: $draft.type) {
                    ForEach(CardioType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.sm, bottom: Spacing.sm, trailing: Spacing.sm))
                .onChange(of: draft.type) { _, newType in
                    // Clear interval toggle when switching to swimming (no interval support)
                    if newType == .swimming { draft.isIntervalWorkout = false }
                }
            }

            // Distance — only for run/bike
            if draft.type != .swimming {
                Section("Target Distance (optional)") {
                    HStack {
                        TextField("0.0", text: $draft.targetDistance)
                            .keyboardType(.decimalPad)
                        Text(distanceUnit.abbreviation)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Duration — always shown, HH:MM:SS
            Section {
                HStack(spacing: Spacing.sm) {
                    durationField(value: $draft.targetHours,   label: "HRS", max: 23)
                    Text(":").font(.sfHeadline).foregroundStyle(.secondary)
                    durationField(value: $draft.targetMinutes, label: "MIN", max: 59)
                    Text(":").font(.sfHeadline).foregroundStyle(.secondary)
                    durationField(value: $draft.targetSeconds, label: "SEC", max: 59)
                }
                .padding(.vertical, Spacing.xs)
            } header: {
                Text("Target Duration (optional)")
            }

            // Interval toggle + editor (run/bike only)
            if draft.type != .swimming {
                Section {
                    Toggle("Interval / Fartlek Workout", isOn: $draft.isIntervalWorkout)
                        .tint(Color.sfAccent)
                        .onChange(of: draft.isIntervalWorkout) { _, on in
                            if on && draft.intervals.isEmpty {
                                draft.intervals.append(DraftInterval())
                            }
                        }
                }

                if draft.isIntervalWorkout {
                    Section {
                        ForEach($draft.intervals) { $interval in
                            IntervalRowView(interval: $interval, distanceUnit: distanceUnit)
                        }
                        .onDelete { draft.intervals.remove(atOffsets: $0) }

                        Button {
                            draft.intervals.append(DraftInterval())
                        } label: {
                            Label("Add Interval", systemImage: "plus.circle.fill")
                                .foregroundStyle(Color.sfAccent)
                        }

                        Button {
                            var rest = DraftInterval()
                            rest.label = "Rest"
                            rest.isRest = true
                            draft.intervals.append(rest)
                        } label: {
                            Label("Add Rest", systemImage: "moon.fill")
                                .foregroundStyle(Color.sfAccent.opacity(0.7))
                        }
                    } header: {
                        Text("Intervals")
                    } footer: {
                        Text("Swipe to delete. Drag to reorder is not yet supported.")
                    }
                }
            }

            Section("Notes") {
                TextField("e.g. Easy pace, fartlek, tempo run...", text: $draft.notes, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                Button {
                    onAssign(draft)
                    dismiss()
                } label: {
                    Text("Assign to Day")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .padding(.horizontal, Spacing.md)
            }
        }
        .navigationTitle(draft.type.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func durationField(value: Binding<String>, label: String, max: Int) -> some View {
        VStack(spacing: 4) {
            TextField("0", text: value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.sfHeadline)
                .frame(maxWidth: .infinity)
                .padding(Spacing.xs)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .onChange(of: value.wrappedValue) { _, new in
                    if let n = Int(new), n > max { value.wrappedValue = "\(max)" }
                }
            Text(label)
                .font(.sfCaption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Interval Row View

struct IntervalRowView: View {
    @Binding var interval: DraftInterval
    let distanceUnit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Label row + rest toggle
            HStack {
                Image(systemName: interval.isRest ? "moon.fill" : "bolt.fill")
                    .font(.sfCaption)
                    .foregroundStyle(interval.isRest ? Color.sfAccent.opacity(0.5) : Color.sfAccent)

                TextField(interval.isRest ? "Rest" : "Label (e.g. Fast interval)", text: $interval.label)
                    .font(.sfSubhead)

                Toggle("", isOn: $interval.isRest)
                    .labelsHidden()
                    .tint(Color.sfAccent.opacity(0.5))
                    .scaleEffect(0.8)
            }

            if !interval.isRest {
                HStack(spacing: Spacing.sm) {
                    // Distance
                    HStack(spacing: 4) {
                        TextField("dist", text: $interval.distanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 56)
                            .padding(Spacing.xxs)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(distanceUnit.abbreviation)
                            .font(.sfCaption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Pace MM:SS
                    HStack(spacing: 2) {
                        TextField("0", text: $interval.paceMinutes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 36)
                            .padding(Spacing.xxs)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(":").foregroundStyle(.secondary).font(.sfCaption)
                        TextField("00", text: $interval.paceSeconds)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 36)
                            .padding(Spacing.xxs)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onChange(of: interval.paceSeconds) { _, new in
                                if let n = Int(new), n > 59 { interval.paceSeconds = "59" }
                            }
                        Text("pace")
                            .font(.sfCaption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.sfCaption)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}
