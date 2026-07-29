import Foundation
import SwiftData

// MARK: - CSVImportService
// Orchestrates a full import as UNSAVED context changes (a "staged" graph), so the
// preview can show real counts and resolve real references. The caller then either
// commit()s (save) or cancel()s (rollback) — one call each, fully transactional.
//
// Workout sections are built first so program sections can bind their `name`
// references to freshly-imported workouts as well as pre-existing ones.

@MainActor
enum CSVImportService {

    struct ProgramSummary: Identifiable {
        let id = UUID()
        var name: String
        var weeks: Int
        var activeDays: Int
    }

    struct StagedImport {
        var workoutNames: [String]
        var programs: [ProgramSummary]
        var issues: [ImportIssue]
        var hasErrors: Bool { issues.hasErrors }
        var isEmpty: Bool { workoutNames.isEmpty && programs.isEmpty }
    }

    /// Builds the object graph in a dedicated child context (autosave off) and
    /// returns the summary plus that context. Commit saves it; cancel just drops
    /// it — so nothing touches the store until the user confirms, and the main
    /// context / @Query views are untouched during preview.
    static func stage(text: String, replaceExisting: Bool, container: ModelContainer) -> (summary: StagedImport, context: ModelContext) {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let (doc, parseIssues) = CSVParser.parse(text)
        var issues = parseIssues

        // Snapshot the existing library BEFORE building anything.
        let existingExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let existingWorkouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        let existingPrograms = (try? context.fetch(FetchDescriptor<Program>())) ?? []
        let existingCardio = ((try? context.fetch(FetchDescriptor<CardioTemplate>())) ?? []).filter { $0.isTemplate }

        var resolver = ExerciseResolver(library: existingExercises, context: context)

        // Decode + build all workout sections.
        var mapped: [MappedWorkout] = []
        for section in doc.sections where section.type == "workout" {
            let (workouts, wIssues) = WorkoutCSV.decode(section, resolver: &resolver)
            issues.append(contentsOf: wIssues)
            mapped.append(contentsOf: workouts)
        }

        // Replace-by-name: delete pre-existing workouts that an import overrides.
        let importedWorkoutKeys = Set(mapped.map { ExerciseResolver.normalize($0.name) })
        if replaceExisting {
            for w in existingWorkouts where importedWorkoutKeys.contains(ExerciseResolver.normalize(w.name)) {
                context.delete(w)
            }
        } else {
            for w in existingWorkouts where importedWorkoutKeys.contains(ExerciseResolver.normalize(w.name)) {
                issues.append(.warning("A workout named '\(w.name)' already exists — a second copy will be created", section: "workout"))
            }
        }

        var builtWorkouts: [Workout] = []
        for m in mapped { builtWorkouts.append(buildWorkout(m, context: context)) }

        // Workout lookup: existing (minus replaced) + freshly built, imported wins.
        var workoutLookup: [String: Workout] = [:]
        for w in existingWorkouts where !(replaceExisting && importedWorkoutKeys.contains(ExerciseResolver.normalize(w.name))) {
            workoutLookup[ExerciseResolver.normalize(w.name)] = w
        }
        for w in builtWorkouts { workoutLookup[ExerciseResolver.normalize(w.name)] = w }

        let cardioLookup: [String: CardioTemplate] = Dictionary(
            existingCardio.map { (ExerciseResolver.normalize($0.name.isEmpty ? $0.displayName : $0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Decode + build program sections.
        var programSummaries: [ProgramSummary] = []
        for section in doc.sections where section.type == "program" {
            let (parsed, pIssues) = ProgramCSV.decode(section, workoutLookup: workoutLookup, cardioLookup: cardioLookup)
            issues.append(contentsOf: pIssues)
            guard let parsed else { continue }

            if replaceExisting {
                let key = ExerciseResolver.normalize(parsed.name)
                for p in existingPrograms where ExerciseResolver.normalize(p.name) == key { context.delete(p) }
            }
            _ = buildProgram(parsed, context: context)
            let activeDays = parsed.weeks.reduce(0) { $0 + $1.days.filter { !$0.isRestDay }.count }
            programSummaries.append(ProgramSummary(name: parsed.name, weeks: parsed.weeks.count, activeDays: activeDays))
        }

        for section in doc.sections where section.type != "workout" && section.type != "program" {
            issues.append(.warning("Ignored unknown section type '\(section.type)'", line: section.directiveLine))
        }

        let summary = StagedImport(workoutNames: builtWorkouts.map(\.name), programs: programSummaries, issues: issues)
        return (summary, context)
    }

    /// Persists the staged child context to the store.
    static func commit(context: ModelContext) {
        try? context.save()
    }

    /// Nothing to do — an unsaved child context simply gets discarded by the caller.
    static func cancel(context: ModelContext) {}

    // MARK: - Builders (mirror CreateWorkoutViewModel.buildSets / CreateProgramViewModel.buildWeeks,
    // but insert only — no save — so the whole import stays a single staged transaction.)

    private static func buildWorkout(_ mapped: MappedWorkout, context: ModelContext) -> Workout {
        let workout = Workout(name: mapped.name)
        workout.workoutDescription = mapped.summary

        for (setIndex, draft) in mapped.sets.enumerated() {
            let slots: [ExerciseInSet] = draft.exercises.enumerated().map { i, dex in
                let eis = ExerciseInSet(exercise: dex.exercise, isTimeBased: dex.isTimeBased, order: i)
                context.insert(eis)
                return eis
            }
            let rounds: [SetRound] = draft.rounds.enumerated().map { rIdx, dr in
                let targets: [ExerciseTarget] = draft.exercises.enumerated().map { i, dex in
                    let dt = i < dr.targets.count ? dr.targets[i] : DraftTarget()
                    let t = ExerciseTarget(
                        order: i,
                        exerciseName: dex.exercise.name,
                        targetReps: dex.isTimeBased ? nil : dt.targetReps,
                        targetTime: dex.isTimeBased ? dt.targetTime : nil,
                        targetWeight: dt.targetWeight,
                        effortLevel: dt.effortLevel
                    )
                    context.insert(t)
                    return t
                }
                let round = SetRound(order: rIdx, restSeconds: dr.restSeconds, targets: targets)
                context.insert(round)
                return round
            }
            let set = WorkoutSet(exercises: slots, rounds: rounds, order: setIndex)
            context.insert(set)
            workout.sets.append(set)
        }
        workout.estimatedDuration = estimatedMinutes(mapped.sets)
        context.insert(workout)
        return workout
    }

    private static func buildProgram(_ parsed: ParsedProgram, context: ModelContext) -> Program {
        let program = Program(name: parsed.name, targetGoal: parsed.goal, difficultyLevel: parsed.difficulty)
        program.programDescription = parsed.description

        for draftWeek in parsed.weeks {
            let days: [ProgramDay] = draftWeek.days.map { draftDay in
                let activities: [ProgramDayActivity] = draftDay.activities.enumerated().map { index, draftActivity in
                    var cardioTemplate: CardioTemplate? = nil
                    if let dc = draftActivity.cardioTemplate {
                        let t = CardioTemplate(cardioType: dc.type)
                        t.structureType = dc.structureType
                        t.targetDurationSeconds = dc.targetDurationSeconds
                        t.targetDistance = Double(dc.targetDistance)
                        t.distanceUnit = dc.distanceUnit
                        t.isIntervalWorkout = dc.isIntervalWorkout
                        t.notes = dc.notes
                        if dc.isIntervalWorkout {
                            t.intervals = dc.intervals.enumerated().map { ivIdx, di in
                                let iv = CardioTemplateInterval(order: ivIdx)
                                iv.label = di.label
                                iv.isRest = di.isRest
                                iv.intensity = di.intensity
                                iv.distanceValue = Double(di.distanceText)
                                iv.durationSeconds = di.durationTotalSeconds
                                iv.paceSecondsPerUnit = di.paceSecondsPerUnit
                                iv.inclinePercent = di.inclineValue
                                context.insert(iv)
                                return iv
                            }
                        }
                        context.insert(t)
                        cardioTemplate = t
                    }
                    let activity = ProgramDayActivity(order: index, workout: draftActivity.workout, cardioTemplate: cardioTemplate)
                    context.insert(activity)
                    return activity
                }
                let day = ProgramDay(dayOfWeek: draftDay.dayOfWeek, activities: activities)
                context.insert(day)
                return day
            }
            let week = ProgramWeek(weekNumber: draftWeek.weekNumber, days: days)
            context.insert(week)
            program.weeks.append(week)
        }

        context.insert(program)
        return program
    }

    /// Same heuristic as CreateWorkoutViewModel.estimatedDurationMinutes.
    private static func estimatedMinutes(_ sets: [DraftWorkoutSet]) -> Int {
        var total = 0
        for set in sets {
            for round in set.rounds {
                total += set.exercises.count * 45
                total += round.restSeconds
            }
        }
        return max(1, total / 60)
    }
}
