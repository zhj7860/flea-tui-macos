.import "../../ui/js/Match.js" as Match

function run(check) {
    check("a match in the root has no location", Match.location("BENCHMARK.md"), "")
    check("a match in the root is its own base name", Match.base("BENCHMARK.md"), "BENCHMARK.md")
    check("a nested match keeps its parent path", Match.location("tools/benches/bench-run.sh"), "tools/benches")
    check("a nested match's base name is the leaf", Match.base("tools/benches/bench-run.sh"), "bench-run.sh")
    check("a directory match's base name is its last segment", Match.base("tools/benches"), "benches")

    check("an empty query paints no run", Match.run("bench.txt", "").start, -1)
    check("a miss paints no run", Match.run("other.txt", "bench").start, -1)
    check("a run starts where the query starts", Match.run("bench.txt", "bench").start, 0)
    check("a run is exactly the query's length", Match.run("bench.txt", "bench").length, 5)
    check("the run folds case the way the backend does", Match.run("BENCHMARK.md", "bench").start, 0)
    check("the run finds a query inside the name", Match.run("field-bench-notes.md", "bench").start, 6)
}
