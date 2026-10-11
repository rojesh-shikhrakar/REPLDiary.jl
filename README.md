# REPLDiary.jl

[![CI](https://github.com/rojesh-shikhrakar/REPLDiary.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/rojesh-shikhrakar/REPLDiary.jl/actions/workflows/CI.yml)

A MATLAB-style `diary` for the Julia REPL. While the diary is on, the commands you
type are appended to a plain Julia file, so a REPL session becomes a script you can
read, edit, replay or share.

```julia
julia> using REPLDiary

julia> diary("session.jl")        # start recording

🔴 julia> x = 1 + 2
3

🔴 julia> diary(:off)             # stop
```

`session.jl` now contains:

```julia
# ── diary started 2026-10-11 20:15:03 ──
x = 1 + 2
# ── diary stopped 2026-10-11 20:15:09 ──
```

## Installation

```julia
pkg> add REPLDiary
```

Requires Julia 1.7 or newer. To have it in every session, add `using REPLDiary`
to `~/.julia/config/startup.jl`.

## Quick reference

| You type | What happens | MATLAB equivalent |
|:--|:--|:--|
| `diary("file.jl")` | set the file and start recording | `diary filename` |
| `diary(:on)` / `diary(:off)` | start / stop recording | `diary on` / `diary off` |
| `diary()` | toggle recording | `diary` |
| `isdiary()` | is it recording? | `get(0,'Diary')` |
| `diaryfile()` | absolute path of the diary file | `get(0,'DiaryFile')` |
| `diary(:status)` | show state, file, counts and options | |
| `diary(n)` | write the last `n` commands to the file | |
| `diary("file.jl", n)` | start recording, beginning with the last `n` commands | |
| `diary(:undo)` / `diary(:undo, k)` | remove the last entry / last `k` entries | |

Basics:

- The default file is `diary.jl` in the current directory. A name without an
  extension gets `.jl`.
- Existing files are appended to, never overwritten.
- While recording, the prompt shows a red circle: `🔴 julia>`.
- Calls to `diary(...)` are never recorded.

## What gets written

- **Julia input** is written as typed, multi-line input included.
- **Shell (`;`), help (`?`) and Pkg (`]`) input** is written as comments
  (`# shell> ls`) so the file stays a valid Julia script.
- **Failed commands are left out** (an error, an interrupt, a syntax error), so the
  diary holds only what worked. `diary(n)` skips them too.

## Options

Options are keyword arguments to any `diary(...)` call. They stay in effect until you
change them, for example `diary(:on; output=false)`.

### `output=true`: record results

```julia
diary("s.jl"; output=true)
```

```julia
a = 1 + 2
# 3
v = [1, 2, 3]
# 3-element Vector{Int64}:
#  1
#  2
#  3
```

Commands ending in `;` get no result line. Text printed with `println`, `@show`
or `@warn` is not captured, only the value the REPL displays.

### `errors=:comment`: keep failed commands

```julia
diary("s.jl"; errors=:comment)
```

```julia
# failed> undefined_thing + 1
# ERROR: UndefVarError: `undefined_thing` not defined in `Main`
```

The default, `errors=:skip`, leaves failed commands out.

### `timestamps=true`

Writes a `# HH:MM:SS` comment before each command.

### Controlling what is recorded

| Option | Effect |
|:--|:--|
| `exclude=[r"^using ", "hunter2"]` | never record commands that match (a `Regex`, or a `String` matched literally). `exclude=[]` clears it. |
| `modes=[:julia, :pkg]` | record only these REPL modes: `:julia`, `:shell`, `:help`, `:pkg`. `modes=[]` records all again. |
| `redact=true` | mask likely secrets as `<redacted>`: GitHub, AWS, Slack and API-key tokens, JWTs, `Bearer …`, and the value in assignments such as `password = "…"` or `github_token = "…"` (the variable name is kept). |

`redact` is pattern matching, not a guarantee. A redacted line no longer replays
as written, which is why it is off by default. Use `exclude` for anything truly
sensitive. All three also apply to `diary(n)` and, with `output=true`, to recorded
results and error text.

```julia
diary("s.jl"; exclude=[r"password"], modes=[:julia], redact=true)
```

## Recording earlier commands: `diary(n)`

Forgot to start the diary? `diary(5)` writes the last 5 commands from the REPL
history to the diary file, without turning recording on. `diary("s.jl", 5)` starts
recording and puts those 5 commands first.

It reads the REPL history, so it can include commands from earlier Julia sessions.
It knows about failures only from the current session.

## Undo: `diary(:undo)`

Pasted something you did not mean to keep? `diary(:undo)` removes the last entry
from the file, and `diary(:undo, 3)` removes the last three. A block written by
`diary(n)` counts as one entry. Only entries written in the current session can be
undone, up to 1000 back. If the file was edited by hand in the meantime, undo
warns and leaves it alone rather than cut the wrong bytes.

## `diary(:status)`

```
Diary is ON
  file:     /home/me/project/s.jl
  commands: 6 recorded, 2 failed and skipped (this session)
  options:  timestamps=false output=true errors=:skip
  filters:  modes=all exclude=r"^using " redact=true
```

`REPLDiary.diary_status()` returns the same information as a `NamedTuple`.

## Limitations

- **Pkg mode:** commands are always recorded, because Pkg handles its own errors and
  the outcome cannot be seen. The Pkg prompt does not show the red circle.
- **Shell mode:** a shell command that exits non-zero is not a Julia error, so it
  is recorded.
- **Output capture** records the displayed value only, not text written to `stdout`.
- **Interactive REPL only:** IJulia/Jupyter and the VS Code REPL run commands in
  other ways and are not hooked. `diary(n)` needs the REPL history.
- **Prompt packages** that replace the REPL prompt (OhMyREPL, for example) may hide
  the red circle. Recording still works.

## How it works

The REPL calls each mode's `on_done` callback with the submitted text. REPLDiary
wraps those callbacks so each line is noted first and then handed to the original
callback, leaving REPL behaviour untouched. A line is written to the file only once
the REPL backend reports that it succeeded, which is how failed commands are
dropped. Per-command overhead is a few microseconds, and idle cost is negligible.

The source is organised by concern (`src/state.jl`, `format.jl`, `filters.jl`,
`recorder.jl`, `outcomes.jl`, `history.jl`, `hooks.jl`, `api.jl`); the module
docstring in `src/REPLDiary.jl` explains how they fit together.

## Development

```julia
julia --project -e 'using Pkg; Pkg.test()'
```

The tests run without an interactive REPL, so the REPL hooks themselves (prompt,
Pkg mode, result capture) should also be checked by hand in a real session.

## License

MIT. See [LICENSE](LICENSE).
