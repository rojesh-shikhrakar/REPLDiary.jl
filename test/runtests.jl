using Test
using REPLDiary

@testset "REPLDiary" begin
    mktempdir() do dir
        cd(dir) do
            @test !isdiary()
            @test diaryfile() == abspath("diary.jl")

            diary("session")
            @test isdiary()
            @test endswith(diaryfile(), "session.jl")

            REPLDiary.record("", "x = 1 + 1\n")
            REPLDiary.record("", "diary(:off)")            # control call: skipped
            REPLDiary.record("shell>", "ls -la")
            REPLDiary.record("", "   ")                    # blank: skipped
            diary(:off)
            @test !isdiary()
            REPLDiary.record("", "ignored = 1")            # off: skipped

            diary(timestamps=false)                        # toggle on again, appends
            REPLDiary.record("", "f(x) = begin\n    x\nend")
            diary()
            @test !isdiary()

            txt = read("session.jl", String)
            @test occursin("x = 1 + 1\n", txt)
            @test occursin("# shell> ls -la\n", txt)
            @test !occursin("ignored", txt)
            @test !occursin("diary(:off)\n", replace(txt, r"# .*\n" => ""))
            @test occursin("f(x) = begin\n    x\nend\n", txt)
            @test count("diary started", txt) == 2
            @test count("diary stopped", txt) == 2
            # the diary file is valid Julia
            @test Meta.parseall(txt) isa Expr

            diary(:on)
            REPLDiary.record("", "1")
            diary("off")
            @test isfile("session.jl")
        end
    end

    @testset "diary(n)" begin
        mktempdir() do dir
            cd(dir) do
                hist = [(:julia, "a = 1"), (:julia, "diary(\"x.jl\")"), (:shell, "ls"),
                        (:julia, "b = 2\nc = 3"), (:julia, "diary(2)")]
                REPLDiary.STATE.file = joinpath(dir, "n.jl")
                REPLDiary.write_last(2, hist)
                txt = read("n.jl", String)
                @test txt == "# ── last 2 commands ──\n# shell> ls\nb = 2\nc = 3\n"
                @test Meta.parseall(txt) isa Expr
                rm("n.jl")
                REPLDiary.write_last(10, hist)       # n larger than history
                @test count('\n', read("n.jl", String)) == 5
                rm("n.jl")
                REPLDiary.write_last(0, hist)
                @test !isfile("n.jl")
                @test_throws ArgumentError diary(-1)
            end
        end
    end

    @testset "format_entry" begin
        @test REPLDiary.format_entry("", "  x = 1 \n") == "x = 1\n"
        @test REPLDiary.format_entry("pkg>", "add A\nup") == "# pkg> add A\n# pkg> up\n"
        @test REPLDiary.format_entry("", "   ") == ""
        @test occursin(r"^# \d\d:\d\d:\d\d\nx\n$", REPLDiary.format_entry("", "x"; timestamp=true))
    end

    @testset "switching file while recording closes the old session" begin
        mktempdir() do dir
            cd(dir) do
                diary("a")
                REPLDiary.record("", "in_a = 1")
                diary("b")
                REPLDiary.record("", "in_b = 2")
                diary(:off)
                a, b = read("a.jl", String), read("b.jl", String)
                @test occursin("in_a", a) && !occursin("in_b", a)
                @test occursin("diary stopped", a)
                @test occursin("in_b", b) && !occursin("in_a", b)
            end
        end
    end

    @testset "write failure leaves the diary off" begin
        mktempdir() do dir
            cd(dir) do
                mkdir("blocked.jl")                      # a directory, so opening it fails
                @test_throws Exception diary("blocked.jl")
                @test !isdiary()
            end
        end
    end

    @testset "failed commands are not recorded" begin
        mktempdir() do dir
            cd(dir) do
                diary("f")
                REPLDiary.submit!("", "ok1 = 1");        REPLDiary.resolve_pending!(true)
                REPLDiary.submit!("", "boom()");         REPLDiary.resolve_pending!(false)
                REPLDiary.submit!("", "1 +* 2");         REPLDiary.finish_submission!()  # never ran
                REPLDiary.submit!("pkg>", "add Foo");    REPLDiary.finish_submission!()  # Pkg: always kept
                REPLDiary.submit!("", "ok2 = 2");        REPLDiary.resolve_pending!(true)
                REPLDiary.finish_submission!()                                           # nothing pending: no-op
                diary(:off)
                txt = read("f.jl", String)
                @test occursin("ok1 = 1", txt) && occursin("ok2 = 2", txt)
                @test occursin("# pkg> add Foo", txt)
                @test !occursin("boom", txt) && !occursin("+*", txt)
            end
        end
    end

    @testset "diary(n) skips commands known to have failed" begin
        mktempdir() do dir
            cd(dir) do
                REPLDiary.STATE.file = joinpath(dir, "w.jl")
                empty!(REPLDiary.OUTCOMES)
                hist = [(:julia, "a = 1"), (:julia, "bad()"), (:julia, "b = 2")]
                REPLDiary.OUTCOMES[2] = ("bad()", false)
                REPLDiary.OUTCOMES[1] = ("something else", false)   # text mismatch: ignored
                REPLDiary.write_last(3, hist)
                @test read("w.jl", String) == "# ── last 2 commands ──\na = 1\nb = 2\n"
            end
        end
    end

    @testset "output=true records displayed results" begin
        mktempdir() do dir
            cd(dir) do
                diary("o"; output=true)
                REPLDiary.record("", "1 + 2", REPLDiary.Outcome(true, 3, nothing))
                REPLDiary.record("", "x = [1, 2]", REPLDiary.Outcome(true, [1, 2], nothing))
                REPLDiary.record("", "y = 5;", REPLDiary.Outcome(true, 5, nothing))        # hidden by `;`
                REPLDiary.record("", "nothing", REPLDiary.Outcome(true, nothing, nothing)) # no value
                REPLDiary.record("shell>", "ls", REPLDiary.Outcome(true, 7, nothing))      # only Julia mode
                diary(:off; output=false)
                txt = read("o.jl", String)
                @test occursin("1 + 2\n# 3\n", txt)
                @test occursin("x = [1, 2]\n# 2-element Vector{Int64}:\n#  1\n#  2\n", txt)
                @test occursin("y = 5;\n", txt) && !occursin("# 5", txt)
                @test occursin("# shell> ls\n", txt) && !occursin("# 7", txt)
                @test Meta.parseall(txt) isa Expr
            end
        end
    end

    @testset "errors=:comment keeps failed commands as comments" begin
        mktempdir() do dir
            cd(dir) do
                @test_throws ArgumentError diary("e"; errors=:bogus)
                diary("e"; errors=:comment)
                REPLDiary.record("", "boom()", REPLDiary.Outcome(false, nothing, "UndefVarError: `boom` not defined"))
                REPLDiary.record("", "1 +* 2", REPLDiary.Outcome(false))   # no details
                diary(:off; errors=:skip)
                txt = read("e.jl", String)
                @test occursin("# failed> boom()\n# ERROR: UndefVarError: `boom` not defined\n", txt)
                @test occursin("# failed> 1 +* 2\n# ERROR: the command could not be run\n", txt)
                @test Meta.parseall(txt) isa Expr
            end
        end
    end

    @testset "Outcome from a backend response" begin
        @test REPLDiary.Outcome(7 => false).value == 7
        stack = [(exception=ErrorException("bad"), backtrace=nothing)]
        o = REPLDiary.Outcome(stack => true)
        @test !o.succeeded && o.error == "bad"
    end

    @testset "diary(:status)" begin
        mktempdir() do dir
            cd(dir) do
                diary("s"; timestamps=false, output=false, errors=:skip)
                REPLDiary.record("", "a = 1")
                REPLDiary.record("", "bad()", REPLDiary.Outcome(false))
                st = REPLDiary.diary_status()
                @test st.recording && st.commands == 1 && st.skipped == 1
                @test endswith(st.file, "s.jl")
                out = sprint(REPLDiary.print_status)
                @test occursin("Diary is ON", out) && occursin("1 recorded, 1 failed", out)
                diary(:off)
                @test !REPLDiary.diary_status().recording
                diary(:on)                                  # a new session resets the counts
                @test REPLDiary.diary_status().commands == 0
                diary(:off)
            end
        end
    end

    @testset "diary(:undo)" begin
        mktempdir() do dir
            cd(dir) do
                diary("u")
                REPLDiary.record("", "keep = 1")
                REPLDiary.record("", "oops = 2")
                REPLDiary.record("", "oops = 3")
                diary(:undo)
                @test !occursin("oops = 3", read("u.jl", String))
                @test occursin("oops = 2", read("u.jl", String))
                diary(:undo, 5)                              # more than available: stops at the header
                txt = read("u.jl", String)
                @test occursin("diary started", txt) && !occursin("keep", txt)
                @test REPLDiary.undo!() == 0                 # nothing left
                REPLDiary.record("", "again = 4")
                write("u.jl", read("u.jl", String) * "# edited elsewhere\n")
                @test_logs (:warn, r"cannot undo") diary(:undo)   # file changed: refuse
                @test occursin("again = 4", read("u.jl", String))
                diary(:off)
                @test_throws ArgumentError diary(:undo, -1)
            end
        end
    end

    @testset "filters: exclude, modes, redact" begin
        @test REPLDiary.as_regexes("a.b(c)") == [r"a\.b\(c\)"] || occursin(REPLDiary.as_regexes("a.b(c)")[1], "a.b(c)")
        @test !occursin(REPLDiary.as_regexes("a.b")[1], "axb")           # String is literal
        @test_throws ArgumentError diary(modes=[:nope])
        @test REPLDiary.STATE.modes == Symbol[]                          # bad option changed nothing

        mktempdir() do dir
            cd(dir) do
                diary("flt"; exclude=[r"^using ", "hunter2"], modes=[:julia, :pkg], redact=true)
                REPLDiary.record("", "using Foo")                        # excluded by pattern
                REPLDiary.record("", "x = 1")
                REPLDiary.record("", "login(\"bob\", \"hunter2\")")      # excluded by literal
                REPLDiary.record("shell>", "ls")                         # mode not selected
                REPLDiary.record("pkg>", "add A")
                REPLDiary.record("", "api_key = \"abc123\"")             # redacted
                REPLDiary.record("", "t = \"ghp_" * "a"^30 * "\"")        # redacted
                diary(:off)
                txt = read("flt.jl", String)
                @test occursin("x = 1\n", txt) && occursin("# pkg> add A", txt)
                @test !occursin("using Foo", txt) && !occursin("hunter2", txt) && !occursin("shell>", txt)
                @test occursin("api_key = \"<redacted>\"", txt) && !occursin("abc123", txt)
                @test occursin("t = \"<redacted>\"", txt)

                # diary(n) honours the same filters
                REPLDiary.STATE.file = joinpath(dir, "n2.jl")
                empty!(REPLDiary.OUTCOMES)
                REPLDiary.write_last(5, [(:julia, "using Foo"), (:shell, "ls"), (:julia, "y = 2"),
                                         (:julia, "password = 'p'")])
                @test read("n2.jl", String) == "# ── last 2 commands ──\ny = 2\npassword = '<redacted>'\n"

                diary(exclude=[], modes=[], redact=false)                # reset
                @test isempty(REPLDiary.STATE.exclude) && isempty(REPLDiary.STATE.modes) && !REPLDiary.STATE.redact
            end
        end
    end
end
