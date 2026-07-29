import SwiftUI
import SwiftData

/// Full-screen guided runner for a structured cardio template.
/// Steps through the template's segments with a timer, then saves a CardioLog.
struct ActiveCardioView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var vm: ActiveCardioViewModel
    @State private var showingQuitConfirm = false
    @State private var showingSaveError = false

    init(template: CardioTemplate) {
        _vm = State(wrappedValue: ActiveCardioViewModel(template: template))
    }

    private var title: String {
        vm.template.name.isEmpty ? vm.template.displayName : vm.template.name
    }

    // MARK: - Body

    var body: some View {
        Group {
            if vm.isComplete {
                completionView
            } else {
                activeContent
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.isComplete)
        .onAppear { vm.start() }
        .confirmationDialog("End Session?", isPresented: $showingQuitConfirm, titleVisibility: .visible) {
            Button("End Session", role: .destructive) { dismiss() }
            Button("Keep Going", role: .cancel) { }
        } message: {
            Text("Your session won't be saved if you quit now.")
        }
        .alert("Couldn't Save Session", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text("Your cardio session couldn't be saved due to a storage error.")
        }
    }

    // MARK: - Active Content

    private var activeContent: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            progressBar

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    Text("Segment \(vm.currentIndex + 1) of \(vm.totalSegments)")
                        .font(.sfSubhead)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    currentSegmentCard

                    if let next = vm.upNextSegment {
                        upNextCard(next)
                    }

                    actionButton
                        .padding(.top, Spacing.xs)
                }
                .padding(Spacing.md)
            }
        }
        .background(Color(.systemBackground))
    }

    private var topBar: some View {
        HStack {
            Button {
                showingQuitConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.sfSurface)
                    .clipShape(Circle())
            }
            Spacer()
            VStack(spacing: 2) {
                Text(title).font(.sfHeadline).lineLimit(1)
                Text(vm.elapsedSeconds.timerFormatted)
                    .font(.sfCaption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.sfSurface).frame(height: 3)
                Rectangle().fill(Color.sfAccent)
                    .frame(width: geo.size.width * vm.progress, height: 3)
                    .animation(.spring(response: 0.4), value: vm.progress)
            }
        }
        .frame(height: 3)
    }

    private var currentSegmentCard: some View {
        VStack(spacing: Spacing.md) {
            if let seg = vm.currentSegment {
                HStack {
                    Text(seg.label.isEmpty ? (seg.isRest ? "Recovery" : "Segment") : seg.label)
                        .font(.sfTitle)
                    Spacer()
                    intensityBadge(seg.isRest ? .rest : seg.intensity)
                }

                // Big timer ring
                ZStack {
                    Circle()
                        .stroke(Color.sfSurface, lineWidth: 8)
                    if let remaining = vm.segmentRemaining, let dur = vm.currentSegmentDuration, dur > 0 {
                        Circle()
                            .trim(from: 0, to: 1 - (Double(remaining) / Double(dur)))
                            .stroke(seg.isRest ? Color.sfAccent.opacity(0.5) : Color.sfAccent,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: remaining)
                    }
                    VStack(spacing: 4) {
                        Text((vm.segmentRemaining ?? vm.segmentElapsed).timerFormatted)
                            .font(.sfTimer)
                            .monospacedDigit()
                        Text(vm.segmentRemaining != nil ? "remaining" : "elapsed")
                            .font(.sfCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 200, height: 200)
                .padding(.vertical, Spacing.sm)

                // Target details
                if !targetDetails(seg).isEmpty {
                    Text(targetDetails(seg))
                        .font(.sfSubhead)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.sfSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func upNextCard(_ seg: CardioTemplateInterval) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "arrow.turn.down.right")
                .font(.sfCaption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Up Next")
                    .font(.sfCaption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(seg.displaySummary)
                    .font(.sfCallout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.sfSurface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var actionButton: some View {
        Button(vm.isLastSegment ? "Finish Session" : "Next Segment →") {
            vm.advance()
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    // MARK: - Completion

    private var completionView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.sfAccent)
            Text("Session Complete")
                .font(.sfTitle)
            Text(title)
                .font(.sfCallout)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                summaryItem(icon: "clock", value: vm.elapsedSeconds.timerFormatted, label: "Time")
                Divider().frame(height: 36)
                summaryItem(icon: "list.number", value: "\(vm.totalSegments)", label: "Segments")
            }
            .padding(Spacing.md)
            .background(Color.sfSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .padding(.horizontal, Spacing.xl)

            Spacer()

            Button("Save Session") { saveAndDismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Spacing.lg)
            Button("Discard") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func summaryItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.sfCaption).foregroundStyle(Color.sfAccent)
            Text(value).font(.sfHeadline).monospacedDigit()
            Text(label).font(.sfCaption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func targetDetails(_ seg: CardioTemplateInterval) -> String {
        var parts: [String] = []
        if let d = seg.distanceValue, d > 0 {
            parts.append(String(format: "%.2f %@", d, vm.template.distanceUnit.abbreviation))
        }
        if let pace = seg.paceFormatted {
            parts.append("target \(pace) /\(vm.template.distanceUnit.abbreviation)")
        }
        if let incline = seg.inclinePercent, incline > 0 {
            parts.append(String(format: "%.0f%% incline", incline))
        }
        return parts.joined(separator: "  ·  ")
    }

    private func intensityBadge(_ intensity: CardioIntensity) -> some View {
        Text(intensity.displayName)
            .font(.sfCaption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(intensityColor(intensity))
            .clipShape(Capsule())
    }

    private func intensityColor(_ intensity: CardioIntensity) -> Color {
        switch intensity {
        case .easy:     return Color.sfAccent
        case .moderate: return Color.blue
        case .hard:     return Color.orange
        case .max:      return Color.sfDanger
        case .rest:     return Color.sfMuted
        }
    }

    // MARK: - Save

    private func saveAndDismiss() {
        let log = vm.buildLog()
        for split in log.splits { modelContext.insert(split) }
        modelContext.insert(log)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            showingSaveError = true
        }
    }
}
