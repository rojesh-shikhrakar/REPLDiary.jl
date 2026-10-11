# Writing to the diary: session start/stop, live commands, and past commands.

"""
    start_recording!()

Write the session header and turn recording on. The header is written first so a
failing file write leaves the diary off rather than silently half-on.
"""
function start_recording!()
    @lock LOCK begin
        STATE.enabled && return
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
    record(label, text)

Append one command typed at the REPL. `label` is `""` for the Julia prompt, or the
mode prompt (`"shell>"`, …). Does nothing while the diary is off.
"""
function record(label::AbstractString, text::AbstractString)
    STATE.enabled || return
    is_diary_call(label, text) && return
    entry = format_entry(label, text; timestamp=STATE.timestamps)
    isempty(entry) && return
    @lock LOCK STATE.enabled && append_to_file(entry)
    return
end

"""
    write_last(n, entries=repl_history())

Append the last `n` of `entries` (`(mode, text)` pairs, oldest first) to the diary
file, ignoring `diary(...)` calls and commands known to have failed. Works whether or not recording is on.
"""
function write_last(n::Integer, entries=repl_history())
    n > 0 || return
    commands = [(m, t) for (i, (m, t)) in enumerate(entries)
                if !is_diary_call(mode_label(m), t) && succeeded_or_unknown(i, t)]
    commands = commands[max(1, length(commands) - n + 1):end]
    body = join(format_entry(mode_label(m), t) for (m, t) in commands)  # blanks give ""
    isempty(body) && return
    count = length(commands)
    header = "# ── last $count command$(count == 1 ? "" : "s") ──\n"
    @lock LOCK append_to_file(header * body)
    return
end
