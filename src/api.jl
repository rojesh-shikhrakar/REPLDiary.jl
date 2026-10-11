# The user-facing functions. Each `diary` method resolves its arguments and then
# calls the building blocks in recorder.jl, so this file stays short.

"""
    isdiary() -> Bool

Whether the diary is currently recording.
"""
isdiary

"""
    diaryfile() -> String

Absolute path of the current diary file.
"""
diaryfile

"""
    diary()
    diary(:on | :off | "on" | "off")
    diary(filename)
    diary(n)
    diary(:on | :off | filename, n)
    diary(...; timestamps=false)

MATLAB-compatible control of the command diary.

- `diary()` toggles recording.
- `diary(:on)` / `diary(:off)` switch recording on or off.
- `diary(filename)` sets the diary file and starts recording. A name without
  an extension gets `.jl` appended. Existing files are appended to.
- `diary(n)` writes the last `n` commands from the REPL history to the diary
  file, without the `diary(...)` calls themselves. It does not change whether
  recording is on. `diary(:on, n)` / `diary("file.jl", n)` first start recording
  and then add the last `n` commands, so they come first in the new session.
- `timestamps=true` writes a `# HH:MM:SS` comment before each command.
"""
function diary(; timestamps::Union{Bool,Nothing}=nothing)
    isdiary() ? stop_recording!() : start!(; timestamps)
    return nothing
end

function diary(arg::Union{AbstractString,Symbol}; timestamps::Union{Bool,Nothing}=nothing)
    word = lowercase(String(arg))
    if word == "on"
        start!(; timestamps)
    elseif word == "off"
        stop_recording!()
    else
        start!(file=String(arg); timestamps)   # anything else is a file name
    end
    return nothing
end

function diary(n::Integer; timestamps::Union{Bool,Nothing}=nothing)
    n >= 0 || throw(ArgumentError("number of commands must be non-negative, got $n"))
    set_timestamps!(timestamps)
    write_last(n)
    return nothing
end

function diary(arg::Union{AbstractString,Symbol}, n::Integer; timestamps::Union{Bool,Nothing}=nothing)
    diary(arg; timestamps)
    diary(n)
end

# ── helpers ─────────────────────────────────────────────────────────────────

set_timestamps!(t::Bool) = (STATE.timestamps = t; nothing)
set_timestamps!(::Nothing) = nothing

"A file name without extension gets `.jl`; the result is always absolute."
function normalize_file(name::AbstractString)
    isempty(splitext(name)[2]) && (name *= ".jl")
    return abspath(name)
end

"""
    start!(; file=nothing, timestamps=nothing)

Select the file (if given), install the REPL hooks and start recording. Switching
to a different file while recording closes the old session first.
"""
function start!(; file::Union{String,Nothing}=nothing, timestamps::Union{Bool,Nothing}=nothing)
    @lock LOCK begin
        if file !== nothing
            new_file = normalize_file(file)
            isdiary() && new_file != diaryfile() && stop_recording!()
            STATE.file = new_file
        else
            STATE.file = diaryfile()   # pin the default to the current directory
        end
        set_timestamps!(timestamps)
        _install_hooks()
        start_recording!()
        ensure_watcher_running()
    end
    return
end
