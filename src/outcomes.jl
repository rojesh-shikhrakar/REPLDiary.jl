# Deciding whether a command succeeded, so failed commands are not recorded.
#
# The REPL runs a command *after* our hook sees it, so a command is first
# "pending" and is written to the diary only once it is known to have succeeded.
# The outcome comes from the REPL backend, which answers every evaluation with a
# `(value, iserror)` pair on a channel (see `install_outcome_tap!` in hooks.jl).
#
# A command that never reaches the backend, such as one with a syntax error,
# gets no answer at all. Once the REPL has finished handling the line
# (`finish_submission!`), a command still pending is therefore a failure.
#
# Exception: Pkg mode runs its commands without the backend and handles its own
# errors, so its outcome is unknowable. Pkg commands are always recorded.

"""
How a command went. `value` is the result of a successful command and `error` the
message of a failed one (`nothing` when the REPL gave no details).
"""
struct Outcome
    succeeded::Bool
    value::Any
    error::Union{String,Nothing}
end
Outcome(succeeded::Bool) = Outcome(succeeded, nothing, nothing)

"""
Turn the backend's `value => iserror` response into an `Outcome`. On failure the
value is the exception stack; its last entry is the exception the REPL reports.
"""
function Outcome(response::Pair)
    value, failed = response.first, response.second
    failed || return Outcome(true, value, nothing)
    message = try
        exception = value isa AbstractVector && !isempty(value) ? value[end].exception : value
        Base.invokelatest(sprint, showerror, exception)
    catch
        nothing
    end
    return Outcome(false, nothing, message)
end

mutable struct Pending
    label::String        # "" for Julia code, else the mode label ("shell>", …)
    text::String
    history_index::Int   # position of the command in the REPL history
end

const PENDING = Ref{Union{Pending,Nothing}}(nothing)

# History position => (text, succeeded). Lets `diary(n)` skip failed commands
# that are still in the REPL history. The text guards against shifted positions.
const OUTCOMES = Dict{Int,Tuple{String,Bool}}()

"A line was submitted at the prompt; wait for its outcome."
function submit!(label::AbstractString, text::AbstractString)
    @lock LOCK PENDING[] = Pending(label, text, history_length())
    return
end

"The backend reported how the pending command went."
resolve_pending!(succeeded::Bool) = resolve_pending!(Outcome(succeeded))

function resolve_pending!(outcome::Outcome)
    pending = @lock LOCK begin
        p = PENDING[]
        PENDING[] = nothing
        p
    end
    pending === nothing && return
    OUTCOMES[pending.history_index] = (pending.text, outcome.succeeded)
    record(pending.label, pending.text, outcome)
    return
end

is_pkg_mode(label::AbstractString) = endswith(label, "pkg>")

"The REPL finished handling the line. If nothing resolved it, it never ran: it failed."
function finish_submission!()
    pending = PENDING[]
    pending === nothing && return
    resolve_pending!(is_pkg_mode(pending.label))
end

"`true` unless the command at history `index` (with this `text`) is known to have failed."
function succeeded_or_unknown(index::Integer, text::AbstractString)
    outcome = get(OUTCOMES, index, nothing)
    return outcome === nothing || outcome[1] != text || outcome[2]
end

# `exit()` never returns, so it never gets an outcome. Nothing else can still be
# pending at exit, so write it rather than lose the last command.
function flush_pending_at_exit()
    try
        PENDING[] === nothing || resolve_pending!(true)
    catch
    end
    return
end
