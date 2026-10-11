# REPLDiary.jl

A MATLAB-style `diary` for the Julia REPL: every command you type is appended to a
Julia file while the diary is on.

```julia
using REPLDiary

diary("session.jl")   # set the file and start recording   (MATLAB: diary filename)
diary(:off)           # stop                                (MATLAB: diary off)
diary(:on)            # resume (appends to the same file)   (MATLAB: diary on)
diary()               # toggle                              (MATLAB: diary)
isdiary()             # recording?                          (MATLAB: get(0,'Diary'))
diaryfile()           # absolute path of the diary file     (MATLAB: get(0,'DiaryFile'))
diary(5)              # write the last 5 commands (excluding diary calls) to the file
diary("s.jl", 5)      # start recording to s.jl, beginning with the last 5 commands
diary("s.jl"; timestamps=true)   # add a `# HH:MM:SS` comment before each command
```

- The default file is `diary.jl` in the current directory; a name without an extension gets `.jl`.
- Existing files are appended to, never overwritten.
- Julia input is written verbatim (multi-line input included); shell (`;`), help (`?`)
  and Pkg (`]`) input is written as comments (`# shell> ls`), so the file is a valid script.
- While recording, the prompt shows a red circle (`🔴 julia>`); it disappears when the diary is off.
- Commands that fail (an error, an interrupt, a syntax error) are not recorded, and `diary(n)` skips them too.
  Exceptions: Pkg-mode (`]`) commands are always recorded because Pkg handles its own errors, and a
  shell command that merely exits non-zero is not a Julia error. `diary(n)` can only know about
  failures from the current session.
- Calls to `diary(...)` themselves are not recorded.
- Unlike MATLAB, command *output* is not captured — only the commands.

To always have it available, add `using REPLDiary` to `~/.julia/config/startup.jl`.

Install from a local checkout: `] dev /path/to/REPLDiary.jl`.
