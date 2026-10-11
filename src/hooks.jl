# Plugging into the REPL: recording typed input and showing the red-circle prompt.
#
# Every REPL mode (`julia>`, `shell>`, `help?>`, `pkg>`) is a `LineEdit.Prompt`
# whose `on_done(state, buffer, ok)` callback runs when a line is submitted, and
# whose `prompt` is the text (or a function returning the text) shown to the user.
# We replace both with thin wrappers that delegate to the originals.

"The live REPL if its prompt interface is already built, otherwise `nothing`."
function active_line_edit_repl()
    isdefined(Base, :active_repl) || return nothing
    repl = Base.active_repl
    repl isa REPL.LineEditREPL || return nothing
    isdefined(repl, :interface) && repl.interface isa LineEdit.ModalInterface || return nothing
    return repl
end

# ── recording wrapper ───────────────────────────────────────────────────────

"""
Wraps a mode's `on_done`: note the submitted text, then run the original.
Subtyping `Function` is required because `Prompt.on_done` is typed `Function`.
"""
struct RecordingHook{F} <: Function
    original::F
    label::String
end

function (hook::RecordingHook)(s, buf, ok)
    try
        # `copy` so reading the text does not consume the buffer the REPL evaluates.
        ok && submit!(hook.label, String(take!(copy(buf))))
    catch err
        # Never let diary trouble break the user's REPL; warn once, not per line.
        @warn "REPLDiary could not track a command" exception = err maxlog = 1
    end
    try
        return hook.original(s, buf, ok)   # parses and evaluates the line
    finally
        try
            finish_submission!()
        catch err
            @warn "REPLDiary could not record a command" exception = err maxlog = 1
        end
    end
end

# ── red-circle prompt ───────────────────────────────────────────────────────

"""
Wraps a mode's prompt so it starts with 🔴 while recording. `original` is the
prompt text, or a no-argument function returning it (the Julia prompt is one).
"""
struct RecordingPrompt{P} <: Function
    original::P
end

function (prompt::RecordingPrompt)()
    text = String(prompt_text(prompt.original))
    return STATE.enabled ? "🔴 " * text : text
end

prompt_text(p::Function) = p()
prompt_text(p) = p

"""
Prompt text of `mode` without any decoration, or `fallback` for prompts that
cannot be evaluated without arguments (Pkg's).
"""
function plain_prompt(mode::LineEdit.Prompt, fallback::AbstractString)
    p = mode.prompt
    p isa RecordingPrompt && (p = p.original)
    try
        return String(strip(String(prompt_text(p))))
    catch
        return String(fallback)
    end
end

# ── outcome tap ─────────────────────────────────────────────────────────────

# The backend task answers each evaluation with `put!(backend.response_channel,
# value => iserror)`, and the front end `take!`s it from the same channel. We
# point the backend at a new channel and relay everything to the original one,
# looking at the `iserror` flag on the way. The front end is untouched.
const TAPPED_BACKEND = Ref{Any}(nothing)

function install_outcome_tap!()
    backend = Base.active_repl_backend
    backend isa REPL.REPLBackend || return false
    backend === TAPPED_BACKEND[] && return true
    downstream = backend.response_channel
    upstream = Channel{Any}(1)
    errormonitor(@async begin
        try
            for response in upstream
                # Resolve before forwarding: the REPL cannot move on until it
                # receives the response, so the outcome is always known by then.
                try
                    resolve_pending!(Outcome(response))
                catch err
                    @warn "REPLDiary could not record a command" exception = err maxlog = 1
                end
                put!(downstream, response)
            end
        catch err
            err isa InvalidStateException || rethrow()   # downstream closed: REPL is exiting
        end
    end)
    backend.response_channel = upstream
    TAPPED_BACKEND[] = backend
    return true
end

# ── installing ──────────────────────────────────────────────────────────────

# Only wrap prompts that can be evaluated with no arguments; Pkg's cannot, so it
# keeps its own prompt (and gets no red circle).
function wrap_prompt!(mode::LineEdit.Prompt)
    mode.prompt isa RecordingPrompt && return
    try
        prompt_text(mode.prompt)
    catch
        return
    end
    mode.prompt = RecordingPrompt(mode.prompt)
    return
end

function wrap_on_done!(mode::LineEdit.Prompt, is_julia_mode::Bool)
    mode.on_done isa RecordingHook && return
    label = is_julia_mode ? "" : plain_prompt(mode, "pkg>")
    mode.on_done = RecordingHook(mode.on_done, label)
    return
end

"""
    _install_hooks() -> Bool

Wrap every REPL mode not wrapped yet. Idempotent. Returns `false` if the REPL
interface does not exist yet.
"""
function _install_hooks()
    repl = active_line_edit_repl()
    repl === nothing && return false
    install_outcome_tap!()
    for (i, mode) in enumerate(repl.interface.modes)
        mode isa LineEdit.Prompt || continue
        wrap_prompt!(mode)
        wrap_on_done!(mode, i == 1)
    end
    return true
end

# ── background tasks ────────────────────────────────────────────────────────

# The Pkg mode is created lazily on the first `]`, so while the diary is on we
# keep re-running the (cheap, idempotent) installer to catch modes that appear late.
const WATCHER = Ref{Union{Task,Nothing}}(nothing)

function ensure_watcher_running()
    task = WATCHER[]
    (task === nothing || istaskdone(task)) || return
    WATCHER[] = errormonitor(@async begin
        while STATE.enabled
            try
                _install_hooks()
            catch err
                @debug "REPLDiary hook install failed" exception = err
            end
            sleep(0.2)
        end
    end)
    return
end

"Install as soon as the REPL interface exists (for `using REPLDiary` in startup.jl)."
function _install_hooks_when_ready()
    errormonitor(@async begin
        for _ in 1:200      # give up after ~10 s
            _install_hooks() && break
            sleep(0.05)
        end
    end)
    return
end
