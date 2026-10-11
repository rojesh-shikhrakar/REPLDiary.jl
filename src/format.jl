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
