# Run with `julia --project -e 'using Pkg; Pkg.test()'`.
#
# Layout (one file per source file / concern, all sharing helpers.jl):
#
#   test_format.jl      how commands, results and errors look in the file (format.jl)
#   test_filters.jl     modes, exclude patterns and secret redaction     (filters.jl)
#   test_recording.jl   writing live commands to the file                (recorder.jl)
#   test_outcomes.jl    holding a command until it is known to succeed   (outcomes.jl)
#   test_last_n.jl      diary(n) and the REPL history                    (recorder.jl, history.jl)
#   test_api.jl         diary(...) arguments, options and file handling  (api.jl, state.jl)
#   test_status_undo.jl diary(:status) and diary(:undo)                  (state.jl)
#   test_hooks.jl       the REPL wrappers, without a real REPL           (hooks.jl)
#
# Not covered here: a real interactive REPL (prompt, Pkg mode, the backend tap).
# Those are checked by hand in a terminal.

using Test
using REPLDiary

include("helpers.jl")

@testset "REPLDiary" begin
    include("test_format.jl")
    include("test_filters.jl")
    include("test_recording.jl")
    include("test_outcomes.jl")
    include("test_last_n.jl")
    include("test_api.jl")
    include("test_status_undo.jl")
    include("test_hooks.jl")
end
