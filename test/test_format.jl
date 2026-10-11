@testset "format" begin
    @testset "helpers used by the tests" begin
        @test parses_cleanly("x = 1\nf(y) = y + 1\n")
        @test !parses_cleanly("1 +* 2\n")          # guards against a vacuous validity check
        @test !parses_cleanly("function f(\n")
    end

    @testset "mode_label / label_mode" begin
        @test D.mode_label(:julia) == ""
        @test D.mode_label(:shell) == "shell>"
        @test D.mode_label(:help) == "help?>"
        @test D.mode_label(:pkg) == "pkg>"
        @test D.mode_label(:custom) == "custom>"     # unknown modes still get a label
    end

    @testset "is_diary_call" begin
        for text in ("diary()", "diary(:off)", "  diary (\"x\")", "REPLDiary.diary(5)", "diary(\"a.jl\", 3)")
            @test D.is_diary_call("", text)
        end
        for text in ("mydiary()", "x = 1", "# diary()", "println(\"diary(\")", "isdiary()")
            @test !D.is_diary_call("", text)
        end
        @test !D.is_diary_call("shell>", "diary()")   # only Julia input is a diary call
    end

    @testset "format_entry" begin
        @test D.format_entry("", "  x = 1 \n") == "x = 1\n"
        @test D.format_entry("", "f(x) = begin\n    x\nend") == "f(x) = begin\n    x\nend\n"
        @test D.format_entry("pkg>", "add A\nup") == "# pkg> add A\n# pkg> up\n"
        @test D.format_entry("shell>", "ls -la") == "# shell> ls -la\n"
        @test D.format_entry("", "") == ""
        @test D.format_entry("", " \n\t ") == ""
        @test D.format_entry("pkg>", "   ") == ""
        @test occursin(r"^# \d\d:\d\d:\d\d\nx\n$", D.format_entry("", "x"; timestamp=true))
        @test occursin(r"^# \d\d:\d\d:\d\d\n# shell> ls\n$", D.format_entry("shell>", "ls"; timestamp=true))
        @test D.format_entry("", "x"; timestamp=true) != D.format_entry("", "x")
        @test parses_cleanly(D.format_entry("pkg>", "add A\nup"))
    end

    @testset "comment_lines" begin
        @test D.comment_lines("a") == "# a\n"
        @test D.comment_lines("a\nb\n\n") == "# a\n# b\n"     # trailing blank lines dropped
        @test D.comment_lines("a\n\nb") == "# a\n# \n# b\n"   # inner blank lines kept
    end

    @testset "format_result" begin
        @test D.format_result("1 + 2", 3) == "# 3\n"
        @test D.format_result("x = [1, 2]", [1, 2]) == "# 2-element Vector{Int64}:\n#  1\n#  2\n"
        @test D.format_result("\"s\"", "s") == "# \"s\"\n"
        @test D.format_result("nothing", nothing) == ""
        @test D.format_result("y = 5;", 5) == ""             # `;` hides the value
        @test D.format_result("y = 5;  ", 5) == ""
        @test D.format_result("y = 5 # not hidden; really", 5) != ""

        # `show` is user code: a broken or silent one must not break recording.
        struct BrokenShow end
        Base.show(::IO, ::MIME"text/plain", ::BrokenShow) = error("nope")
        @test D.format_result("BrokenShow()", BrokenShow()) == ""
        struct SilentShow end
        Base.show(::IO, ::MIME"text/plain", ::SilentShow) = nothing
        @test D.format_result("SilentShow()", SilentShow()) == ""
    end

    @testset "format_error" begin
        @test D.format_error("boom") == "# ERROR: boom\n"
        @test D.format_error("line 1\nline 2") == "# ERROR: line 1\n# line 2\n"
    end
end
