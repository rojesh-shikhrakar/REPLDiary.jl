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
    diary(:on | :off | :status | "on" | "off" | "status")
    diary(filename)
    diary(n)
    diary(:on | :off | filename, n)
    diary(...; timestamps=false, output=false, errors=:skip,
               exclude=[], modes=[], redact=false)

MATLAB-compatible control of the command diary.

- `diary()` toggles recording.
- `diary(:on)` / `diary(:off)` switch recording on or off.
- `diary(:status)` prints whether the diary is on, its file, the number of commands
  recorded or skipped this session, and the options.
- `diary(filename)` sets the diary file and starts recording. A name without
  an extension gets `.jl` appended. Existing files are appended to.
- `diary(n)` writes the last `n` commands from the REPL history to the diary
  file, without the `diary(...)` calls themselves. It does not change whether
  recording is on. `diary(:on, n)` / `diary("file.jl", n)` first start recording
  and then add the last `n` commands, so they come first in the new session.

Options (they stay in effect until changed):

- `diary(:undo)` removes the last recorded command from the diary file;
  `diary(:undo, k)` removes the last `k`. A block written by `diary(n)` counts
  as one entry. Only entries written in the current session can be undone.
- `timestamps=true` writes a `# HH:MM:SS` comment before each command.
- `output=true` writes the result the REPL displays after each Julia command as
  `# ` comment lines. Text printed with `println` is not captured.
- `errors=:comment` keeps failed commands, as `# failed> command` followed by
  `# ERROR: message`; the default `errors=:skip` leaves them out.
- `exclude=[r"password", "secret_"]` never records commands matching any of the
  patterns (`Regex`, or `String` matched literally). `exclude=[]` clears the list.
  Excluded commands are not recorded by `diary(n)` either.
- `modes=[:julia]` records only the listed REPL modes (`:julia`, `:shell`, `:help`,
  `:pkg`); `modes=[]` records all of them again.
- `redact=true` masks likely secrets in what is written (GitHub/AWS/Slack/API-key
  tokens, JWTs, `Bearer …`, and the value in `password = "…"`, `token = "…"`,
  `api_key = "…"` assignments) as `<redacted>`. This is pattern matching, not a
  guarantee; use `exclude` for anything sensitive.
"""
function diary(; kwargs...)
    set_options!(; kwargs...)
    isdiary() ? stop_recording!() : start!()
    return nothing
end

function diary(arg::Union{AbstractString,Symbol}; kwargs...)
    word = lowercase(String(arg))
    if word == "on"
        start!(; kwargs...)
    elseif word == "off"
        set_options!(; kwargs...)
        stop_recording!()
    elseif word == "undo"
        report_undo(undo!(1))
    elseif word == "status"
        set_options!(; kwargs...)
        print_status()
    else
        start!(file=String(arg); kwargs...)   # anything else is a file name
    end
    return nothing
end

function diary(n::Integer; kwargs...)
    n >= 0 || throw(ArgumentError("number of commands must be non-negative, got $n"))
    set_options!(; kwargs...)
    write_last(n)
    return nothing
end

function diary(arg::Union{AbstractString,Symbol}, n::Integer; kwargs...)
    if lowercase(String(arg)) == "undo"
        n >= 0 || throw(ArgumentError("number of entries must be non-negative, got $n"))
        report_undo(undo!(n))
        return nothing
    end
    n >= 0 || throw(ArgumentError("number of commands must be non-negative, got $n"))  # before any side effect
    diary(arg; kwargs...)
    diary(n)
end

# ── helpers ─────────────────────────────────────────────────────────────────

report_undo(removed::Integer) =
    removed == 0 ? (@info "REPLDiary: nothing to undo"; nothing) : nothing

"A file name without extension gets `.jl`; the result is always absolute."
function normalize_file(name::AbstractString)
    isempty(splitext(name)[2]) && (name *= ".jl")
    return abspath(name)
end

"""
    start!(; file=nothing, options...)

Select the file (if given), apply the options, install the REPL hooks and start
recording. Switching to a different file while recording closes the old session first.
"""
function start!(; file::Union{String,Nothing}=nothing, kwargs...)
    set_options!(; kwargs...)    # validate first so a bad option changes nothing else
    @lock LOCK begin
        if file !== nothing
            new_file = normalize_file(file)
            isdiary() && new_file != diaryfile() && stop_recording!()
            STATE.file = new_file
        else
            STATE.file = diaryfile()   # pin the default to the current directory
        end
        _install_hooks()
        start_recording!()
        ensure_watcher_running()
    end
    return
end
