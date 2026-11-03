.import "../../ui/js/CodeRuns.js" as CodeRuns
.import "../../ui/js/Contrast.js" as Contrast

// The ink a role draws in, as the theme names them: [foreground, red, green, yellow, blue, magenta, cyan].
var INKS = ["#cccccc", "#ff0001", "#00ff02", "#ffff03", "#0004ff", "#ff00ff", "#00ffff"]
var FALLBACK = { red: "#f38ba8", green: "#a6e3a1", yellow: "#f9e2af", blue: "#89b4fa", magenta: "#cba6f7", cyan: "#94e2d5" }

function run(check) {
    check("role 0 is the foreground", CodeRuns.roleName(0), "foreground")
    check("roles 1 to 6 are bat's SGR 31 to 36", [1, 2, 3, 4, 5, 6].map(CodeRuns.roleName).join(" "), "red green yellow blue magenta cyan")
    check("an unknown role is the foreground", CodeRuns.roleName(9), "foreground")

    check("& < > and \" are escaped", CodeRuns.escape("a&b<c>d\"e"), "a&amp;b&lt;c&gt;d&quot;e")
    check("an already escaped entity is escaped again", CodeRuns.escape("&lt;"), "&amp;lt;")
    check("plain text is left alone", CodeRuns.escape("fn add(a: i32) -> i32 { 'x' }"), "fn add(a: i32) -&gt; i32 { 'x' }")

    check("a foreground run is bare text", CodeRuns.styled([0, "let"], INKS), "let")
    check("a magenta run is one font tag of its ink", CodeRuns.styled([5, "fn"], INKS), "<font color=\"#ff00ff\">fn</font>")
    check("runs of two roles join in order", CodeRuns.styled([5, "fn", 0, " ", 4, "add"], INKS),
          "<font color=\"#ff00ff\">fn</font> <font color=\"#0004ff\">add</font>")
    check("blue is not the foreground", CodeRuns.styled([4, "add"], INKS) !== "add", true)
    check("a run in every role takes its own ink", CodeRuns.styled([1, "a", 2, "b", 3, "c", 4, "d", 5, "e", 6, "f"], INKS),
          "<font color=\"#ff0001\">a</font><font color=\"#00ff02\">b</font><font color=\"#ffff03\">c</font><font color=\"#0004ff\">d</font><font color=\"#ff00ff\">e</font><font color=\"#00ffff\">f</font>")

    var img = "<img src=\"http://127.0.0.1:9/x\">"
    check("markup in a run is escaped, never a tag", CodeRuns.styled([0, img], INKS),
          "&lt;img src=&quot;http://127.0.0.1:9/x&quot;&gt;")
    check("markup in a coloured run is escaped inside its font tag", CodeRuns.styled([2, img], INKS),
          "<font color=\"#00ff02\">&lt;img src=&quot;http://127.0.0.1:9/x&quot;&gt;</font>")
    check("a run text cannot close its own font tag", CodeRuns.styled([2, "</font><b>x"], INKS).indexOf("</font><b>"), -1)
    check("no raw angle bracket survives from text", CodeRuns.styled([1, "<", 5, ">", 0, "<>"], INKS).replace(/<\/?font[^>]*>/g, "").indexOf("<"), -1)

    check("a single space between words stays a space", CodeRuns.styled([0, "a b"], INKS), "a b")
    check("a repeated space is kept as non-breaking spaces", CodeRuns.styled([0, "a  b"], INKS), "a&nbsp;&nbsp;b")
    check("a leading space is kept", CodeRuns.styled([0, "  x"], INKS), "&nbsp;&nbsp;x")
    check("a trailing space is kept", CodeRuns.styled([0, "x "], INKS), "x&nbsp;")
    check("a space alone is kept", CodeRuns.styled([0, " "], INKS), "&nbsp;")
    check("a single space at the start of a run after text stays a space",
          CodeRuns.styled([5, "fn", 0, " add"], INKS), "<font color=\"#ff00ff\">fn</font> add")
    check("two spaces split across runs are both kept",
          CodeRuns.styled([5, "fn ", 0, " add"], INKS), "<font color=\"#ff00ff\">fn&nbsp;</font>&nbsp;add")
    check("a tab at the line start fills to the next stop of eight", CodeRuns.styled([0, "\tx"], INKS), "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;x")
    check("a tab after three characters fills five", CodeRuns.styled([0, "abc\tx"], INKS), "abc&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;x")
    check("a tab counts the columns of the runs before it", CodeRuns.styled([5, "ab", 0, "\tx"], INKS),
          "<font color=\"#ff00ff\">ab</font>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;x")
    check("an empty line is empty", CodeRuns.styled([], INKS), "")

    check("plain joins the runs' text", CodeRuns.plain([5, "fn", 0, " ", 4, "add"]), "fn add")
    check("plain expands a tab to the next stop", CodeRuns.plain([0, "a\tb"]), "a       b")
    check("plain of nothing is empty", CodeRuns.plain([]), "")

    // The inks: each lifted to 4.5 on whichever of the two grounds it contrasts less with.
    var dark = "#101315"
    var surface = "#181825"
    var base = { background: dark, surface: surface, red: FALLBACK.red, green: FALLBACK.green, yellow: FALLBACK.yellow, blue: FALLBACK.blue, magenta: FALLBACK.magenta, cyan: FALLBACK.cyan }
    var none = CodeRuns.inks({}, base, "#cccccc")
    check("no palette gives the foreground then the six fallbacks", none.join(" "),
          "#cccccc " + [FALLBACK.red, FALLBACK.green, FALLBACK.yellow, FALLBACK.blue, FALLBACK.magenta, FALLBACK.cyan].join(" "))
    check("a palette colour passing on both grounds is kept", CodeRuns.inks({ blue: "#5599ff" }, base, "#cccccc")[4], "#5599ff")
    check("an unnamed colour takes its ANSI slot", CodeRuns.inks({ color5: "#ccaaff" }, base, "#cccccc")[5], "#ccaaff")
    var pale = CodeRuns.inks({ background: "#f4f4ef", dark_background: "#e4e4df", yellow: "#f0f0d0" }, base, "#222222")[3]
    check("a yellow too pale for a light ground is lifted to 4.5", Contrast.ratio(pale, "#f4f4ef") >= 4.5, true)
    var mid = CodeRuns.inks({ background: "#303030", dark_background: "#404040", red: "#884444" }, base, "#cccccc")[1]
    check("a red under 4.5 on the surface is lifted against it, the less contrasting ground", Contrast.ratio(mid, "#404040") >= 4.5, true)
    for (var i = 1; i <= 6; i++) {
        var ink = FALLBACK[CodeRuns.roleName(i)]
        var worst = Math.min(Contrast.ratio(ink, dark), Contrast.ratio(ink, surface))
        check("fallback " + CodeRuns.roleName(i) + " holds 4.5 on both dark grounds", worst >= 4.5, true)
    }
}
