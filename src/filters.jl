# What is allowed into the diary: which modes, which commands, and secret masking.
# Pure functions of their arguments (plus the options held in STATE).

const ALL_MODES = (:julia, :shell, :help, :pkg)

"The REPL mode a recorded label belongs to (labels are described in format.jl)."
function label_mode(label::AbstractString)
    isempty(label) && return :julia
    startswith(label, "shell") && return :shell
    startswith(label, "help") && return :help
    return :pkg
end

"Accept a `Regex`, a `String` (matched literally) or a collection of them."
as_regexes(x::Regex) = [x]
as_regexes(x::AbstractString) = [Regex(replace(x, r"[\\^$.|?*+()\[\]{}]" => s"\\\0"))]
as_regexes(xs) = Regex[only(as_regexes(x)) for x in xs]

"Accept one mode or a collection of modes; each must be one of `$ALL_MODES`."
as_modes(m::Symbol) = as_modes((m,))
function as_modes(ms)
    ms = Symbol[Symbol(m) for m in ms]
    bad = filter(m -> m ∉ ALL_MODES, ms)
    isempty(bad) || throw(ArgumentError("unknown mode(s) $(join(repr.(bad), ", ")); choose from $(join(repr.(ALL_MODES), ", "))"))
    return unique(ms)
end

"""
    should_record(mode::Symbol, text) -> Bool

`false` if `mode` is not among the selected modes (when any were selected) or
`text` matches one of the `exclude` patterns.
"""
function should_record(mode::Symbol, text::AbstractString)
    isempty(STATE.modes) || mode in STATE.modes || return false
    return !any(re -> occursin(re, text), STATE.exclude)
end

# Secret shapes that are recognisable on their own.
const SECRET_PATTERNS = [
    r"\bgh[pousr]_[A-Za-z0-9]{20,}",                   # GitHub tokens
    r"\bgithub_pat_[A-Za-z0-9_]{20,}",                 # GitHub fine-grained tokens
    r"\bsk-[A-Za-z0-9_-]{16,}",                        # OpenAI/Anthropic-style API keys
    r"\bAKIA[0-9A-Z]{16}\b",                           # AWS access key ids
    r"\bxox[abprs]-[A-Za-z0-9-]{10,}",                 # Slack tokens
    r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}",   # JWTs
    r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{16,}",
]

# `password = "hunter2"`, `api_key="…"`, `token: '…'`: keep the name, mask the value.
const SECRET_ASSIGNMENT =
    r"""(?i)\b(pass(?:word|wd)?|secret|token|api[_-]?key|auth)(\w*\s*[=:]\s*)(["'])(?:(?!\3).)*\3"""

const REDACTED = "<redacted>"
const SECRET_ASSIGNMENT_MASK = SubstitutionString("\\1\\2\\3$(REDACTED)\\3")   # keep name, separator, quote style

"Mask recognisable secrets in `text`."
function redact_secrets(text::AbstractString)
    text = replace(text, SECRET_ASSIGNMENT => SECRET_ASSIGNMENT_MASK)
    for pattern in SECRET_PATTERNS
        text = replace(text, pattern => REDACTED)
    end
    return text
end

"The text to write for `text`: redacted if the option is on."
prepare_text(text::AbstractString) = STATE.redact ? redact_secrets(text) : String(text)
