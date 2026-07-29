import Foundation

// MARK: - CSVTemplate
// The documented, self-describing template users download to author against.
// It is itself a valid import file (imports cleanly as-is).

enum CSVTemplate {
    static let text = """
    # Simple Fitness — import template
    # Lines starting with '#' are comments and are ignored.
    #   '#! <type> v1' begins a section (workout or program)
    #   '#: key = value' sets section metadata
    #
    # ============ WORKOUT ============
    # Columns: block,exercise,muscle_group,timed,set,reps,weight,effort,rest
    #   block   — groups exercises; TWO exercises sharing a block = a superset
    #   set     — working-set number (1,2,3...); vary reps/weight across sets here
    #   timed   — true for holds like planks; then 'reps' is read as seconds
    #   weight  — pounds; leave blank for bodyweight movements
    #   effort  — percent of 1-rep-max (40-100); rest — seconds after the set
    #! workout v1
    #: name = Sample Push Day
    #: description = Chest, shoulders, triceps
    block,exercise,muscle_group,timed,set,reps,weight,effort,rest
    1,Bench Press,chest,false,1,8,135,72,120
    1,Bench Press,chest,false,2,6,155,78,150
    1,Bench Press,chest,false,3,4,185,85,180
    2,Overhead Press,shoulders,false,1,8,95,70,90
    2,Overhead Press,shoulders,false,2,8,95,70,90
    2,Overhead Press,shoulders,false,3,8,95,70,90
    3,Lateral Raise,shoulders,false,1,15,20,60,45
    3,Tricep Dip,triceps,false,1,12,,60,45
    4,Plank,core,true,1,60,,,45
    4,Plank,core,true,2,45,,,45

    # ============ PROGRAM ============
    # Columns: week,day,type,name
    #   day  — monday..sunday    type — workout or cardio
    #   name — must match a workout above (or already in the app),
    #          or, for cardio, a saved cardio template
    #   omit a day = rest day; repeat a week/day to stack activities
    #! program v1
    #: name = Sample 2-Week Block
    #: goal = hypertrophy
    #: difficulty = intermediate
    week,day,type,name
    1,monday,workout,Sample Push Day
    1,thursday,workout,Sample Push Day
    2,monday,workout,Sample Push Day
    2,thursday,workout,Sample Push Day
    """
}
