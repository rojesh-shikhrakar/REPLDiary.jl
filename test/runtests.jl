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
end
