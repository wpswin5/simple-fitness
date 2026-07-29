import SwiftUI
import SwiftData

// MARK: - ImportPreviewView
// The validation gate for a CSV import. Stages the file into a throwaway child
// context, shows what will be created plus blocking errors / non-blocking
// warnings, and commits only on the user's confirmation.

struct ImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let text: String

    @State private var replaceExisting = false
    @State private var staged: CSVImportService.StagedImport?
    @State private var stagingContext: ModelContext?
    @State private var didCommit = false

    var body: some View {
        NavigationStack {
            Group {
                if let staged {
                    content(staged)
                } else {
                    ProgressView("Reading…")
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") { commit() }
                        .fontWeight(.semibold)
                        .disabled(!(staged.map { !$0.hasErrors && !$0.isEmpty } ?? false))
                }
            }
            .onAppear { if staged == nil { restage() } }
            .onChange(of: replaceExisting) { _, _ in restage() }
            .onDisappear { if !didCommit { stagingContext = nil } }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ staged: CSVImportService.StagedImport) -> some View {
        List {
            if staged.isEmpty && !staged.hasErrors {
                Section {
                    Text("Nothing to import. Check that the file has a `#! workout v1` or `#! program v1` section.")
                        .font(.sfCallout)
                        .foregroundStyle(.secondary)
                }
            }

            if !staged.workoutNames.isEmpty {
                Section("Workouts (\(staged.workoutNames.count))") {
                    ForEach(staged.workoutNames, id: \.self) { name in
                        Label(name, systemImage: "dumbbell.fill")
                            .foregroundStyle(Color.sfAccent)
                    }
                }
            }

            if !staged.programs.isEmpty {
                Section("Programs (\(staged.programs.count))") {
                    ForEach(staged.programs) { program in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(program.name, systemImage: "calendar")
                                .foregroundStyle(Color.sfAccent)
                            Text("\(program.weeks) week\(program.weeks == 1 ? "" : "s") · \(program.activeDays) active day\(program.activeDays == 1 ? "" : "s")")
                                .font(.sfCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            let errors = staged.issues.errors
            if !errors.isEmpty {
                Section {
                    ForEach(errors) { issue in
                        issueRow(issue, color: Color.sfDanger, icon: "xmark.octagon.fill")
                    }
                } header: {
                    Text("Errors — must be fixed")
                } footer: {
                    Text("Import is disabled until these are resolved.")
                }
            }

            let warnings = staged.issues.warnings
            if !warnings.isEmpty {
                Section("Warnings") {
                    ForEach(warnings) { issue in
                        issueRow(issue, color: .orange, icon: "exclamationmark.triangle.fill")
                    }
                }
            }

            Section {
                Toggle("Replace items with the same name", isOn: $replaceExisting)
                    .tint(Color.sfAccent)
            } footer: {
                Text("Off: a second copy is created. On: an existing workout or program with a matching name is deleted first.")
            }
        }
    }

    private func issueRow(_ issue: ImportIssue, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.sfCaption)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.message)
                    .font(.sfCallout)
                Text(issue.locationLabel)
                    .font(.sfCaption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Staging

    private func restage() {
        // Dropping the previous child context discards its unsaved graph.
        let result = CSVImportService.stage(
            text: text,
            replaceExisting: replaceExisting,
            container: modelContext.container
        )
        staged = result.summary
        stagingContext = result.context
    }

    private func commit() {
        guard let ctx = stagingContext, let staged, !staged.hasErrors, !staged.isEmpty else { return }
        CSVImportService.commit(context: ctx)
        didCommit = true
        dismiss()
    }
}
