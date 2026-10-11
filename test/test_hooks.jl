# The wrappers that plug into the REPL, exercised on stand-in `LineEdit.Prompt`s.
using REPL.LineEdit

make_prompt(prompt; on_done=(s, buf, ok) -> nothing) = LineEdit.Prompt(prompt; on_done)

@testset "hooks" begin
    @testset "no REPL: nothing to install" begin
        @test D.active_line_edit_repl() === nothing
        @test D._install_hooks() === false
    end

    @testset "RecordingHook records only after the backend reports success" begin
        with_diary_dir() do _
            diary("h")
            calls = Symbol[]
            # Stands in for the REPL: it "evaluates" the line and the backend tap reports back.
            evaluate(outcome) = (s, buf, ok) -> (push!(calls, :original); outcome === nothing || D.resolve_pending!(outcome))

            mode = make_prompt("julia> "; on_done=evaluate(D.Outcome(true)))
            D.wrap_on_done!(mode, true)
            @test mode.on_done isa D.RecordingHook
            mode.on_done(nothing, IOBuffer("x = 1"), true)
            @test calls == [:original]

            mode.on_done = D.RecordingHook(evaluate(D.Outcome(false, nothing, "no")), "")
            mode.on_done(nothing, IOBuffer("fails()"), true)             # backend says: error

            mode.on_done = D.RecordingHook(evaluate(nothing), "")
            mode.on_done(nothing, IOBuffer("1 +* 2"), true)              # never reached the backend

            mode.on_done = D.RecordingHook(evaluate(D.Outcome(true)), "")
            mode.on_done(nothing, IOBuffer("y = 2"), false)              # ok=false (aborted line): not tracked
            @test D.PENDING[] === nothing

            diary(:off)
            txt = read_file("h.jl")
            @test occursin("x = 1", txt) && !occursin("fails", txt) && !occursin("+*", txt) && !occursin("y = 2", txt)
        end
    end

    @testset "the buffer is left intact for the REPL" begin
        with_diary_dir() do _
            seen = Ref("")
            mode = make_prompt("julia> "; on_done=(s, buf, ok) -> seen[] = String(take!(buf)))
            D.wrap_on_done!(mode, true)
            mode.on_done(nothing, IOBuffer("keep_me = 1"), true)
            @test seen[] == "keep_me = 1"
        end
    end

    @testset "the original's result and errors pass through" begin
        with_diary_dir() do _
            mode = make_prompt("julia> "; on_done=(s, buf, ok) -> :returned)
            D.wrap_on_done!(mode, true)
            @test mode.on_done(nothing, IOBuffer("x"), true) == :returned

            mode = make_prompt("julia> "; on_done=(s, buf, ok) -> error("repl failure"))
            D.wrap_on_done!(mode, true)
            @test_throws ErrorException("repl failure") mode.on_done(nothing, IOBuffer("x"), true)
            @test D.PENDING[] === nothing                                # cleaned up even so
        end
    end

    @testset "tracking trouble never breaks the REPL" begin
        with_diary_dir() do _
            diary("h")
            rm("h.jl"); mkdir("h.jl")                                    # make every write fail
            ran = Ref(false)
            # Pkg-mode lines are written when the REPL finishes with them; that write fails here.
            mode = make_prompt("pkg> "; on_done=(s, buf, ok) -> ran[] = true)
            D.wrap_on_done!(mode, false)
            @test_logs (:warn, r"could not record") match_mode=:any mode.on_done(nothing, IOBuffer("add A"), true)
            @test ran[]                                                  # the REPL still ran the command
        end
    end

    @testset "labels per mode" begin
        with_diary_dir() do _
            shell = make_prompt("shell> ")
            D.wrap_on_done!(shell, false)
            @test shell.on_done.label == "shell>"
            julia = make_prompt("julia> ")
            D.wrap_on_done!(julia, true)
            @test julia.on_done.label == ""
            pkg = make_prompt(() -> error("needs arguments"))
            D.wrap_on_done!(pkg, false)
            @test pkg.on_done.label == "pkg>"                            # unevaluable prompt: fallback
            wrapped = make_prompt("help?> ")
            D.wrap_prompt!(wrapped); D.wrap_on_done!(wrapped, false)
            @test wrapped.on_done.label == "help?>"                      # decoration is not part of the label
        end
    end

    @testset "wrapping is idempotent" begin
        mode = make_prompt("julia> ")
        D.wrap_on_done!(mode, true); first_hook = mode.on_done
        D.wrap_on_done!(mode, true)
        @test mode.on_done === first_hook
        D.wrap_prompt!(mode); first_prompt = mode.prompt
        D.wrap_prompt!(mode)
        @test mode.prompt === first_prompt
    end

    @testset "red-circle prompt" begin
        with_diary_dir() do _
            string_mode = make_prompt("shell> ")
            fun_mode = make_prompt(() -> "(Main) julia> ")
            for mode in (string_mode, fun_mode)
                D.wrap_prompt!(mode)
                @test mode.prompt isa D.RecordingPrompt
            end
            @test string_mode.prompt() == "shell> " && fun_mode.prompt() == "(Main) julia> "
            diary("p")
            @test string_mode.prompt() == "🔴 shell> " && fun_mode.prompt() == "🔴 (Main) julia> "
            diary(:off)
            @test string_mode.prompt() == "shell> "

            unevaluable = make_prompt(() -> error("needs arguments"))    # like Pkg's prompt
            D.wrap_prompt!(unevaluable)
            @test !(unevaluable.prompt isa D.RecordingPrompt)
        end
    end

    @testset "plain_prompt" begin
        @test D.plain_prompt(make_prompt("shell> "), "x") == "shell>"
        @test D.plain_prompt(make_prompt(() -> "(env) pkg> "), "x") == "(env) pkg>"
        @test D.plain_prompt(make_prompt(() -> error("no")), "fallback>") == "fallback>"
        wrapped = make_prompt("help?> "); D.wrap_prompt!(wrapped)
        @test D.plain_prompt(wrapped, "x") == "help?>"
    end
end
