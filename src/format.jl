# Pure functions: how a command looks in the diary file. No I/O here.

# Calls that control the diary are not themselves recorded.
const DIARY_CALL = r"^\s*(REPLDiary\.)?diary\s*\("

# REPL history mode => label. Julia code has no label and is written verbatim;
# everything else becomes `# label line` comments to keep the file valid Julia.
const MODE_LABELS = Dict(:julia => "", :shell => "shell>", :help => "help?>", :pkg => "pkg>")

mode_label(mode::Symbol) = get(MODE_LABELS, mode, string(mode, ">"))

is_diary_call(label::AbstractString, text::AbstractString) =
    isempty(label) && occursin(DIARY_CALL, text)

"""
    format_entry(label, text; timestamp=false) -> String

One command as diary-file text, ending in a newline. Returns `""` for blank input.
"""
function format_entry(label::AbstractString, text::AbstractString; timestamp::Bool=false)
    text = strip(text)
    isempty(text) && return ""
    io = IOBuffer()
    timestamp && println(io, "# ", now_string("HH:MM:SS"))
    if isempty(label)
        println(io, text)
    else
        for line in split(text, '\n')
            println(io, "# ", label, " ", line)
        end
    end
    return String(take!(io))
end

# ── results and errors as comments ──────────────────────────────────────────

"Prefix every line of `text` with `# `, ending in a newline."
comment_lines(text::AbstractString) =
    join(("# " * line * "\n" for line in split(rstrip(text), '\n')))

# `x = 1;` hides its value in the REPL; do the same.
function hides_output(text::AbstractString)
    try
        return REPL.ends_with_semicolon(text)
    catch
        return endswith(rstrip(text), ';')
    end
end

"""
    format_result(text, value) -> String

The value the REPL would display after the command `text`, as comment lines, or
`""` when nothing is displayed (`nothing`, or a command ending in `;`). The value's
`show` method is user code: it runs in the latest world and may not break recording.
"""
function format_result(text::AbstractString, value)
    (value === nothing || hides_output(text)) && return ""
    try
        io = IOBuffer()
        context = IOContext(io, :limit => true, :displaysize => (24, 80))
        Base.invokelatest(show, context, MIME"text/plain"(), value)
        shown = String(take!(io))
        return isempty(strip(shown)) ? "" : comment_lines(shown)
    catch
        return ""
    end
end

"The error as a comment line, e.g. `# ERROR: UndefVarError: ...`."
format_error(message::AbstractString) = comment_lines("ERROR: " * message)
