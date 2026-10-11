@testset "diary(...) arguments and options" begin
    @testset "normalize_file" begin
        with_diary_dir() do dir
            @test D.normalize_file("log") == abspath("log.jl")          # extension added
            @test D.normalize_file("log.jl") == abspath("log.jl")
            @test D.normalize_file("notes.txt") == abspath("notes.txt") # other extensions kept
            @test isabspath(D.normalize_file("sub/log"))
            @test D.normalize_file("sub/log") == abspath("sub/log.jl")
        end
    end

    @testset "toggle, on and off" begin
        with_diary_dir() do _
            diary()                                                      # toggle on (default file)
            @test isdiary() && diaryfile() == abspath("diary.jl")
            diary()                                                      # toggle off
            @test !isdiary()
            diary(:on);  @test isdiary()
            diary(:on);  @test isdiary()                                 # already on: no second header
            @test count("diary started", read_file("diary.jl")) == 2     # (one per toggle-on session above)
            diary(:off); @test !isdiary()
            diary(:off); @test !isdiary()                                # already off: no second footer
            diary("ON"); @test isdiary()                                 # case-insensitive
            diary("Off"); @test !isdiary()
            @test count("diary stopped", read_file("diary.jl")) == 3
        end
    end

    @testset "a file name starts recording and is remembered" begin
        with_diary_dir() do _
            diary("session")
            @test isdiary() && diaryfile() == abspath("session.jl")
            diary(:off)
            diary(:on)                                                   # resumes the same file
            @test diaryfile() == abspath("session.jl")
            diary(:off)
            diary(Symbol("sym"))                                         # symbols work as file names
            @test diaryfile() == abspath("sym.jl")
            diary(:off)
        end
    end

    @testset "files in new folders are created" begin
        with_diary_dir() do _
            diary("logs/2026/day")
            record_all("x = 1")
            diary(:off)
            @test isfile(joinpath("logs", "2026", "day.jl"))
        end
    end

    @testset "switching file while recording closes the old session" begin
        with_diary_dir() do _
            diary("a"); record_all("in_a = 1")
            diary("b"); record_all("in_b = 2")
            diary(:off)
            a, b = read_file("a.jl"), read_file("b.jl")
            @test occursin("in_a", a) && !occursin("in_b", a) && occursin("diary stopped", a)
            @test occursin("in_b", b) && !occursin("in_a", b)
            @test D.STATE.commands == 1                                  # counts restart per session
        end
        with_diary_dir() do _
            diary("same"); diary("same.jl")                              # same file: not a new session
            diary(:off)
            @test count("diary started", read_file("same.jl")) == 1
        end
    end

    @testset "a write failure leaves the diary off" begin
        with_diary_dir() do _
            mkdir("blocked.jl")                                          # a directory: opening it fails
            @test_throws Exception diary("blocked.jl")
            @test !isdiary()
        end
    end

    @testset "options persist until changed" begin
        with_diary_dir() do _
            diary("p"; timestamps=true, output=true, errors=:comment, redact=true,
                  exclude=["x"], modes=[:julia])
            diary(:off)
            diary(:on)                                                   # not mentioned: unchanged
            s = D.STATE
            @test s.timestamps && s.output && s.errors === :comment && s.redact
            @test length(s.exclude) == 1 && s.modes == [:julia]
            diary(:off; timestamps=false)                                # options can change while off
            @test !s.timestamps && s.output
            diary(:on; exclude=[], modes=[], redact=false, output=false, errors=:skip)
            @test isempty(s.exclude) && isempty(s.modes) && !s.redact && !s.output && s.errors === :skip
            diary(:off)
        end
    end

    @testset "a bad option changes nothing" begin
        with_diary_dir() do _
            @test_throws ArgumentError diary("bad"; timestamps=true, modes=[:nope])
            @test !isdiary() && !D.STATE.timestamps && isempty(D.STATE.modes)
            @test !isfile("bad.jl")                                      # and no file was started
            @test_throws ArgumentError diary(; errors=:bogus)
            @test_throws ArgumentError D.set_options!(errors=:bogus, redact=true)
            @test !D.STATE.redact
            @test_throws ArgumentError diary(modes=[:julia, :nope])
            @test D.STATE.modes == Symbol[]
        end
    end

    @testset "return values are quiet" begin
        with_diary_dir() do _
            @test diary("q") === nothing
            @test diary(:off) === nothing
            @test diary(; timestamps=true) === nothing
            @test diary() === nothing
        end
    end

    @testset "the file and state are exposed" begin
        with_diary_dir() do _
            @test isdiary() === false
            diary("e"); @test isdiary() === true; diary(:off)
            @test diaryfile() == abspath("e.jl")
        end
    end
end
