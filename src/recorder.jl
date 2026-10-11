# Writing to the diary: session start/stop, live commands, and past commands.

"""
    start_recording!()

Write the session header and turn recording on. The header is written first so a
failing file write leaves the diary off rather than silently half-on.
"""
function start_recording!()
    @lock LOCK begin
        STATE.enabled && return
        STATE.commands = 0
        STATE.skipped = 0
        append_to_file("# ── diary started $(now_string("yyyy-mm-dd HH:MM:SS")) ──\n")
        STATE.enabled = true
    end
    return
end

"Turn recording off (even if writing the footer fails) and write the session footer."
function stop_recording!()
    @lock LOCK begin
        STATE.enabled || return
        STATE.enabled = false
        append_to_file("# ── diary stopped $(now_string("yyyy-mm-dd HH:MM:SS")) ──\n\n")
    end
    return
end

"""
    record(label, text, outcome=Outcome(true))

Write one command typed at the REPL, according to its `outcome` and the options:

- succeeded: the command, plus its displayed result if `output` is on (Julia mode only);
- failed, `errors == :comment`: the command and the error, both as comments;
- failed, `errors == :skip`: nothing (it is only counted).

`label` is `""` for the Julia prompt, or the mode prompt (`"shell>"`, …).
Does nothing while the diary is off.
"""
function record(label::AbstractString, text::AbstractString, outcome::Outcome=Outcome(true))
    STATE.enabled || return
    is_diary_call(label, text) && return
    should_record(label_mode(label), text) || return   # filtered out: not counted either
    text = prepare_text(text)                          # masks secrets if `redact` is on
    timestamp = STATE.timestamps
    if outcome.succeeded
        entry = format_entry(label, text; timestamp)
        isempty(entry) && return
        STATE.output && isempty(label) && (entry *= prepare_text(format_result(text, outcome.value)))
    elseif STATE.errors === :comment
        entry = format_entry(isempty(label) ? "failed>" : label, text; timestamp)
        isempty(entry) && return
        entry *= prepare_text(format_error(something(outcome.error, "the command could not be run")))
    else
        STATE.skipped += 1
        return
    end
    @lock LOCK if STATE.enabled
        append_to_file(entry; undoable=true, commands=outcome.succeeded ? 1 : 0)
        outcome.succeeded && (STATE.commands += 1)
    end
    return
end

"""
    write_last(n, entries=nothing)

Append the last `n` of `entries` (`(mode, text)` pairs, oldest first) to the diary
file (default: the REPL history, read only when `n > 0`), ignoring `diary(...)` calls, commands known to have failed, and anything the
`modes`/`exclude` options filter out. Works whether or not recording is on.
"""
function write_last(n::Integer, entries=nothing)
    n > 0 || return
    entries === nothing && (entries = repl_history())
    commands = [(m, t) for (i, (m, t)) in enumerate(entries)
                if !is_diary_call(mode_label(m), t) && succeeded_or_unknown(i, t) && should_record(m, t)]
    commands = commands[max(1, length(commands) - n + 1):end]
    body = join(format_entry(mode_label(m), prepare_text(t)) for (m, t) in commands)  # blanks give ""
    isempty(body) && return
    count = length(commands)
    header = "# ── last $count command$(count == 1 ? "" : "s") ──\n"
    @lock LOCK append_to_file(header * body; undoable=true)
    return
end
