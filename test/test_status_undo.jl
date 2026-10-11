@testset "status" begin
    with_diary_dir() do _
        diary("s")
        record_all("a = 1")
        D.record("", "bad()", D.Outcome(false))
        st = D.diary_status()
        @test st.recording && st.commands == 1 && st.skipped == 1
        @test endswith(st.file, "s.jl")
        @test (st.timestamps, st.output, st.errors, st.redact) == (false, false, :skip, false)

        out = sprint(D.print_status)
        @test occursin("Diary is ON", out) && occursin("1 recorded, 1 failed", out)
        @test occursin("modes=all", out) && occursin("exclude=none", out)

        diary(:off; modes=[:julia, :pkg], exclude=[r"^using "], redact=true)
        out = sprint(D.print_status)
        @test occursin("Diary is OFF", out)
        @test occursin("modes=julia,pkg", out) && occursin("r\"^using \"", out) && occursin("redact=true", out)

        st = D.diary_status()
        @test st.modes == [:julia, :pkg]
        push!(st.modes, :shell)                                          # a copy: cannot alter the state
        @test D.STATE.modes == [:julia, :pkg]

        diary(:on)                                                       # a new session resets the counts
        @test D.diary_status().commands == 0 && D.diary_status().skipped == 0
        diary(:off)

        @test redirect_stdout(() -> diary(:status), devnull) === nothing     # the public form prints and returns nothing
    end
end

@testset "undo" begin
    @testset "removes the last entries" begin
        with_diary_dir() do _
            diary("u")
            record_all("keep = 1", "oops = 2", "oops = 3")
            @test D.STATE.commands == 3
            diary(:undo)
            @test !occursin("oops = 3", read_file("u.jl")) && occursin("oops = 2", read_file("u.jl"))
            @test D.STATE.commands == 2                                  # count follows the file
            diary(:undo, 5)                                              # more than available: stops at the header
            txt = read_file("u.jl")
            @test occursin("diary started", txt) && !occursin("keep", txt)
            @test D.STATE.commands == 0
            @test D.undo!() == 0                                         # nothing left
            @test_logs (:info, r"nothing to undo") diary(:undo)
            diary(:off)
        end
    end

    @testset "can be repeated and combined with new entries" begin
        with_diary_dir() do _
            diary("u")
            record_all("a = 1")
            diary(:undo)
            record_all("b = 2")
            @test D.undo!(2) == 1                                        # only one entry since the header
            diary(:off)
            @test !occursin("a = 1", read_file("u.jl")) && !occursin("b = 2", read_file("u.jl"))
        end
    end

    @testset "undoes a multi-line entry as one unit" begin
        with_diary_dir() do _
            diary("u")
            record_all("keep = 1", "function f()\n    1\nend")
            diary(:undo)
            txt = read_file("u.jl")
            @test occursin("keep = 1", txt) && !occursin("function", txt)
            @test parses_cleanly(txt)
            diary(:off)
        end
    end

    @testset "undoes a diary(n) block and counts failures correctly" begin
        with_diary_dir() do dir
            D.STATE.file = joinpath(dir, "u.jl")
            D.write_last(2, [(:julia, "a = 1"), (:julia, "b = 2")])
            @test occursin("last 2 commands", read_file("u.jl"))
            @test D.undo!() == 1
            @test read_file("u.jl") == ""
            diary("v"; errors=:comment)
            D.record("", "bad()", D.Outcome(false, nothing, "x"))
            @test D.STATE.commands == 0
            diary(:undo)
            @test !occursin("bad()", read_file("v.jl")) && D.STATE.commands == 0
            diary(:off)
        end
    end

    @testset "refuses when the file was changed elsewhere" begin
        with_diary_dir() do _
            diary("u")
            record_all("again = 4")
            write("u.jl", read_file("u.jl") * "# edited elsewhere\n")
            @test_logs (:warn, r"cannot undo") diary(:undo)
            @test occursin("again = 4", read_file("u.jl"))               # untouched
            @test D.undo!() == 0                                         # the stale stack was dropped
            diary(:off)
        end
    end

    @testset "refuses when the file is gone" begin
        with_diary_dir() do _
            diary("u")
            record_all("x = 1")
            rm("u.jl")
            @test_logs (:warn, r"cannot undo") diary(:undo)
            @test !isfile("u.jl")
            diary(:off)
        end
    end

    @testset "header and footer are not undoable" begin
        with_diary_dir() do _
            diary("u")
            record_all("x = 1")
            diary(:off)                                                  # footer written: stack cleared
            @test D.undo!() == 0
            @test occursin("diary stopped", read_file("u.jl"))
        end
    end

    @testset "argument checks" begin
        with_diary_dir() do _
            @test_throws ArgumentError diary(:undo, -1)
            diary("u"); diary(:undo, 0)                                  # zero is allowed and removes nothing
            diary(:off)
        end
    end
end
