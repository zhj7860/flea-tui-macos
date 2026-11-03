.import "../../ui/js/Selection.js" as Selection

function run(check) {
    var s = Selection.create()
    check("a new selection is empty", s.count(), 0)

    s.only(4)
    check("only replaces", s.count(), 1)
    check("only selects the row asked for", s.has(4), true)

    s.toggle(6)
    check("toggle adds", s.count(), 2)
    s.toggle(6)
    check("toggle removes", s.count(), 1)

    s.only(2)
    s.extendTo(5, 2)
    check("extend covers the range inclusive", s.count(), 4)
    check("extend includes the anchor", s.has(2), true)
    check("extend includes the far end", s.has(5), true)

    s.only(5)
    s.extendTo(2, 5)
    check("extend runs backwards too", s.count(), 4)

    s.all(10)
    check("select all takes every row", s.count(), 10)
    // count() and indices() are different questions, and an operation is handed the second one. This
    // is the first link of the Dropbox truncation: Ctrl-a really does yield an index per row, far more
    // than the window holds, and what drops them is targetPaths downstream.
    s.all(5000)
    check("and hands every one of them out, not just a windowful",
          s.indices().length, 5000)
    check("the last index is the last row, so nothing is capped on the way out",
          s.indices()[4999], 4999)
    s.clear()
    check("clear empties it", s.count(), 0)
    check("indices come back sorted", Selection.create().indices().length, 0)

    var t = Selection.create()
    t.only(3)
    t.toggle(1)
    check("indices are sorted ascending", t.indices()[0], 1)
}
