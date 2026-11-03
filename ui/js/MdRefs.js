.pragma library

// Parse one definition's text; MdBlocks alone decides where definitions are allowed.
.import "MdLink.js" as Link
.import "MdHtml.js" as MdHtml
.import "MdContainer.js" as Container

var hasOwn = Object.prototype.hasOwnProperty

// Sample: [pic]: image.png "Title"; an empty destination can continue on the next container line.
function readDefinition(line) {
    var indent = 0
    while (indent < MAX_INDENT && line.charAt(indent) === " ")
        indent++
    var found = Link.readLabelRef(line, indent)
    if (found === null || found.label.trim().length === 0 || found.label.charAt(0) === "^" || line.charAt(found.end) !== ":")
        return null
    var rest = line.slice(found.end + 1)
    if (rest.trim().length === 0)
        return { key: Link.normalizeLabel(found.label), target: "", titled: false }
    var body = readBodyAt(rest, 0)
    if (body === null)
        return null
    return { key: Link.normalizeLabel(found.label), target: body.target, titled: body.titled }
}

// Sample: <my pic.png> "Title" or pic.png; one destination grammar for top level and containers.
function readDefinitionParts(text) {
    var body = readBodyAt(text, 0)
    if (body === null)
        return { target: "", titled: false }
    return { target: body.target, titled: body.titled }
}

function readDefinitionTarget(text) {
    return readDefinitionParts(text).target
}

var MAX_INDENT = 3
var TITLE_CLOSER = { '"': '"', "'": "'", "(": ")" }

// Sample input: "\n  x" read from 0 answers { at: 4, newline: true }; spaces, tabs and at most one line ending are skipped.
function skipGap(text, from) {
    var at = from
    var newline = false
    while (at < text.length && (text.charAt(at) === " " || text.charAt(at) === "\t" || (!newline && text.charAt(at) === "\n"))) {
        newline = newline || text.charAt(at) === "\n"
        at++
    }
    return { at: at, newline: newline }
}

// Sample input: '<a b> "t"' read from 0 answers { target: "a b", end: 5 }; "/u x" answers { target: "/u", end: 2 }; "<a" answers null.
function readDestinationAt(text, from) {
    var at = from
    if (text.charAt(at) === "<") {
        at = Link.angleClose(text, from + 1, text.length, true)
        return at >= 0 ? { target: text.slice(from + 1, at), end: at + 1 } : null
    }
    var depth = 0
    while (at < text.length && !/[\s\x00-\x1f]/.test(text.charAt(at))) {
        var c = text.charAt(at)
        depth += c === "(" ? 1 : c === ")" ? -1 : 0
        at += c === "\\" && at + 1 < text.length && !/\s/.test(text.charAt(at + 1)) ? 2 : 1
    }
    return at > from && depth === 0 ? { target: text.slice(from, at), end: at } : null
}

// Sample input: `"a\nb" x` read from 0 answers 6, the index after the closing quote; a title needs its closer, and "(" titles hold no "(".
function readTitleEnd(text, from) {
    var opener = text.charAt(from)
    var closer = TITLE_CLOSER.hasOwnProperty(opener) ? TITLE_CLOSER[opener] : ""
    for (var at = from + 1; closer !== "" && at < text.length; at++) {
        var c = text.charAt(at)
        if (c === closer)
            return at + 1
        if (opener === "(" && c === "(")
            return -1
        at += c === "\\" && text.charAt(at + 1) !== "\n" ? 1 : 0
    }
    return -1
}

// Sample input: "a  \nb" at 1 answers true, only blanks remain on the line; "a b" at 1 answers false.
function endsLine(text, from) {
    var at = from
    while (text.charAt(at) === " " || text.charAt(at) === "\t")
        at++
    return at >= text.length || text.charAt(at) === "\n"
}

// Sample input: '<a b> "t"' read from 0 answers { target: "a b", titled: true, end: 9 }; "/u x" answers null, junk follows the destination.
function readBodyAt(text, from) {
    var lead = skipGap(text, from)
    var dest = readDestinationAt(text, lead.at)
    if (dest === null)
        return null
    var gap = skipGap(text, dest.end)
    var close = gap.at > dest.end ? readTitleEnd(text, gap.at) : -1
    var titled = close >= 0 && endsLine(text, close)
    if (!titled && !endsLine(text, dest.end))
        return null
    return { target: dest.target, titled: titled, end: titled ? close : dest.end }
}

