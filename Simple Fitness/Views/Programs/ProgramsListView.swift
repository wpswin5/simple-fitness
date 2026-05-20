import SwiftUI
import SwiftData

struct ProgramsListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Program.createdDate, order: .reverse) private var programs: [Program]
    @Query(sort: \ProgramRegistration.startDate, order: .reverse) private var registrations: [ProgramRegistration]

    @State private var showingCreate = false
    @State private var programToEdit: Program?

    private var activeRegistration: ProgramRegistration? {
        registrations.first { $0.isActive }
    }

    var body: some View {
        NavigationStack {
            Group {
                if programs.isEmpty {
                    emptyState
                } else {
                    programList
                }
            }
            .navigationTitle("Programs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateProgramView()
            }
            .sheet(item: $programToEdit) { program in
                CreateProgramView(editing: program)
            }
        }
    }

    // MARK: - List

    private var programList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {

                // Active program section
                if let reg = activeRegistration, let program = reg.program {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        sectionHeader("Active Program")
                        NavigationLink(destination: ProgramDetailView(program: program, registration: reg)) {
                            ProgramCard(
                                program: program,
                                isActive: true,
                                currentWeek: reg.currentWeek
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().padding(.vertical, Spacing.xs)
                }

                // All programs
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    sectionHeader(activeRegistration != nil ? "All Programs" : "My Programs")

                    ForEach(programs) { program in
                        NavigationLink(destination: ProgramDetailView(program: program, registration: registrations.first { $0.program?.id == program.id })) {
                            ProgramCard(
                                program: program,
                                isActive: activeRegistration?.program?.id == program.id,
                                currentWeek: registrations.first { $0.program?.id == program.id }?.currentWeek
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                programToEdit = program
                            } label: {
                                Label("Edit Program", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteProgram(program)
                            } label: {
                                Label("Delete Program", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(Spacing.md)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(Color.sfAccent.opacity(0.6))
            VStack(spacing: Spacing.xs) {
                Text("No programs yet")
                    .font(.sfHeadline)
                Text("Create a multi-week training plan to structure your training.")
                    .font(.sfCallout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Create Program") { showingCreate = true }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 220)
        }
        .padding(Spacing.xl)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sfSubhead)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deleteProgram(_ program: Program) {
        // Deactivate any registrations first
        registrations
            .filter { $0.program?.id == program.id }
            .forEach { $0.isActive = false }
        modelContext.delete(program)
        try? modelContext.save()
    }
}
