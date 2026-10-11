"""
    REPLDiary

A MATLAB-style `diary` for the Julia REPL. Every command typed at the prompt is
appended to a plain-text Julia file while the diary is on.

    using REPLDiary
    diary()               # toggle (MATLAB: `diary`)
    diary(:on)            # start recording to the current diary file ("diary.jl")
    diary(:off)           # stop recording
    diary("session.jl")   # set the file and start recording (MATLAB: `diary filename`)
    diary(5)              # write the last 5 commands to the diary file
    diary(:status)        # show whether it is on, the file and the counts
    diary("s.jl"; output=true, errors=:comment)   # also keep results and failed commands
    isdiary()             # is the diary on?          (MATLAB: get(0,'Diary'))
    diaryfile()           # absolute path of the file (MATLAB: get(0,'DiaryFile'))

Input from the shell (`;`), help (`?`) and Pkg (`]`) modes is recorded as
comments so the diary file stays a valid Julia script.

# How it works

The REPL calls each mode's `on_done` callback with the submitted text. We wrap
those callbacks (`hooks.jl`) so every submitted line is noted and then passed to
the original callback, leaving REPL behaviour untouched. The line is written by
[`record`](@ref) (`recorder.jl`) only once the REPL backend reports that it
succeeded (`outcomes.jl`), so failed commands are never recorded. `diary(n)`
instead reads the REPL's own history (`history.jl`) and skips known failures.

| file          | responsibility                                          |
|:------------- |:------------------------------------------------------- |
| `state.jl`    | the global on/off state, file path and file appends     |
| `format.jl`   | turning a command into diary-file text                  |
| `filters.jl`  | which modes/commands are allowed; secret masking        |
| `recorder.jl` | writing live commands and the last `n` history entries  |
| `outcomes.jl` | holding a command until it is known to have succeeded   |
| `history.jl`  | reading the REPL history across Julia versions          |
| `hooks.jl`    | wrapping the REPL modes and the red-circle prompt       |
| `api.jl`      | the user-facing `diary`, `isdiary`, `diaryfile`         |
"""
module REPLDiary

using Dates
using REPL
using REPL.LineEdit

export diary, isdiary, diaryfile

include("state.jl")
include("format.jl")
include("filters.jl")
include("outcomes.jl")
include("recorder.jl")
include("history.jl")
include("hooks.jl")
include("api.jl")

function __init__()
    # Support `using REPLDiary` from startup.jl: the REPL interface does not
    # exist yet at that point, so wait for it in the background.
    if isinteractive()
        atreplinit(_ -> _install_hooks_when_ready())
        atexit(flush_pending_at_exit)
    end
    return
end

end # module
