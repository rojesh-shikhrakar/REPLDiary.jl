# Reading the REPL's own command history.

"Number of entries in the REPL history (0 if there is no REPL)."
function history_length()
    repl = active_line_edit_repl()
    return repl === nothing ? 0 : length(repl.interface.modes[1].hist.history)
end

"""
    repl_history() -> Vector{Tuple{Symbol,String}}

The REPL history as `(mode, text)` pairs, oldest first. Throws if there is no
interactive REPL.
"""
function repl_history()
    repl = active_line_edit_repl()
    repl === nothing && error("diary(n) needs an interactive REPL")
    history = repl.interface.modes[1].hist.history  # modes[1] is the Julia prompt
    isempty(history) && return Tuple{Symbol,String}[]
    if first(history) isa AbstractString
        # Julia < 1.13: parallel vectors of texts and modes.
        modes = repl.interface.modes[1].hist.modes
        return [(m, String(t)) for (m, t) in zip(modes, history)]
    end
    # Julia >= 1.13: a vector of `HistEntry`.
    return [(e.mode, String(e.content)) for e in history]
end
