# Global diary state and the only place that touches the diary file.

const DEFAULT_FILE = "diary.jl"

mutable struct State
    enabled::Bool        # is the diary recording?
    file::String         # "" until chosen; then DEFAULT_FILE resolves against the cwd
    timestamps::Bool     # write a `# HH:MM:SS` comment before each command
end

const STATE = State(false, "", false)

# Guards STATE and the file: the REPL task and the hook-watcher task both use them.
const LOCK = ReentrantLock()

isdiary() = STATE.enabled

# Resolved lazily (not at precompile time) so the default means "the cwd of the user".
diaryfile() = isempty(STATE.file) ? abspath(DEFAULT_FILE) : STATE.file

"Append `text` to the diary file, creating the file and its folder if needed."
function append_to_file(text::AbstractString)
    file = diaryfile()
    mkpath(dirname(file))
    open(io -> write(io, text), file, "a")
    return nothing
end

now_string(format::AbstractString) = Dates.format(now(), format)
