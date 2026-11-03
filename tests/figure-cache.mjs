// Pin the QML cache-key functions to the reference the worker used to carry, including both layouts of one source.
import { argv, finish, readText, resolve, absolute } from "./js-runtime.mjs";

const tree = absolute(argv[0] || ".");
// The reference cache-key recipe the worker carried until 0.3.9 made it test-only: FNV-1a over the table text, then the theme key, then the kind key.
const HEX_RADIX = 16;
const FNV_OFFSET = 0x811c9dc5;
const FNV_PRIME = 0x01000193;
function tableDigest(table) {
    if (!table || table.length === 0)
        return "0";
    var text = table.join(",");
    var hash = FNV_OFFSET;
    for (var i = 0; i < text.length; i++)
        hash = Math.imul(hash ^ text.charCodeAt(i), FNV_PRIME);
    return (hash >>> 0).toString(HEX_RADIX);
}
function themeKey(t) {
    return [t.bg, t.fg, t.accent || "", t.muted || "", t.line || "", t.surface || "",
        t.border || "", t.font || "", t.bodyPx || 0, t.exPx || 0, tableDigest(t.advances), tableDigest(t.boldAdvances)].join("|");
}
function cacheKey(kind, source, t, display) {
    return kind + "\n" + themeKey(t) + "\n" + !!display + "\n" + source;
}
const service = readText(resolve(tree, "ui/FigureService.qml"));
// Sample input: function name(a, b) { body with { nested } braces } answers the text between the outer braces.
function functionBody(source, name) {
    const at = source.indexOf("function " + name + "(");
    if (at < 0)
        throw new Error("FigureService function " + name + " is missing");
    const open = source.indexOf("{", at);
    let depth = 0;
    for (let i = open; i < source.length; i++) {
        depth += source[i] === "{" ? 1 : source[i] === "}" ? -1 : 0;
        if (depth === 0)
            return source.slice(open + 1, i);
    }
    throw new Error("FigureService function " + name + " does not close");
}
const digestOf = new Function("table", functionBody(service, "tableDigestOf"));
const qmlKeyOf = new Function("root", "kind", "source", "t", "display", functionBody(service, "cacheKeyOf"));
const qmlKey = (kind, source, t, display) => qmlKeyOf({ tableDigestOf: digestOf }, kind, source, t, display);
// A printable ASCII advance table in thousandths of an em, 95 entries, and the same table with one entry changed.
const TABLE_LENGTH = 95;
const table = Array.from({ length: TABLE_LENGTH }, (unused, i) => 500 + (i % 7) * 20);
const nudged = table.map((v, i) => (i === TABLE_LENGTH - 1 ? v + 1 : v));
const themes = [{ bg: "#101315", fg: "#c0caf5", accent: "#7aa2f7", font: "monospace", bodyPx: 14, exPx: 7.7, advances: table, boldAdvances: table },
    { bg: "#fff", fg: "#000" }];
// The key stands a table in by a short digest, so a request's key stays far shorter than the table's text.
const DIGEST_LENGTH_MAX = 8;
let checks = 0;
let failures = 0;
function check(ok, why) {
    checks++;
    if (!ok) {
        failures++;
        console.log("FAIL " + why);
    }
}
for (const theme of themes) {
    for (const display of [false, true])
        check(qmlKey("math", "x^2", theme, display) === cacheKey("math", "x^2", theme, display), "service and reference agree on a formula key");
    check(qmlKey("math", "x^2", theme, false) !== qmlKey("math", "x^2", theme, true), "one source has separate inline and display cache keys");
    for (const role of ["bg", "fg", "accent", "muted", "line", "surface", "border", "font", "bodyPx", "exPx", "advances", "boldAdvances"]) {
        const value = role === "advances" || role === "boldAdvances" ? nudged : ["bodyPx", "exPx"].includes(role) ? 20 : "changed " + role;
        const changed = { ...theme, [role]: value };
        check(qmlKey("mermaid", "A --> B", theme, true) !== qmlKey("mermaid", "A --> B", changed, true), "service cache key includes theme role " + role);
        check(qmlKey("mermaid", "A --> B", changed, true) === cacheKey("mermaid", "A --> B", changed, true), "service and reference agree on theme role " + role);
    }
}
check(tableDigest(table).length <= DIGEST_LENGTH_MAX && digestOf(table) === tableDigest(table), "the service digest is the reference, " + tableDigest(table));
check(digestOf(table) !== digestOf(nudged) && digestOf([]) === digestOf(undefined), "one changed entry changes the service digest, and no table digests as none");
console.log(`figure-cache: ${checks} check(s), ${failures} failed`);
finish(failures);
