import SwiftUI
import SwiftData

/// Form for creating or editing a named, standalone cardio template
/// (saved to the user's library, distinct from program-day configs).
struct CreateCardioTemplateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.miles.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .miles }

    /// Non-nil when editing an existing template
    var editing: CardioTemplate? = nil

    // MARK: - Form state

    @State private var name: String = ""
    @State private var cardioType: CardioType = .running
    @State private var targetHours: String = ""
    @State private var targetMinutes: String = ""
    @State private var targetSeconds: String = ""
    @State private var targetDistance: String = ""
    @State private var isIntervalWorkout: Bool = false
    @State private var intervals: [DraftInterval] = []
    @State private var notes: String = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var targetDurationSeconds: Int {
        ((Int(targetHours) ?? 0) * 3600)
        + ((Int(targetMinutes) ?? 0) * 60)
        + (Int(targetSeconds) ?? 0)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Name
                Section {
                    TextField("e.g. Morning 5K, Easy Bike Hour", text: $name)
                        .autocorrectionDisabled()
                } header: {
                    Text("Template Name")
                }

                // Activity type
                Section {
                    Picker("Activity", selection: $cardioType) {
                        ForEach(CardioType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.sm,
                                             bottom: Spacing.sm, trailing: Spacing.sm))
                    .onChange(of: cardioType) { _, newType in
                        if newType == .swimming { isIntervalWorkout = false }
                    }
                } header: {
                    Text("Activity")
                }

                // Distance — run/bike only
                if cardioType != .swimming {
                    Section {
                        HStack {
                            TextField("0.0", text: $targetDistance)
                                .keyboardType(.decimalPad)
                            Text(distanceUnit.abbreviation)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Target Distance (optional)")
                    }
                }

                // Duration HH:MM:SS
                Section {
                    HStack(spacing: Spacing.sm) {
                        durationField(value: $targetHours,   label: "HRS", max: 23)
                        Text(":").font(.sfHeadline).foregroundStyle(.secondary)
                        durationField(value: $targetMinutes, label: "MIN", max: 59)
                        Text(":").font(.sfHeadline).foregroundStyle(.secondary)
                        durationField(value: $targetSeconds, label: "SEC", max: 59)
                    }
                    .padding(.vertical, Spacing.xs)
                } header: {
                    Text("Target Duration (optional)")
                }

                // Interval toggle + editor — run/bike only
                if cardioType != .swimming {
                    Section {
                        Toggle("Interval / Fartlek Workout", isOn: $isIntervalWorkout)
                            .tint(Color.sfAccent)
                            .onChange(of: isIntervalWorkout) { _, on in
                                if on && intervals.isEmpty { intervals.append(DraftInterval()) }
                            }
                    }

                    if isIntervalWorkout {
                        Section {
                            ForEach($intervals) { $interval in
                                IntervalRowView(interval: $interval, distanceUnit: distanceUnit)
                            }
                            .onDelete { intervals.remove(atOffsets: $0) }

                            Button {
                                intervals.append(DraftInterval())
                            } label: {
                                Label("Add Interval", systemImage: "plus.circle.fill")
                                    .foregroundStyle(Color.sfAccent)
                            }

                            Button {
                                var rest = DraftInterval()
                                rest.label = "Rest"
                                rest.isRest = true
                                intervals.append(rest)
                            } label: {
                                Label("Add Rest", systemImage: "moon.fill")
                                    .foregroundStyle(Color.sfAccent.opacity(0.7))
                            }
                        } header: {
                            Text("Intervals")
                        } footer: {
                            Text("Set distance and target pace for each interval.")
                        }
                    }
                }

                // Notes
                Section {
                    TextField("e.g. Keep it aerobic, race-pace effort...", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Notes")
                }
            }
            .navigationTitle(editing == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(isValid ? Color.sfAccent : .secondary)
                        .disabled(!isValid)
                }
            }
            .onAppear { populateIfEditing() }
        }
    }

    // MARK: - Populate from existing template

    private func populateIfEditing() {
        guard let t = editing else { return }
        name            = t.name
        cardioType      = t.cardioType
        isIntervalWorkout = t.isIntervalWorkout
        notes           = t.notes

        if let dist = t.targetDistance, dist > 0 {
            targetDistance = String(format: "%.2f", dist)
        }
        if t.targetDurationSeconds > 0 {
            let total = t.targetDurationSeconds
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            targetHours   = h > 0 ? "\(h)" : ""
            targetMinutes = m > 0 ? "\(m)" : ""
            targetSeconds = s > 0 ? "\(s)" : ""
        }
        intervals = t.sortedIntervals.map { iv in
            var di = DraftInterval()
            di.label  = iv.label
            di.isRest = iv.isRest
            if let d = iv.distanceValue, d > 0 {
                di.distanceText = String(format: "%.2f", d)
            }
            if let p = iv.paceSecondsPerUnit, p > 0 {
                di.paceMinutes = "\(p / 60)"
                di.paceSeconds = p % 60 > 0 ? "\(p % 60)" : ""
            }
            return di
        }
    }

    // MARK: - Save

    private func save() {
        let template: CardioTemplate
        if let existing = editing {
            // Remove old intervals before rebuilding
            existing.intervals.forEach { modelContext.delete($0) }
            existing.intervals = []
            template = existing
        } else {
            template = CardioTemplate(cardioType: cardioType, name: "", isTemplate: true)
            modelContext.insert(template)
        }

        template.name                 = name.trimmingCharacters(in: .whitespaces)
        template.cardioType           = cardioType
        template.targetDurationSeconds = targetDurationSeconds
        template.targetDistance       = Double(targetDistance)
        template.distanceUnit         = distanceUnit
        template.isIntervalWorkout    = isIntervalWorkout && cardioType != .swimming
        template.notes                = notes
        template.isTemplate           = true

        if isIntervalWorkout && cardioType != .swimming {
            let persistedIntervals = intervals.enumerated().map { index, di in
                let iv = CardioTemplateInterval(order: index)
                iv.label               = di.label
                iv.isRest              = di.isRest
                iv.distanceValue       = Double(di.distanceText)
                iv.paceSecondsPerUnit  = di.paceSecondsPerUnit
                modelContext.insert(iv)
                return iv
            }
            template.intervals = persistedIntervals
        }

        try? modelContext.save()
        dismiss()
    }

    // MARK: - Duration field helper

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

#Preview {
    CreateCardioTemplateView()
        .modelContainer(for: [CardioTemplate.self, CardioTemplateInterval.self], inMemory: true)
}
