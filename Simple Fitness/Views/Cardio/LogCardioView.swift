import SwiftUI
import SwiftData

// MARK: - Local editing structs (not persisted until Save)

private struct SplitEntry: Identifiable {
    let id = UUID()
    var label: String = ""
    var minutes: String = ""
    var seconds: String = ""
    var distanceText: String = ""
    var isRest: Bool = false
}

private struct SwimSetEntry: Identifiable {
    let id = UUID()
    var stroke: SwimStroke = .freestyle
    var lapsText: String = ""
    var metersText: String = ""
    var minutes: String = ""
    var seconds: String = ""
}

// MARK: - Log Cardio View

struct LogCardioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Optional: pre-select a cardio type when launched from a program day
    var prefillType: CardioType? = nil

    // Distance unit preference — syncs with SettingsView
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.miles.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .miles }

    // Form state
    @State private var cardioType: CardioType = .running
    @State private var date: Date = Date()
    @State private var durationHours: String = ""
    @State private var durationMinutes: String = ""
    @State private var durationSeconds: String = ""
    @State private var distanceText: String = ""
    @State private var isIntervalWorkout: Bool = false
    @State private var splits: [SplitEntry] = []
    @State private var swimSets: [SwimSetEntry] = []
    @State private var notes: String = ""

    @State private var showValidationAlert = false
    @State private var showingTemplatePicker = false

    // MARK: - Computed

    private var totalDurationSeconds: Int {
        let h = Int(durationHours) ?? 0
        let m = Int(durationMinutes) ?? 0
        let s = Int(durationSeconds) ?? 0
        return h * 3600 + m * 60 + s
    }

    private var distanceValue: Double? {
        guard let d = Double(distanceText), d > 0 else { return nil }
        return d
    }

    private var calculatedPace: String? {
        guard let dist = distanceValue, dist > 0, totalDurationSeconds > 0 else { return nil }
        let paceSeconds = Double(totalDurationSeconds) / dist
        let m = Int(paceSeconds) / 60
        let s = Int(paceSeconds) % 60
        return String(format: "%d:%02d /%@", m, s, distanceUnit.abbreviation)
    }

    private var isRunOrBike: Bool { cardioType == .running || cardioType == .biking }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                typeAndDateSection
                durationSection
                if isRunOrBike {
                    distanceSection
                    intervalSection
                }
                if cardioType == .swimming {
                    swimSetsSection
                }
                notesSection
            }
            .navigationTitle("Log \(cardioType.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sfAccent)
                }
                ToolbarItem(placement: .principal) {
                    Button {
                        showingTemplatePicker = true
                    } label: {
                        Label("Use Template", systemImage: "square.and.arrow.down")
                            .font(.sfCaption)
                            .foregroundStyle(Color.sfAccent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveLog() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.sfAccent)
                }
            }
            .alert("Missing Info", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please enter at least a duration or a distance.")
            }
            .sheet(isPresented: $showingTemplatePicker) {
                TemplatePickerSheet { template in
                    applyTemplate(template)
                }
            }
            .onAppear {
                if let pre = prefillType { cardioType = pre }
            }
        }
    }

    // MARK: - Sections

    private var typeAndDateSection: some View {
        Section {
            Picker("Type", selection: $cardioType) {
                ForEach(CardioType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.sm, bottom: Spacing.sm, trailing: Spacing.sm))

            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
        } header: {
            Text("Session")
        }
    }

    private var durationSection: some View {
        Section {
            HStack(spacing: Spacing.md) {
                durationField(value: $durationHours, label: "HRS", max: 23)
                Text(":").font(.sfHeadline).foregroundStyle(.secondary)
                durationField(value: $durationMinutes, label: "MIN", max: 59)
                Text(":").font(.sfHeadline).foregroundStyle(.secondary)
                durationField(value: $durationSeconds, label: "SEC", max: 59)
            }
            .padding(.vertical, Spacing.xs)
        } header: {
            Text("Duration")
        }
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

    private var distanceSection: some View {
        Section {
            HStack {
                TextField("0.00", text: $distanceText)
                    .keyboardType(.decimalPad)
                    .font(.sfBody)
                Text(distanceUnit.abbreviation)
                    .foregroundStyle(.secondary)
                    .font(.sfBody)
            }

            if let pace = calculatedPace {
                HStack {
                    Text("Pace")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(pace)
                        .font(.sfCaption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.sfAccent)
                }
            }
        } header: {
            Text("Distance")
        }
    }

    private var intervalSection: some View {
        Section {
            Toggle("Interval / Fartlek Workout", isOn: $isIntervalWorkout)
                .tint(Color.sfAccent)

            if isIntervalWorkout {
                ForEach($splits) { $split in
                    SplitRowView(split: $split, distanceUnit: distanceUnit)
                }
                .onDelete { splits.remove(atOffsets: $0) }

                Button(action: { splits.append(SplitEntry()) }) {
                    Label("Add Interval", systemImage: "plus.circle.fill")
                        .foregroundStyle(Color.sfAccent)
                }

                Button(action: {
                    var rest = SplitEntry()
                    rest.label = "Rest"
                    rest.isRest = true
                    splits.append(rest)
                }) {
                    Label("Add Rest", systemImage: "moon.fill")
                        .foregroundStyle(Color.sfAccent.opacity(0.7))
                }
            }
        } header: {
            Text("Intervals")
        }
    }

    private var swimSetsSection: some View {
        Section {
            ForEach($swimSets) { $set in
                SwimSetRowView(entry: $set)
            }
            .onDelete { swimSets.remove(atOffsets: $0) }

            Button(action: { swimSets.append(SwimSetEntry()) }) {
                Label("Add Set", systemImage: "plus.circle.fill")
                    .foregroundStyle(Color.sfAccent)
            }
        } header: {
            Text("Swim Sets")
        } footer: {
            Text("Enter laps or meters — whichever you prefer.")
        }
    }

    private var notesSection: some View {
        Section {
            TextField("How did it feel? Any comments...", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .font(.sfBody)
        } header: {
            Text("Notes")
        }
    }

    // MARK: - Apply Template

    private func applyTemplate(_ template: CardioTemplate) {
        cardioType = template.cardioType

        // Duration
        if template.targetDurationSeconds > 0 {
            let total = template.targetDurationSeconds
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            durationHours   = h > 0 ? "\(h)" : ""
            durationMinutes = m > 0 ? "\(m)" : ""
            durationSeconds = s > 0 ? "\(s)" : ""
        }

        // Distance
        if let dist = template.targetDistance, dist > 0 {
            distanceText = String(format: "%.2f", dist)
        }

        // Notes (only if form notes is empty)
        if notes.isEmpty && !template.notes.isEmpty {
            notes = template.notes
        }

        // Intervals — convert pace + distance into expected split duration
        if template.isIntervalWorkout && !template.sortedIntervals.isEmpty {
            isIntervalWorkout = true
            splits = template.sortedIntervals.map { iv in
                var entry = SplitEntry()
                entry.label   = iv.label
                entry.isRest  = iv.isRest
                if let d = iv.distanceValue, d > 0 {
                    entry.distanceText = String(format: "%.2f", d)
                    // Pre-fill expected duration if pace is known
                    if let pace = iv.paceSecondsPerUnit, pace > 0 {
                        let expectedSec = Int(d * Double(pace))
                        entry.minutes = "\(expectedSec / 60)"
                        entry.seconds = expectedSec % 60 > 0 ? "\(expectedSec % 60)" : ""
                    }
                }
                return entry
            }
        }
    }

    // MARK: - Save

    private func saveLog() {
        guard totalDurationSeconds > 0 || distanceValue != nil else {
            showValidationAlert = true
            return
        }

        let log = CardioLog(cardioType: cardioType, date: date)
        log.durationSeconds = totalDurationSeconds
        log.distanceValue = distanceValue
        log.distanceUnit = distanceUnit
        log.isIntervalWorkout = isIntervalWorkout && isRunOrBike
        log.notes = notes

        // Splits
        if isIntervalWorkout && isRunOrBike {
            let cardioSplits = splits.enumerated().map { index, entry in
                let s = CardioSplit(order: index, label: entry.label, isRest: entry.isRest)
                let m = Int(entry.minutes) ?? 0
                let sec = Int(entry.seconds) ?? 0
                let totalSec = m * 60 + sec
                s.durationSeconds = totalSec > 0 ? totalSec : nil
                s.distanceValue = Double(entry.distanceText)
                return s
            }
            cardioSplits.forEach { modelContext.insert($0) }
            log.splits = cardioSplits
        }

        // Swim sets
        if cardioType == .swimming {
            let sets = swimSets.enumerated().map { index, entry in
                let s = SwimSet(order: index, stroke: entry.stroke)
                s.laps = Int(entry.lapsText)
                s.meters = Int(entry.metersText)
                let m = Int(entry.minutes) ?? 0
                let sec = Int(entry.seconds) ?? 0
                let totalSec = m * 60 + sec
                s.durationSeconds = totalSec > 0 ? totalSec : nil
                return s
            }
            sets.forEach { modelContext.insert($0) }
            log.swimSets = sets
        }

        modelContext.insert(log)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Split Row

private struct SplitRowView: View {
    @Binding var split: SplitEntry
    let distanceUnit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Image(systemName: split.isRest ? "moon.fill" : "bolt.fill")
                    .font(.sfCaption)
                    .foregroundStyle(split.isRest ? Color.sfAccent.opacity(0.5) : Color.sfAccent)

                TextField(split.isRest ? "Rest" : "Label (e.g. Interval 1)", text: $split.label)
                    .font(.sfSubhead)

                Toggle("", isOn: $split.isRest)
                    .labelsHidden()
                    .tint(Color.sfAccent.opacity(0.5))
                    .scaleEffect(0.8)
            }

            HStack(spacing: Spacing.sm) {
                // Duration MM:SS
                HStack(spacing: 4) {
                    TextField("0", text: $split.minutes)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 36)
                        .padding(Spacing.xxs)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(":").foregroundStyle(.secondary)
                    TextField("00", text: $split.seconds)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 36)
                        .padding(Spacing.xxs)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onChange(of: split.seconds) { _, new in
                            if let n = Int(new), n > 59 { split.seconds = "59" }
                        }
                    Text("min").font(.sfCaption2).foregroundStyle(.secondary)
                }

                Spacer()

                // Distance (optional)
                HStack(spacing: 4) {
                    TextField("dist", text: $split.distanceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 52)
                        .padding(Spacing.xxs)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(distanceUnit.abbreviation)
                        .font(.sfCaption2)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.sfCaption)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Swim Set Row

private struct SwimSetRowView: View {
    @Binding var entry: SwimSetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Stroke picker
            Picker("Stroke", selection: $entry.stroke) {
                ForEach(SwimStroke.allCases, id: \.self) { stroke in
                    Text(stroke.displayName).tag(stroke)
                }
            }
            .font(.sfSubhead)

            HStack(spacing: Spacing.md) {
                // Laps
                VStack(alignment: .leading, spacing: 2) {
                    TextField("0", text: $entry.lapsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .padding(Spacing.xxs)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Laps").font(.sfCaption2).foregroundStyle(.secondary)
                }

                // Meters
                VStack(alignment: .leading, spacing: 2) {
                    TextField("0", text: $entry.metersText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .padding(Spacing.xxs)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Meters").font(.sfCaption2).foregroundStyle(.secondary)
                }

                // Duration MM:SS
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        TextField("0", text: $entry.minutes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 32)
                            .padding(Spacing.xxs)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(":").foregroundStyle(.secondary).font(.sfCaption)
                        TextField("00", text: $entry.seconds)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 32)
                            .padding(Spacing.xxs)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onChange(of: entry.seconds) { _, new in
                                if let n = Int(new), n > 59 { entry.seconds = "59" }
                            }
                    }
                    Text("Duration").font(.sfCaption2).foregroundStyle(.secondary)
                }
            }
            .font(.sfCaption)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Template Picker Sheet

struct TemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CardioTemplate.name) private var allTemplates: [CardioTemplate]

    let onSelect: (CardioTemplate) -> Void

    private var templates: [CardioTemplate] {
        allTemplates.filter { $0.isTemplate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    VStack(spacing: Spacing.lg) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.sfAccent.opacity(0.6))
                        VStack(spacing: Spacing.xs) {
                            Text("No templates yet")
                                .font(.sfHeadline)
                            Text("Create a template in the Cardio tab to reuse it here.")
                                .font(.sfCallout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(Spacing.xl)
                } else {
                    List(templates) { template in
                        Button {
                            onSelect(template)
                            dismiss()
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: template.cardioType.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.sfAccent)
                                    .frame(width: 30, height: 30)
                                    .background(Color.sfAccent.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name.isEmpty ? template.displayName : template.name)
                                        .font(.sfSubhead)
                                        .foregroundStyle(.primary)
                                    Text(template.displayName)
                                        .font(.sfCaption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.down.circle")
                                    .foregroundStyle(Color.sfAccent)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Use Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LogCardioView()
        .modelContainer(for: [CardioLog.self, CardioSplit.self, SwimSet.self,
                               CardioTemplate.self, CardioTemplateInterval.self], inMemory: true)
}
