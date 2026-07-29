import SwiftUI
import SwiftData

/// Form for creating or editing a named, standalone cardio template
/// (saved to the user's library, distinct from program-day configs).
/// Supports structured workout types (intervals, fartlek, hills, tempo, progression)
/// with per-segment duration, intensity, pace and incline.
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
    @State private var structureType: CardioWorkoutType = .steady
    @State private var targetHours: String = ""
    @State private var targetMinutes: String = ""
    @State private var targetSeconds: String = ""
    @State private var targetDistance: String = ""
    @State private var segments: [DraftInterval] = []
    @State private var notes: String = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isSegmented: Bool { structureType.isSegmented && cardioType != .swimming }

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
                    TextField("e.g. Tuesday Hills, Morning 5K", text: $name)
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
                        if newType == .swimming { structureType = .steady }
                    }
                } header: {
                    Text("Activity")
                }

                // Workout type — run/bike only
                if cardioType != .swimming {
                    Section {
                        Picker("Type", selection: $structureType) {
                            ForEach(CardioWorkoutType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .onChange(of: structureType) { _, newType in
                            if newType.isSegmented && segments.isEmpty {
                                segments = Self.scaffold(for: newType)
                            }
                        }
                        Text(structureType.blurb)
                            .font(.sfCaption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Workout Type")
                    }
                }

                // Distance/duration targets — steady workouts only
                if !isSegmented {
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
                }

                // Structured segments
                if isSegmented {
                    Section {
                        ForEach($segments) { $segment in
                            SegmentRowView(
                                segment: $segment,
                                distanceUnit: distanceUnit,
                                showIncline: structureType == .hills
                            )
                        }
                        .onDelete { segments.remove(atOffsets: $0) }
                        .onMove { segments.move(fromOffsets: $0, toOffset: $1) }

                        Button {
                            segments.append(DraftInterval())
                        } label: {
                            Label("Add Segment", systemImage: "plus.circle.fill")
                                .foregroundStyle(Color.sfAccent)
                        }

                        Button {
                            var rest = DraftInterval()
                            rest.label = "Recovery"
                            rest.isRest = true
                            rest.intensity = .rest
                            segments.append(rest)
                        } label: {
                            Label("Add Recovery", systemImage: "moon.fill")
                                .foregroundStyle(Color.sfAccent.opacity(0.7))
                        }

                        Button {
                            segments = Self.scaffold(for: structureType)
                        } label: {
                            Label("Reset to \(structureType.displayName) template", systemImage: "arrow.counterclockwise")
                                .font(.sfCaption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Segments")
                    } footer: {
                        Text("Set a duration (or distance) and intensity for each segment. Mark recovery segments as rest.")
                    }
                }

                // Notes
                Section {
                    TextField("e.g. Keep hills at 5K effort...", text: $notes, axis: .vertical)
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
                if isSegmented {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
            }
            .onAppear { populateIfEditing() }
        }
    }

    // MARK: - Default segment scaffolding

    private static func scaffold(for type: CardioWorkoutType) -> [DraftInterval] {
        func seg(_ label: String, _ intensity: CardioIntensity, isRest: Bool = false,
                 durMin: String = "", incline: String = "") -> DraftInterval {
            var d = DraftInterval()
            d.label = label
            d.intensity = intensity
            d.isRest = isRest
            d.durationMinutes = durMin
            d.inclineText = incline
            return d
        }
        switch type {
        case .steady:
            return []
        case .intervals:
            return [
                seg("Warmup", .easy, durMin: "10"),
                seg("Interval", .hard, durMin: "1"),
                seg("Recovery", .rest, isRest: true, durMin: "2"),
                seg("Interval", .hard, durMin: "1"),
                seg("Recovery", .rest, isRest: true, durMin: "2"),
                seg("Cooldown", .easy, durMin: "10"),
            ]
        case .fartlek:
            return [
                seg("Warmup", .easy, durMin: "10"),
                seg("Surge", .hard, durMin: "1"),
                seg("Float", .moderate, durMin: "2"),
                seg("Surge", .hard, durMin: "1"),
                seg("Float", .moderate, durMin: "2"),
                seg("Cooldown", .easy, durMin: "10"),
            ]
        case .hills:
            return [
                seg("Warmup", .easy, durMin: "10"),
                seg("Hill", .hard, durMin: "1", incline: "6"),
                seg("Recovery", .rest, isRest: true, durMin: "2"),
                seg("Hill", .hard, durMin: "1", incline: "6"),
                seg("Recovery", .rest, isRest: true, durMin: "2"),
                seg("Cooldown", .easy, durMin: "10"),
            ]
        case .tempo:
            return [
                seg("Warmup", .easy, durMin: "10"),
                seg("Tempo", .hard, durMin: "20"),
                seg("Cooldown", .easy, durMin: "10"),
            ]
        case .progression:
            return [
                seg("Easy", .easy, durMin: "10"),
                seg("Moderate", .moderate, durMin: "10"),
                seg("Hard", .hard, durMin: "10"),
            ]
        }
    }

    // MARK: - Populate from existing template

    private func populateIfEditing() {
        guard let t = editing else { return }
        name          = t.name
        cardioType    = t.cardioType
        structureType = t.structureType
        notes         = t.notes

        if let dist = t.targetDistance, dist > 0 {
            targetDistance = String(format: "%.2f", dist)
        }
        if t.targetDurationSeconds > 0 {
            let total = t.targetDurationSeconds
            targetHours   = total / 3600 > 0 ? "\(total / 3600)" : ""
            targetMinutes = (total % 3600) / 60 > 0 ? "\((total % 3600) / 60)" : ""
            targetSeconds = total % 60 > 0 ? "\(total % 60)" : ""
        }
        segments = t.sortedIntervals.map { iv in
            var di = DraftInterval()
            di.label     = iv.label
            di.isRest    = iv.isRest
            di.intensity = iv.intensity
            if let d = iv.distanceValue, d > 0 { di.distanceText = String(format: "%.2f", d) }
            if let p = iv.paceSecondsPerUnit, p > 0 {
                di.paceMinutes = "\(p / 60)"
                di.paceSeconds = p % 60 > 0 ? "\(p % 60)" : ""
            }
            if let dur = iv.durationSeconds, dur > 0 {
                di.durationMinutes = "\(dur / 60)"
                di.durationSecondsText = dur % 60 > 0 ? "\(dur % 60)" : ""
            }
            if let incline = iv.inclinePercent, incline > 0 {
                di.inclineText = incline.weightFormatted
            }
            return di
        }
    }

    // MARK: - Save

    private func save() {
        let template: CardioTemplate
        if let existing = editing {
            existing.intervals.forEach { modelContext.delete($0) }
            existing.intervals = []
            template = existing
        } else {
            template = CardioTemplate(cardioType: cardioType, name: "", isTemplate: true)
            modelContext.insert(template)
        }

        template.name                  = name.trimmingCharacters(in: .whitespaces)
        template.cardioType            = cardioType
        template.structureType         = cardioType == .swimming ? .steady : structureType
        template.targetDurationSeconds = targetDurationSeconds
        template.targetDistance        = Double(targetDistance)
        template.distanceUnit          = distanceUnit
        template.isIntervalWorkout     = isSegmented
        template.notes                 = notes
        template.isTemplate            = true

        if isSegmented {
            let persisted = segments.enumerated().map { index, di -> CardioTemplateInterval in
                let iv = CardioTemplateInterval(order: index)
                iv.label              = di.label
                iv.isRest             = di.isRest
                iv.intensity          = di.intensity
                iv.distanceValue      = Double(di.distanceText)
                iv.durationSeconds    = di.durationTotalSeconds
                iv.paceSecondsPerUnit = di.paceSecondsPerUnit
                iv.inclinePercent     = di.inclineValue
                modelContext.insert(iv)
                return iv
            }
            template.intervals = persisted
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

// MARK: - Segment Row

/// Editor for one structured cardio segment: label, intensity, duration, distance, pace, incline.
private struct SegmentRowView: View {
    @Binding var segment: DraftInterval
    let distanceUnit: DistanceUnit
    let showIncline: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Label + rest toggle
            HStack {
                Image(systemName: segment.isRest ? "moon.fill" : "bolt.fill")
                    .font(.sfCaption)
                    .foregroundStyle(segment.isRest ? Color.sfAccent.opacity(0.5) : Color.sfAccent)
                TextField(segment.isRest ? "Recovery" : "Label (e.g. Hill)", text: $segment.label)
                    .font(.sfSubhead)
                Toggle("Rest", isOn: $segment.isRest)
                    .labelsHidden()
                    .tint(Color.sfAccent.opacity(0.5))
                    .scaleEffect(0.8)
                    .onChange(of: segment.isRest) { _, isRest in
                        if isRest { segment.intensity = .rest }
                        else if segment.intensity == .rest { segment.intensity = .moderate }
                    }
            }

            // Intensity
            if !segment.isRest {
                Picker("Intensity", selection: $segment.intensity) {
                    ForEach([CardioIntensity.easy, .moderate, .hard, .max], id: \.self) { i in
                        Text(i.displayName).tag(i)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Duration + distance
            HStack(spacing: Spacing.sm) {
                // Duration MM:SS
                HStack(spacing: 2) {
                    TextField("0", text: $segment.durationMinutes)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 34)
                        .padding(Spacing.xxs)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(":").foregroundStyle(.secondary).font(.sfCaption)
                    TextField("00", text: $segment.durationSecondsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 34)
                        .padding(Spacing.xxs)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onChange(of: segment.durationSecondsText) { _, new in
                            if let n = Int(new), n > 59 { segment.durationSecondsText = "59" }
                        }
                    Text("min").font(.sfCaption2).foregroundStyle(.secondary)
                }

                Spacer()

                // Distance (optional)
                HStack(spacing: 4) {
                    TextField("dist", text: $segment.distanceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 50)
                        .padding(Spacing.xxs)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(distanceUnit.abbreviation).font(.sfCaption2).foregroundStyle(.secondary)
                }
            }
            .font(.sfCaption)

            // Pace + incline
            if !segment.isRest {
                HStack(spacing: Spacing.sm) {
                    // Pace MM:SS
                    HStack(spacing: 2) {
                        TextField("0", text: $segment.paceMinutes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 34)
                            .padding(Spacing.xxs)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(":").foregroundStyle(.secondary).font(.sfCaption)
                        TextField("00", text: $segment.paceSeconds)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 34)
                            .padding(Spacing.xxs)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onChange(of: segment.paceSeconds) { _, new in
                                if let n = Int(new), n > 59 { segment.paceSeconds = "59" }
                            }
                        Text("pace").font(.sfCaption2).foregroundStyle(.secondary)
                    }

                    if showIncline {
                        Spacer()
                        HStack(spacing: 4) {
                            TextField("0", text: $segment.inclineText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 42)
                                .padding(Spacing.xxs)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text("% incline").font(.sfCaption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.sfCaption)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}

#Preview {
    CreateCardioTemplateView()
        .modelContainer(for: [CardioTemplate.self, CardioTemplateInterval.self], inMemory: true)
}
