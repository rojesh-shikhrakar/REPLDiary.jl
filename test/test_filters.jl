@testset "filters" begin
    @testset "label_mode" begin
        @test D.label_mode("") == :julia
        @test D.label_mode("shell>") == :shell
        @test D.label_mode("help?>") == :help
        @test D.label_mode("pkg>") == :pkg
        @test D.label_mode("(@v1.13) pkg>") == :pkg
        @test D.label_mode("(MyEnv) pkg>") == :pkg
    end

    @testset "as_regexes" begin
        @test D.as_regexes(r"^using ") == [r"^using "]
        re = only(D.as_regexes("a.b(c)"))
        @test occursin(re, "call a.b(c) now")
        @test !occursin(re, "axb(c)")                 # strings are literal, `.` is not a wildcard
        @test occursin(only(D.as_regexes("1+1")), "x = 1+1")
        @test !occursin(only(D.as_regexes("1+1")), "x = 11")
        @test length(D.as_regexes(["a", r"b", "c|d"])) == 3
        @test !occursin(D.as_regexes(["c|d"])[1], "c")  # `|` is literal too
        @test isempty(D.as_regexes([]))
    end

    @testset "as_modes" begin
        @test D.as_modes(:julia) == [:julia]
        @test D.as_modes([:julia, :pkg]) == [:julia, :pkg]
        @test D.as_modes(["shell", "help"]) == [:shell, :help]
        @test D.as_modes([:julia, :julia]) == [:julia]
        @test D.as_modes([]) == Symbol[]
        err = try D.as_modes([:julia, :nope]); nothing catch e; e end
        @test err isa ArgumentError
        @test occursin(":nope", err.msg) && occursin(":pkg", err.msg)   # names the culprit and the choices
    end

    @testset "should_record" begin
        with_diary_dir() do _
            @test D.should_record(:julia, "anything")
            @test D.should_record(:shell, "anything")

            D.STATE.modes = [:julia]
            @test D.should_record(:julia, "x")
            @test !D.should_record(:shell, "x")
            @test !D.should_record(:pkg, "x")

            D.STATE.modes = Symbol[]
            D.STATE.exclude = [r"^using ", r"secret"]
            @test !D.should_record(:julia, "using Foo")
            @test !D.should_record(:julia, "my_secret_fn()")
            @test D.should_record(:julia, "x = 1  # using Foo")      # `^` anchors
            @test D.should_record(:pkg, "add Foo")

            D.STATE.modes = [:pkg]                                   # both filters combine
            @test !D.should_record(:julia, "x = 1")
            @test D.should_record(:pkg, "add Foo")
            @test !D.should_record(:pkg, "add secret")
        end
    end

    @testset "redact_secrets" begin
        mask = D.REDACTED
        @test mask == "<redacted>"

        # standalone token shapes
        @test D.redact_secrets("t = \"ghp_" * "a"^30 * "\"") == "t = \"$mask\""
        @test D.redact_secrets("github_pat_" * "A1_"^10) == mask
        @test D.redact_secrets("key = sk-" * "x"^20) == "key = $mask"
        @test D.redact_secrets("AKIA" * "A"^16) == mask
        @test D.redact_secrets("xoxb-1234567890-abcdef") == mask
        @test D.redact_secrets("eyJhbGciOiJI.eyJzdWIiOiIx.SflKxwRJSMeK") == mask
        @test D.redact_secrets("curl -H 'Authorization: Bearer abcdefghijklmnop1234'") ==
              "curl -H 'Authorization: $mask'"
        @test D.redact_secrets("curl -H 'authorization: bearer abcdefghijklmnop1234'") ==
              "curl -H 'authorization: $mask'"

        # assignments keep the name, the separator and the quote style
        @test D.redact_secrets("password = \"hunter2\"") == "password = \"$mask\""
        @test D.redact_secrets("api_key=\"abc123\"") == "api_key=\"$mask\""
        @test D.redact_secrets("API-KEY = 'abc123'") == "API-KEY = '$mask'"
        @test D.redact_secrets("token: 'abc'") == "token: '$mask'"
        @test D.redact_secrets("secret_token = \"zzz\"") == "secret_token = \"$mask\""   # name continues after the keyword
        @test D.redact_secrets("github_token = \"zzz\"") == "github_token = \"$mask\""  # the keyword may follow a prefix
        @test D.redact_secrets("author = \"me\"") == "author = \"me\""             # `auth` inside a word is not a secret
        @test D.redact_secrets("login(password=\"p\", user=\"u\")") == "login(password=\"$mask\", user=\"u\")"

        # things that must stay readable
        for safe in ("x = 1", "password_length = 12", "tokens = [1, 2]", "ghp_short", "sk-short",
                     "println(\"hello\")", "Bearer short")
            @test D.redact_secrets(safe) == safe
        end
        @test D.redact_secrets("") == ""
    end

    @testset "prepare_text honours the redact option" begin
        with_diary_dir() do _
            @test D.prepare_text("password = \"x\"") == "password = \"x\""
            D.STATE.redact = true
            @test D.prepare_text("password = \"x\"") == "password = \"<redacted>\""
            @test D.prepare_text(SubString("abc", 1, 2)) == "ab"           # accepts any string type
        end
    end
end
