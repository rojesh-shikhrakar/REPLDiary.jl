# Global diary state and the only place that touches the diary file.

const DEFAULT_FILE = "diary.jl"

mutable struct State
    enabled::Bool        # is the diary recording?
    file::String         # "" until chosen; then DEFAULT_FILE resolves against the cwd
    timestamps::Bool     # write a `# HH:MM:SS` comment before each command
    output::Bool         # write the displayed result of each command as `# ` comments
    errors::Symbol       # :skip = drop failed commands, :comment = keep them as comments
    commands::Int        # commands recorded in the current session
    skipped::Int         # failed commands left out in the current session
    exclude::Vector{Regex}   # commands matching any of these are not recorded
    modes::Vector{Symbol}    # only these REPL modes are recorded; empty = all
    redact::Bool             # mask secrets (tokens, passwords) in recorded text
end

const STATE = State(false, "", false, false, :skip, 0, 0, Regex[], Symbol[], false)

# Guards STATE and the file: the REPL task and the hook-watcher task both use them.
const LOCK = ReentrantLock()

isdiary() = STATE.enabled

# Resolved lazily (not at precompile time) so the default means "the cwd of the user".
diaryfile() = isempty(STATE.file) ? abspath(DEFAULT_FILE) : STATE.file

# Byte ranges `(start, stop)` (and how many commands they added to the session
# count) of the entries written this session, newest last.
# `diary(:undo)` truncates the file at the newest range. Header/footer lines are
# not undoable; writing one clears the stack.
const UNDO_STACK = Tuple{Int,Int,Int}[]   # (start, stop, commands counted)

"""
    append_to_file(text; undoable=false, commands=0)

Append `text` to the diary file, creating the file and its folder if needed.
With `undoable=true` the written byte range can later be removed by [`undo!`](@ref).
"""
function append_to_file(text::AbstractString; undoable::Bool=false, commands::Integer=0)
    file = diaryfile()
    mkpath(dirname(file))
    start = isfile(file) ? filesize(file) : 0
    open(io -> write(io, text), file, "a")
    undoable ? push!(UNDO_STACK, (start, start + sizeof(text), commands)) : empty!(UNDO_STACK)
    return nothing
end

"""
    undo!(count=1) -> Int

Remove the last `count` entries written to the diary file this session and return
how many were removed (0 if there was nothing to undo). If the file was changed by
something else since, the saved byte offsets are no longer valid: it warns and
returns -1 without touching the file.
"""
function undo!(count::Integer=1)
    @lock LOCK begin
        removed = 0
        file = diaryfile()
        while removed < count && !isempty(UNDO_STACK)
            start, stop, commands = UNDO_STACK[end]
            if !isfile(file) || filesize(file) != stop
                @warn "Diary file changed outside REPLDiary; cannot undo" file
                empty!(UNDO_STACK)
                return -1
            end
            open(io -> truncate(io, start), file, "r+")
            pop!(UNDO_STACK)
            STATE.commands = max(0, STATE.commands - commands)
            removed += 1
        end
        return removed
    end
end

now_string(format::AbstractString) = Dates.format(now(), format)

"""
    set_options!(; timestamps, output, errors, exclude, modes, redact)

Change the recording options; an option left as `nothing` keeps its value.
"""
function set_options!(; timestamps::Union{Bool,Nothing}=nothing,
                        output::Union{Bool,Nothing}=nothing,
                        errors::Union{Symbol,Nothing}=nothing,
                        exclude=nothing,
                        modes=nothing,
                        redact::Union{Bool,Nothing}=nothing)
    if errors !== nothing && errors ∉ (:skip, :comment)
        throw(ArgumentError("errors must be :skip or :comment, got :$errors"))
    end
    # Validate and convert everything before changing anything.
    exclude === nothing || (exclude = as_regexes(exclude))
    modes === nothing || (modes = as_modes(modes))
    @lock LOCK begin
        timestamps === nothing || (STATE.timestamps = timestamps)
        output === nothing || (STATE.output = output)
        errors === nothing || (STATE.errors = errors)
        exclude === nothing || (STATE.exclude = exclude)
        modes === nothing || (STATE.modes = modes)
        redact === nothing || (STATE.redact = redact)
    end
    return
end

"The current state as a `NamedTuple` (what `diary(:status)` prints)."
diary_status() = (; recording=STATE.enabled, file=diaryfile(),
                    commands=STATE.commands, skipped=STATE.skipped,
                    timestamps=STATE.timestamps, output=STATE.output, errors=STATE.errors,
                    modes=copy(STATE.modes), exclude=copy(STATE.exclude), redact=STATE.redact)

function print_status(io::IO=stdout)
    st = diary_status()
    println(io, "Diary is ", st.recording ? "ON" : "OFF")
    println(io, "  file:     ", st.file)
    println(io, "  commands: ", st.commands, " recorded, ", st.skipped, " failed and skipped (this session)")
    println(io, "  options:  timestamps=", st.timestamps, " output=", st.output, " errors=:", st.errors)
    println(io, "  filters:  modes=", isempty(st.modes) ? "all" : join(st.modes, ","),
            " exclude=", isempty(st.exclude) ? "none" : join(repr.(st.exclude), ", "),
            " redact=", st.redact)
    return
end
