@testset "outcomes" begin
    @testset "Outcome from a backend response" begin
        ok = D.Outcome(7 => false)
        @test ok.succeeded && ok.value == 7 && ok.error === nothing

        stack = [(exception=ErrorException("inner"), backtrace=nothing),
                 (exception=ErrorException("bad"), backtrace=nothing)]
        failed = D.Outcome(stack => true)
        @test !failed.succeeded && failed.error == "bad"     # the last exception is the one reported
        @test failed.value === nothing

        @test D.Outcome(ErrorException("plain") => true).error == "plain"   # not a stack
        @test D.Outcome(Any[] => true).succeeded == false                   # empty stack: still a failure
        @test D.Outcome(nothing => false).succeeded
    end

    @testset "pending commands are recorded only on success" begin
        with_diary_dir() do _
            diary("f")
            D.submit!("", "ok1 = 1");      D.resolve_pending!(true)
            D.submit!("", "boom()");       D.resolve_pending!(false)
            D.submit!("", "1 +* 2");       D.finish_submission!()     # never reached the backend
            D.submit!("pkg>", "add Foo");  D.finish_submission!()     # Pkg: outcome unknowable, kept
            D.submit!("", "ok2 = 2");      D.resolve_pending!(true)
            D.finish_submission!()                                     # nothing pending: no-op
            D.resolve_pending!(true)                                   # likewise
            diary(:off)
            txt = read_file("f.jl")
            @test occursin("ok1 = 1", txt) && occursin("ok2 = 2", txt)
            @test occursin("# pkg> add Foo", txt)
            @test !occursin("boom", txt) && !occursin("+*", txt)
            @test D.PENDING[] === nothing
        end
    end

    @testset "a new submission replaces an unresolved one" begin
        with_diary_dir() do _
            diary("r")
            D.submit!("", "lost = 1")
            D.submit!("", "kept = 2"); D.resolve_pending!(true)
            diary(:off)
            txt = read_file("r.jl")
            @test occursin("kept = 2", txt) && !occursin("lost", txt)
        end
    end

    @testset "resolve with a full Outcome" begin
        with_diary_dir() do _
            diary("o"; output=true, errors=:comment)
            D.submit!("", "1 + 1");  D.resolve_pending!(D.Outcome(true, 2, nothing))
            D.submit!("", "bad()");  D.resolve_pending!(D.Outcome(false, nothing, "oops"))
            diary(:off)
            txt = read_file("o.jl")
            @test occursin("1 + 1\n# 2\n", txt) && occursin("# failed> bad()\n# ERROR: oops\n", txt)
        end
    end

    @testset "outcomes are remembered for diary(n)" begin
        with_diary_dir() do _
            D.submit!("", "good()"); D.resolve_pending!(true)       # no REPL: history index is 0
            @test D.OUTCOMES[0] == (hash("good()"), true)
            D.submit!("", "bad()");  D.resolve_pending!(false)
            @test D.OUTCOMES[0] == (hash("bad()"), false)                  # latest outcome wins
        end
    end

    @testset "succeeded_or_unknown" begin
        with_diary_dir() do _
            D.remember_outcome!(2, "bad()", false)
            D.remember_outcome!(3, "good()", true)
            @test !D.succeeded_or_unknown(2, "bad()")
            @test D.succeeded_or_unknown(3, "good()")
            @test D.succeeded_or_unknown(4, "never seen")            # unknown: keep
            @test D.succeeded_or_unknown(2, "different text")        # shifted history: keep
        end
    end

    @testset "is_pkg_mode" begin
        @test D.is_pkg_mode("pkg>") && D.is_pkg_mode("(@v1.13) pkg>")
        @test !D.is_pkg_mode("") && !D.is_pkg_mode("shell>") && !D.is_pkg_mode("help?>")
    end

    @testset "flush_pending_at_exit keeps a final exit()" begin
        with_diary_dir() do _
            diary("x")
            D.submit!("", "exit()")
            D.flush_pending_at_exit()
            @test D.PENDING[] === nothing
            @test occursin("exit()", read_file("x.jl"))
            D.flush_pending_at_exit()                                # nothing pending: harmless
            diary(:off)
        end
    end
end

@testset "outcome memory stays bounded" begin
    with_diary_dir() do _
        for i in 1:(2 * D.OUTCOMES_KEEP + 5)
            D.remember_outcome!(i, "cmd $i", true)
        end
        @test length(D.OUTCOMES) <= D.OUTCOMES_KEEP + 5     # pruned to the newest entries
        @test haskey(D.OUTCOMES, 2 * D.OUTCOMES_KEEP + 5)   # newest kept
        @test !haskey(D.OUTCOMES, 1)                        # oldest dropped
        @test all(v -> v[1] isa UInt64, values(D.OUTCOMES)) # no command text retained
    end
end

@testset "undo stack stays bounded" begin
    with_diary_dir() do _
        diary("u")
        for i in 1:(D.UNDO_LIMIT + 50)
            D.record("", "x$i = $i")
        end
        @test length(D.UNDO_STACK) == D.UNDO_LIMIT
        @test D.undo!(1) == 1                                # the newest is still undoable
        diary(:off)
    end
end
