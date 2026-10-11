@testset "diary(n) / write_last" begin
    hist = [(:julia, "a = 1"), (:julia, "diary(\"x.jl\")"), (:shell, "ls"),
            (:julia, "b = 2\nc = 3"), (:julia, "diary(2)")]

    @testset "last n, without diary calls" begin
        with_diary_dir() do dir
            D.STATE.file = joinpath(dir, "n.jl")
            D.write_last(2, hist)
            txt = read_file("n.jl")
            @test txt == "# ── last 2 commands ──\n# shell> ls\nb = 2\nc = 3\n"
            @test parses_cleanly(txt)
        end
    end

    @testset "edge cases" begin
        with_diary_dir() do dir
            D.STATE.file = joinpath(dir, "n.jl")
            D.write_last(10, hist)                                    # more than available
            @test startswith(read_file("n.jl"), "# ── last 3 commands ──\n")
            rm("n.jl")
            D.write_last(0, hist)                                     # nothing requested
            @test !isfile("n.jl")
            D.write_last(3, Tuple{Symbol,String}[])                   # empty history
            @test !isfile("n.jl")
            D.write_last(3, [(:julia, "diary()"), (:julia, "  ")])    # nothing left after filtering
            @test !isfile("n.jl")
            D.write_last(1, [(:julia, "a = 1")])                      # singular header
            @test read_file("n.jl") == "# ── last 1 command ──\na = 1\n"
        end
    end

    @testset "skips commands known to have failed" begin
        with_diary_dir() do dir
            D.STATE.file = joinpath(dir, "w.jl")
            h = [(:julia, "a = 1"), (:julia, "bad()"), (:julia, "b = 2")]
            D.remember_outcome!(2, "bad()", false)
            D.remember_outcome!(1, "something else", false)                 # text mismatch: ignored
            D.write_last(3, h)
            @test read_file("w.jl") == "# ── last 2 commands ──\na = 1\nb = 2\n"
        end
    end

    @testset "honours modes, exclude and redact" begin
        with_diary_dir() do dir
            D.STATE.file = joinpath(dir, "n2.jl")
            D.STATE.exclude = [r"^using "]
            D.STATE.modes = [:julia]
            D.STATE.redact = true
            D.write_last(5, [(:julia, "using Foo"), (:shell, "ls"), (:julia, "y = 2"),
                             (:julia, "password = 'p'")])
            @test read_file("n2.jl") == "# ── last 2 commands ──\ny = 2\npassword = '<redacted>'\n"
        end
    end

    @testset "n counts commands that survive the filters" begin
        with_diary_dir() do dir
            D.STATE.file = joinpath(dir, "k.jl")
            D.STATE.exclude = [r"^skip"]
            D.write_last(2, [(:julia, "a = 1"), (:julia, "b = 2"), (:julia, "skip_me()")])
            @test read_file("k.jl") == "# ── last 2 commands ──\na = 1\nb = 2\n"
        end
    end

    @testset "diary(n) through the public API" begin
        with_diary_dir() do _
            @test_throws ArgumentError diary(-1)
            @test_throws ArgumentError diary(:on, -1)
            @test_throws ArgumentError diary("bad.jl", -1)
            @test !isdiary()                      # a bad count must not start recording
            @test !isfile("bad.jl")
            @test diary(0) === nothing            # n = 0 needs no REPL history
        end
    end

    @testset "without a REPL" begin
        @test D.history_length() == 0
        @test D.active_line_edit_repl() === nothing
        @test_throws ErrorException D.repl_history()
        with_diary_dir() do _
            @test_throws ErrorException diary(3)                        # needs an interactive REPL
        end
    end
end
