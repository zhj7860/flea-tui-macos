import QtQuick

// The counting half of the flingframe probe: pure functions over its snapshots, with no view and no clock.
QtObject {
    // A mean of whole counts is judged within this much of a whole number.
    readonly property real slack: 0.5
    // A mean of whole counts is held to its cap within this much.
    readonly property real capHair: 0.01
    readonly property var askKeys: ["thumb", "thumbcancel", "dirsize", "dirsizecancel", "window", "askMeta"]

    function pad(i) { var n = String(i); while (n.length < 5) n = "0" + n; return n }
    function rowsFor(count) {
        var out = []
        for (var i = 0; i < count; i++)
            out.push({ n: "f_" + pad(i) + ".txt", d: false, i: "text-plain", p: 420, s: i * 7, m: 1758835200 + i * 60, t: false, k: 0, v: 0 })
        return out
    }

    // Every string a delegate draws, in tree order, so a text that moved is a layout the frame paid.
    function textsOf(item, out) {
        if (typeof item.text === "string") out.push(item.text)
        var kids = item.children
        for (var i = 0; kids !== undefined && i < kids.length; i++) textsOf(kids[i], out)
        return out
    }

    function diff(a, b) {
        var rebound = 0, texts = 0
        b.at.forEach(function (now, cell) {
            var was = a.at.get(cell)
            if (!was) return
            if (now.live && (now.index !== was.index || !was.live)) rebound += 1
            if (now.live && now.texts !== was.texts) texts += 1
        })
        var t = {}
        for (var k in b.tally) t[k] = b.tally[k] - a.tally[k]
        return { created: b.created - a.created, destroyed: b.destroyed - a.destroyed, rebound: rebound, texts: texts, tally: t }
    }

    function flat(d) {
        var m = { created: d.created, destroyed: d.destroyed, rebound: d.rebound, texts: d.texts }
        for (var k in d.tally) m[k] = d.tally[k]
        return m
    }

    function means(list) {
        var out = {}, keys = Object.keys(flat(list[0]))
        for (var k = 0; k < keys.length; k++) {
            var sum = 0
            for (var i = 0; i < list.length; i++) sum += flat(list[i])[keys[k]]
            out[keys[k]] = sum / list.length
        }
        return out
    }

    // A frame does the work of the rows entering and nothing else: no backend ask, no build once the pool is full, no read or rebind of a row that stayed. per is the most rows that may enter and clamps the most clamp signals (one per scroll write) the frame may raise. The product's clamp handler writes the cursor on each clamp it raises, in the same call, so the cursor moves at most once per clamp.
    function judge(tag, m, per, poolFull, clamps) {
        var out = [], asks = 0
        for (var a = 0; a < askKeys.length; a++) asks += m[askKeys[a]]
        if (asks > 0) out.push(tag + asks.toFixed(2) + " backend asks a frame, want 0")
        if (poolFull && m.created > 0) out.push(tag + m.created.toFixed(2) + " delegates built a frame, want 0")
        if (m.rebound > per + slack) out.push(tag + m.rebound.toFixed(2) + " rows rebound a frame, want at most " + per)
        // A row built or rebound is a row entering; a read past that is a row that stayed.
        var entering = m.rebound + m.created
        if (m.texts > entering + slack) out.push(tag + m.texts.toFixed(2) + " rows changed text a frame, entering " + entering.toFixed(2))
        if (m.rowFor > 2 * entering + slack) out.push(tag + m.rowFor.toFixed(2) + " row reads a frame, entering " + entering.toFixed(2))
        if (m.isSelected > entering + slack) out.push(tag + m.isSelected.toFixed(2) + " selection reads a frame, entering " + entering.toFixed(2))
        if (m.cursor > m.clamped + capHair || m.clamped > clamps + capHair) out.push(tag + "cursor moved " + m.cursor.toFixed(2) + " and clamped " + m.clamped.toFixed(2) + " a frame, want at most one move per clamp and " + clamps + " clamps")
        return out
    }
}