// Sample input: lines "[Foo\n  bar]: /url\n'a\nb'" answer { key: "foo bar", titled: true, end: 3 }; "[a]: /u x" answers null.
function definitionAt(lines, from) {
    var stop = from + 1
    while (stop < lines.length && lines[stop].trim().length > 0 && !Container.startsBlock(lines[stop]))
        stop++
    var text = lines.slice(from, stop).join("\n")
    var indent = 0
    while (indent < MAX_INDENT && text.charAt(indent) === " ")
        indent++
    var label = Link.readLabelRef(text, indent)
    if (label === null || label.label.trim().length === 0 || label.label.charAt(0) === "^" || text.charAt(label.end) !== ":")
        return null
    var body = readBodyAt(text, label.end + 1)
    if (body === null)
        return null
    // A title that does not close its own line is dropped when it sits on the next line, and spoils the definition when it follows the destination.
    return { key: Link.normalizeLabel(label.label), target: body.target, titled: body.titled,
        end: from + text.slice(0, body.end).split("\n").length - 1 }
}

// Sample input: '    > "t"' under frames list (contentCol 4) then quote answers '"t"'; '"t"' with no indent stays a lazy continuation; a line that opens its own quote answers null.
function replayed(line, frames) {
    var view = { at: 0, padding: 0, column: 0 }
    for (var f = 0; f < frames.length; f++) {
        var quote = Container.quoteAt(line, view)
        if (frames[f].type === "quote" && quote >= 0)
            Container.takeQuote(line, view, quote)
        else if (frames[f].type === "list" && Container.indentationAt(line, view, frames[f].contentCol).width >= frames[f].contentCol)
            Container.takeIndent(line, view, frames[f].contentCol)
        else
            break
    }
    return Container.quoteAt(line, view) >= 0 ? null : Container.textAt(line, view)
}

// Sample input: lines "'a" over "b'" at 0 with no frames answer 1, the line that closes the title; "'open" with no closer, or junk after it, answers -1.
function titleEnd(lines, at, frames) {
    var first = at < lines.length ? replayed(lines[at], frames) : null
    var open = first === null ? "" : first.trim().charAt(0)
    if (open !== "\"" && open !== "'" && open !== "(")
        return -1
    var close = open === "(" ? ")" : open
    for (var k = at; k < lines.length; k++) {
        var text = replayed(lines[k], frames)
        if (text === null || text.trim().length === 0)
            return -1
        for (var c = k === at ? text.indexOf(open) + 1 : 0; c < text.length; c++) {
            if (text.charAt(c) === "\\")
                c++
            else if (text.charAt(c) === close)
                return text.slice(c + 1).trim().length === 0 ? k : -1
        }
    }
    return -1
}

// The first definition of a label wins.
function storeDefinition(defs, key, target) {
    if (!hasOwn.call(defs, key))
        defs[key] = target
}

// A title on the lines after a finished definition belongs to it: its lines hide with the definition; allowed says it has none yet, frames are its containers.
function hideTitle(lines, from, state, allowed, frames) {
    var end = allowed ? titleEnd(lines, from, frames) : -1
    if (end < 0)
        return
    for (var k = from; k <= end; k++)
        state.hidden[k] = true
    state.dropped.push([from, end])
}

// Sample: [^id]: note body; the block reader supplies any indented continuation lines.
function readFootnoteDefinition(line) {
    var match = /^ {0,3}\[\^([^\]\n]+)\]:\s*(.*)$/.exec(line)
    return match === null ? null : { id: match[1], text: match[2] }
}

// Escape a definition-shaped leaf refused by the block reader before handing it to md4c.
function killDefinition(line) {
    if (!/^ {0,3}\[(?:\\.|[^\[\]\\\n])+\]:/.test(line))
        return line
    var at = line.indexOf("[")
    return line.slice(0, at) + "\\[" + line.slice(at + 1)
}

// Sample input: "[^note]" at its "[" yields id "note" and the index after "]".
function readFootnoteRef(text, i) {
    var j = i + 2
    while (j < text.length && text.charAt(j) !== "]" && text.charAt(j) !== "\n")
        j++
    if (j >= text.length || text.charAt(j) !== "]" || j === i + 2)
        return null
    return { id: text.slice(i + 2, j), end: j + 1 }
}


// Skip DROP_CONTENT bodies with same-name nesting; share the dead-tag flag to keep unmatched runs linear.
function skipDropContent(body, i, name, dead) {
    var depth = 1
    while (i < body.length && depth > 0) {
        var o = body.indexOf("<", i)
        if (o < 0)
            return body.length
        var inner = MdHtml.readTag(body, o, dead)
        if (inner === null) {
            i = o + 1
            continue
        }
        var head = MdHtml.tagHead(inner.tag)
        if (head.name === name) {
            if (head.closing)
                depth--
            else if (!head.selfClose)
                depth++
        }
        i = inner.end
    }
    return i
}

// Sample input: lines 2 to 3 hide both and record the span as dropped, so no line of the definition reaches the renderer.
function hideDefinition(state, from, to) {
    for (var i = from; i <= to; i++)
        state.hidden[i] = true
    state.dropped.push([from, to])
}
