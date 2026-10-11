@testset "recording" begin
    @testset "basic session" begin
        with_diary_dir() do _
            @test !isdiary()
            @test diaryfile() == abspath("diary.jl")        # default: current directory

            diary("session")
            @test isdiary()
            @test endswith(diaryfile(), "session.jl")

            D.record("", "x = 1 + 1\n")
            D.record("", "diary(:off)")                     # control call: skipped
            D.record("shell>", "ls -la")
            D.record("", "   ")                             # blank: skipped
            D.record("", "f(x) = begin\n    x\nend")
            diary(:off)
            D.record("", "ignored = 1")                      # off: skipped

            txt = read_file("session.jl")
            @test occursin("x = 1 + 1\n", txt)
            @test occursin("# shell> ls -la\n", txt)
            @test occursin("f(x) = begin\n    x\nend\n", txt)
            @test !occursin("ignored", txt)
            @test !occursin("diary(:off)", txt)
            @test count("diary started", txt) == 1 && count("diary stopped", txt) == 1
            @test parses_cleanly(txt)
            @test occursin(r"^# ── diary started \d{4}-\d\d-\d\d \d\d:\d\d:\d\d ──\n", txt)
        end
    end

    @testset "later sessions append, never overwrite" begin
        with_diary_dir() do _
            write("a.jl", "# existing\n")
            diary("a"); record_all("one = 1"); diary(:off)
            diary("a"); record_all("two = 2"); diary(:off)
            txt = read_file("a.jl")
            @test startswith(txt, "# existing\n")
            @test occursin("one = 1", txt) && occursin("two = 2", txt)
            @test count("diary started", txt) == 2 && count("diary stopped", txt) == 2
            @test parses_cleanly(txt)
        end
    end

    @testset "counts" begin
        with_diary_dir() do _
            diary("c")
            record_all("a = 1", "b = 2")
            D.record("", "bad()", D.Outcome(false))
            @test D.STATE.commands == 2 && D.STATE.skipped == 1
            D.record("", "   ")                           # blanks and diary calls are not counted
            D.record("", "diary()")
            @test D.STATE.commands == 2 && D.STATE.skipped == 1
            diary(:off)
        end
    end

    @testset "timestamps" begin
        with_diary_dir() do _
            diary("t"; timestamps=true)
            record_all("x = 1")
            diary(:off)
            @test occursin(r"# \d\d:\d\d:\d\d\nx = 1\n", read_file("t.jl"))
        end
    end

    @testset "multi-line input and non-Julia modes stay valid Julia" begin
        with_diary_dir() do _
            diary("m")
            record_all("function g()\n    1\nend")
            D.record("pkg>", "add A\nup")
            D.record("help?>", "sin")
            diary(:off)
            @test parses_cleanly(read_file("m.jl"))
        end
    end

    @testset "output=true records displayed results" begin
        with_diary_dir() do _
            diary("o"; output=true)
            D.record("", "1 + 2", D.Outcome(true, 3, nothing))
            D.record("", "x = [1, 2]", D.Outcome(true, [1, 2], nothing))
            D.record("", "y = 5;", D.Outcome(true, 5, nothing))          # hidden by `;`
            D.record("", "nothing", D.Outcome(true, nothing, nothing))   # no value
            D.record("shell>", "ls", D.Outcome(true, 7, nothing))        # only Julia mode
            diary(:off)
            txt = read_file("o.jl")
            @test occursin("1 + 2\n# 3\n", txt)
            @test occursin("x = [1, 2]\n# 2-element Vector{Int64}:\n#  1\n#  2\n", txt)
            @test occursin("y = 5;\n", txt) && !occursin("# 5", txt)
            @test occursin("# shell> ls\n", txt) && !occursin("# 7", txt)
            @test parses_cleanly(txt)
        end
        with_diary_dir() do _                                              # default: no results
            diary("o")
            D.record("", "1 + 2", D.Outcome(true, 3, nothing))
            diary(:off)
            @test !occursin("# 3", read_file("o.jl"))
        end
    end

    @testset "failed commands: skipped by default, comments with errors=:comment" begin
        with_diary_dir() do _
            diary("e")
            D.record("", "boom()", D.Outcome(false, nothing, "UndefVarError"))
            diary(:off)
            @test !occursin("boom", read_file("e.jl"))
        end
        with_diary_dir() do _
            @test_throws ArgumentError diary("e"; errors=:bogus)
            @test !isdiary()
            diary("e"; errors=:comment)
            D.record("", "boom()", D.Outcome(false, nothing, "UndefVarError: `boom` not defined"))
            D.record("", "1 +* 2", D.Outcome(false))                       # no details available
            D.record("shell>", "false", D.Outcome(false, nothing, "failed"))
            @test D.STATE.commands == 0 && D.STATE.skipped == 0            # kept, but not counted as commands
            diary(:off)
            txt = read_file("e.jl")
            @test occursin("# failed> boom()\n# ERROR: UndefVarError: `boom` not defined\n", txt)
            @test occursin("# failed> 1 +* 2\n# ERROR: the command could not be run\n", txt)
            @test occursin("# shell> false\n# ERROR: failed\n", txt)
            @test parses_cleanly(txt)
        end
    end

    @testset "filters apply while recording" begin
        with_diary_dir() do _
            diary("flt"; exclude=[r"^using ", "hunter2"], modes=[:julia, :pkg], redact=true)
            D.record("", "using Foo")                                      # excluded by pattern
            D.record("", "x = 1")
            D.record("", "login(\"bob\", \"hunter2\")")                    # excluded by literal
            D.record("shell>", "ls")                                       # mode not selected
            D.record("pkg>", "add A")
            D.record("", "api_key = \"abc123\"")                           # redacted
            diary(:off)
            txt = read_file("flt.jl")
            @test occursin("x = 1\n", txt) && occursin("# pkg> add A", txt)
            @test !occursin("using Foo", txt) && !occursin("hunter2", txt) && !occursin("shell>", txt)
            @test occursin("api_key = \"<redacted>\"", txt) && !occursin("abc123", txt)
            @test D.STATE.commands == 3                                    # filtered commands are not counted
        end
    end

    @testset "redaction also covers output and errors" begin
        with_diary_dir() do _
            secret = "ghp_" * "a"^30
            diary("r"; redact=true, output=true, errors=:comment)
            D.record("", "token_value", D.Outcome(true, secret, nothing))
            D.record("", "oops()", D.Outcome(false, nothing, "bad $secret"))
            diary(:off)
            @test !occursin(secret, read_file("r.jl"))
        end
    end

    @testset "a failing write never corrupts state" begin
        with_diary_dir() do _
            diary("w")
            rm("w.jl"); mkdir("w.jl")                                      # file turns into a directory mid-session
            @test_throws Exception D.record("", "x = 1")
            @test D.STATE.commands == 0
            @test_throws Exception diary(:off)
            @test !isdiary()                                               # stopped despite the failed footer
        end
    end
end
