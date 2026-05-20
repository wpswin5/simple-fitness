import SwiftUI
import SwiftData

struct WorkoutListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Workout.createdDate, order: .reverse)
    private var workouts: [Workout]

    @Query(sort: \CardioLog.date, order: .reverse)
    private var cardioLogs: [CardioLog]

    @Query(sort: \CardioTemplate.name)
    private var allTemplates: [CardioTemplate]

    private var savedTemplates: [CardioTemplate] {
        allTemplates.filter { $0.isTemplate }
    }

    enum Segment { case strength, cardio }
    @State private var segment: Segment = .strength
    @State private var showingCreateWorkout = false
    @State private var showingLogCardio = false
    @State private var showingCreateTemplate = false
    @State private var editingTemplate: CardioTemplate? = nil
    @State private var workoutToDelete: Workout?
    @State private var cardioLogToDelete: CardioLog?
    @State private var templateToDelete: CardioTemplate?

    var body: some View {
        NavigationStack {
            Group {
                switch segment {
                case .strength:
                    if workouts.isEmpty { strengthEmptyState } else { strengthList }
                case .cardio:
                    cardioView
                }
            }
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    segmentPicker
                }
                ToolbarItem(placement: .topBarTrailing) {
                    addButton
                }
            }
            .sheet(isPresented: $showingCreateWorkout) {
                CreateWorkoutView()
            }
            .sheet(isPresented: $showingLogCardio) {
                LogCardioView()
            }
            .sheet(isPresented: $showingCreateTemplate) {
                CreateCardioTemplateView()
            }
            .sheet(item: $editingTemplate) { template in
                CreateCardioTemplateView(editing: template)
            }
        }
    }

    // MARK: - Toolbar items

    private var segmentPicker: some View {
        Picker("", selection: $segment) {
            Text("Strength").tag(Segment.strength)
            Text("Cardio").tag(Segment.cardio)
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
    }

    private var addButton: some View {
        Group {
            if segment == .strength {
                Button {
                    showingCreateWorkout = true
                } label: {
                    Image(systemName: "plus").fontWeight(.semibold)
                }
            } else {
                Menu {
                    Button {
                        showingLogCardio = true
                    } label: {
                        Label("Log Cardio", systemImage: "plus.circle")
                    }
                    Button {
                        showingCreateTemplate = true
                    } label: {
                        Label("New Template", systemImage: "square.and.pencil")
                    }
                } label: {
                    Image(systemName: "plus").fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Strength List

    private var strengthList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(workouts) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                        WorkoutCard(workout: workout)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { workoutToDelete = workout } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) { workoutToDelete = workout } label: {
                            Label("Delete Workout", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(Spacing.md)
        }
        .confirmationDialog("Delete Workout?", isPresented: .constant(workoutToDelete != nil), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let w = workoutToDelete {
                    modelContext.delete(w)
                    try? modelContext.save() // Non-critical: SwiftData will retry on next launch
                    workoutToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { workoutToDelete = nil }
        }
    }

    // MARK: - Cardio View (templates + history)

    @ViewBuilder
    private var cardioView: some View {
        if savedTemplates.isEmpty && cardioLogs.isEmpty {
            cardioEmptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                    // Templates section
                    templatesSection

                    // History section
                    if !cardioLogs.isEmpty {
                        historySection
                    }
                }
                .padding(Spacing.md)
            }
            .confirmationDialog("Delete Template?", isPresented: .constant(templateToDelete != nil), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let t = templateToDelete {
                        modelContext.delete(t)
                        try? modelContext.save()
                        templateToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { templateToDelete = nil }
            }
            .confirmationDialog("Delete Cardio Log?", isPresented: .constant(cardioLogToDelete != nil), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let l = cardioLogToDelete {
                        modelContext.delete(l)
                        try? modelContext.save()
                        cardioLogToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { cardioLogToDelete = nil }
            }
        }
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Templates")
                    .font(.sfSubhead)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Spacer()
                Button {
                    showingCreateTemplate = true
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.sfCaption)
                        .foregroundStyle(Color.sfAccent)
                }
            }

            if savedTemplates.isEmpty {
                // Inline prompt when no templates yet but logs exist
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.sfAccent.opacity(0.6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No templates yet")
                            .font(.sfSubhead)
                        Text("Save a preconfigured workout to reuse it quickly.")
                            .font(.sfCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(Spacing.md)
                .background(Color.sfSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            } else {
                VStack(spacing: 1) {
                    ForEach(savedTemplates) { template in
                        CardioTemplateRow(template: template)
                            .background(Color.sfSurface)
                            .onTapGesture { editingTemplate = template }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    templateToDelete = template
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingTemplate = template
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Color.sfAccent)
                            }
                            .contextMenu {
                                Button { editingTemplate = template } label: {
                                    Label("Edit Template", systemImage: "pencil")
                                }
                                Button(role: .destructive) { templateToDelete = template } label: {
                                    Label("Delete Template", systemImage: "trash")
                                }
                            }

                        if template.id != savedTemplates.last?.id {
                            Divider().padding(.leading, Spacing.md)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("History")
                .font(.sfSubhead)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)

            LazyVStack(spacing: Spacing.sm) {
                ForEach(cardioLogs) { log in
                    CardioLogCard(log: log)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { cardioLogToDelete = log } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) { cardioLogToDelete = log } label: {
                                Label("Delete Log", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    // MARK: - Empty States

    private var strengthEmptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "dumbbell")
                .font(.system(size: 52))
                .foregroundStyle(Color.sfAccent.opacity(0.7))
            VStack(spacing: Spacing.xs) {
                Text("No workouts yet")
                    .font(.sfHeadline)
                Text("Tap + to create your first workout.")
                    .font(.sfCallout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Create Workout") { showingCreateWorkout = true }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 220)
        }
        .padding(Spacing.xl)
    }

    private var cardioEmptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "figure.run")
                .font(.system(size: 52))
                .foregroundStyle(Color.sfAccent.opacity(0.7))
            VStack(spacing: Spacing.xs) {
                Text("No cardio yet")
                    .font(.sfHeadline)
                Text("Tap + to log a session or save a template.")
                    .font(.sfCallout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: Spacing.sm) {
                Button("Log Cardio") { showingLogCardio = true }
                    .buttonStyle(PrimaryButtonStyle())
                Button("New Template") { showingCreateTemplate = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(Spacing.xl)
    }
}

// MARK: - Template Row

private struct CardioTemplateRow: View {
    let template: CardioTemplate

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: template.cardioType.icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.sfAccent)
                .frame(width: 32, height: 32)
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

            Image(systemName: "chevron.right")
                .font(.sfCaption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

#Preview {
    WorkoutListView()
        .modelContainer(for: [
            Workout.self, WorkoutSet.self, ExerciseInSet.self, Exercise.self,
            WorkoutLog.self, WorkoutSetLog.self, ExerciseLog.self,
            CardioLog.self, CardioSplit.self, SwimSet.self,
            CardioTemplate.self, CardioTemplateInterval.self
        ], inMemory: true)
}
