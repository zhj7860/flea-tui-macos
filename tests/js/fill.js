.import "../../ui/js/Format.js" as Format
.import "../../ui/js/Mounts.js" as Mounts
.import "../../ui/js/PathBar.js" as PathBar
.import "../../ui/js/RunFile.js" as RunFile
.import "../../ui/js/Tags.js" as Tags

// Pins what the rail, picker, run card and tag sentences print through Format.fill; its own cases are in tests/js/format.js.

function run(check) {
    var fill = Format.fill
    check("Format.fill puts values by number, in any order, every copy",
          fill("%2 %1 %1", "a", "b") + "|" + fill("%1 and %2 and %3", 1, "two", 3) + "|" + fill("none", 1), "b a a|1 and two and 3|none")
    check("Format.fill leaves a placeholder with no value, and %0, as written",
          fill("%1 %2", "x") + "|" + fill("%0 %1", "x"), "x %2|%0 x")
    check("Format.fill prints a value as a string, a dollar as typed",
          fill("%1|%1", "$&") + "|" + fill("%1", undefined) + "|" + fill("%1", null), "$&|$&|undefined|null")
    check("the run card title keeps a name holding a dollar or a placeholder",
          RunFile.titleFor("a$&b") + "|" + RunFile.titleFor("%1") + "|" + RunFile.titleFor("%2"),
          "a$&b is a program|%1 is a program|%2 is a program")
    check("every tag name prints in the status and the remove lines",
          Tags.NAMES.map(function (n) { return Tags.statusLine(2, n) + "|" + Tags.removedLine(1, n) }).join("\n"),
          Tags.NAMES.map(function (n) { return "Tagged 2 items " + n + " · z undoes|Removed " + n + " from 1 item · z undoes" }).join("\n"))
    check("a large tag count prints as given",
          Tags.statusLine(1000, "Gray") + "|" + Tags.clearedLine(0),
          "Tagged 1000 items Gray · z undoes|Removed all tags from 0 items · z undoes")

    // The rail and picker sentences take one value and print it whole, whatever it is.
    check("every rail sentence fills an ordinary label, an empty one and a number",
          [Mounts.WORDS.nothingToRelease, Mounts.WORDS.stillEjecting, Mounts.WORDS.stillUnmounting].map(function (w) {
              return [Format.fill(w, "Backup 2"), Format.fill(w, ""), Format.fill(w, 0)].join("/")
          }).join("\n"),
          "Backup 2 has nothing to eject or unmount/ has nothing to eject or unmount/0 has nothing to eject or unmount\n"
          + "Still ejecting Backup 2; wait for its result/Still ejecting ; wait for its result/Still ejecting 0; wait for its result\n"
          + "Still unmounting Backup 2; wait for its result/Still unmounting ; wait for its result/Still unmounting 0; wait for its result")
    check("a label that holds a placeholder or a dollar sign is printed as written",
          Format.fill(Mounts.WORDS.stillEjecting, "%1") + "|" + Format.fill(Mounts.WORDS.nothingToRelease, "$&"),
          "Still ejecting %1; wait for its result|$& has nothing to eject or unmount")
    check("an undefined or null label prints as a string and every copy of the placeholder fills",
          Format.fill(Mounts.WORDS.nothingToRelease, undefined) + "|" + Format.fill(Mounts.WORDS.stillEjecting, null) + "|" + Format.fill("%1/%1", "x"),
          "undefined has nothing to eject or unmount|Still ejecting null; wait for its result|x/x")
    check("an empty, numeric or placeholder path fills as written",
          Format.fill(PathBar.MISSING_SENTENCE, "") + "|" + Format.fill(PathBar.MISSING_SENTENCE, 0) + "|" + Format.fill(PathBar.FILTERED_SENTENCE, "%1"),
          " does not exist or cannot be reached.|0 does not exist or cannot be reached.|%1 is hidden by the file filter or the hidden files setting.")
    check("an undefined or null path prints as a string",
          Format.fill(PathBar.MISSING_SENTENCE, undefined) + "|" + Format.fill(PathBar.FILTERED_SENTENCE, null),
          "undefined does not exist or cannot be reached.|null is hidden by the file filter or the hidden files setting.")
}
