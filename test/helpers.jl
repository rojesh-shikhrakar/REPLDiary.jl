# Shared test helpers. REPLDiary keeps global state, so every test that touches it
# runs through `with_diary_dir`, which starts and ends from a clean slate.

const D = REPLDiary   # short alias for internals

"Put every option, counter and pending command back to its default, without any file I/O."
function reset_diary_state!()
    s = D.STATE
    s.enabled = false
    s.file = ""
    s.timestamps = false
    s.output = false
    s.errors = :skip
    s.commands = 0
    s.skipped = 0
    s.exclude = Regex[]
    s.modes = Symbol[]
    s.redact = false
    empty!(D.UNDO_STACK)
    empty!(D.OUTCOMES)
    D.PENDING[] = nothing
    return
end

"""
    with_diary_dir(f)

Run `f(dir)` in a fresh temporary directory with default diary state, and restore
the default state afterwards even if `f` throws.
"""
function with_diary_dir(f)
    reset_diary_state!()
    return mktempdir() do dir
        cd(dir) do
            try
                f(dir)
            finally
                reset_diary_state!()
            end
        end
    end
end

read_file(name) = read(name, String)

"Does `text` parse as Julia without syntax errors? (`Meta.parseall` itself never throws.)"
function parses_cleanly(text::AbstractString)
    top = Meta.parseall(text)
    return !any(a -> a isa Expr && a.head in (:error, :incomplete), top.args)
end

"Record `commands` (plain Julia text) as successful commands."
record_all(commands...) = foreach(c -> D.record("", c), commands)
