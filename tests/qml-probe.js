.pragma library

// Shared check, log and finish bodies; each harness wrapper prints byte-identical lines.

function log(tag, line) {
    console.log(tag + " " + line)
}

// JSON compare that logs each pass by name, for the button and dialog harnesses.
function checkLoud(state, name, actual, expected) {
    state.checks += 1
    if (JSON.stringify(actual) === JSON.stringify(expected)) {
        state.log("ok " + name)
        return
    }
    state.failures.push(name)
    state.log("FAIL " + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
}

// Same compare, silent on a pass. The menu and settings harnesses log failures only.
function checkQuiet(state, name, actual, expected) {
    state.checks += 1
    if (JSON.stringify(actual) === JSON.stringify(expected)) {
        return
    }
    state.failures.push(name)
    state.log("FAIL " + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
}

// JSON compare over int counters for the preview hunt family, which prints PASS and FAIL itself.
function checkHunt(state, tag, label, actual, expected) {
    state.checks += 1
    var ok = JSON.stringify(actual) === JSON.stringify(expected)
    if (!ok) state.failures += 1
    console.log(tag + " " + (ok ? "PASS " : "FAIL ") + label + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
}

// DONE line through the harness log, for the array-counter harnesses.
function logDone(state) {
    state.log("DONE checks=" + state.checks + " failed=" + state.failures.length)
}

// DONE line straight to the console, for the int-counter family.
function logDoneHunt(state, tag) {
    console.log(tag + " DONE " + state.checks + " checks, " + state.failures + " failed")
}

// A stepped run ends past its script, so the driver loop falls out.
function stepPastEnd(state) {
    state.step = state.script.length + 1
}

// The menu and settings report stops the ticker first, so no later tick advances an ended run.
function reportCard(state, ticker) {
    ticker.running = false
    state.done = true
    if (state.failures.length === 0) {
        state.log("PASS " + state.checks + " checks")
    }
    state.log("DONE failures=" + state.failures.length)
}
