#!/usr/bin/env bash
# Live search against target/debug/flea in the sandbox root, its sends and replies replayed in qml6 through the real Focus/Search/Swap route; fails on a FAIL line, a missing DONE, or noise.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qml6 >/dev/null || { echo "search-live.sh: qml6 is not installed, cannot replay the session"; exit 1; }
command -v python3 >/dev/null || { echo "search-live.sh: python3 is not installed, cannot check the wire"; exit 1; }
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "search-live.sh: build the backend first: $bin"; exit 1; }

fixture="$FIXTURE_ROOT/search-live-$$"
sandbox_make "$fixture"
cleanup() { sandbox_remove "$fixture"; }
trap cleanup EXIT

scope="$fixture/scope"
mkdir -p "$scope/docs" "$scope/sub" || exit 1
touch "$scope/notes.md" "$scope/north.txt" "$scope/docs/notes-old.md" \
    "$scope/sub/photo.png" "$scope/sub/todo.txt" "$scope/sub/music.mp3" "$scope/sub/archive.zip" || exit 1
folder="$scope/sub"

transcript="$fixture/transcript"
{
send() { printf '%s\n' "$1" | tee -a "$fixture/sends"; sleep 0.8; }
# The sends follow the python plan below; Tab flips the scope twice so the reveal still has the scope above the folder, and its own leaveWalk closes the session on wire.
send "{\"c\":\"searchopen\",\"path\":\"$scope\",\"folder\":\"$folder\",\"hidden\":false}"
sleep 0.4
send "{\"c\":\"searchquery\",\"query\":\"n\",\"gen\":1,\"count\":200}"
send "{\"c\":\"searchquery\",\"query\":\"no\",\"gen\":2,\"count\":200}"
send "{\"c\":\"searchquery\",\"query\":\"n\",\"gen\":3,\"count\":200}"
send "{\"c\":\"searchquery\",\"query\":\"\",\"gen\":4,\"count\":200}"
send "{\"c\":\"searchquery\",\"query\":\"q\",\"gen\":5,\"count\":200}"
send "{\"c\":\"searchquery\",\"query\":\"\",\"gen\":6,\"count\":200}"
send "{\"c\":\"searchquery\",\"query\":\"n\",\"gen\":7,\"count\":200}"
send "{\"c\":\"searchopen\",\"path\":\"$folder\",\"folder\":\"$folder\",\"hidden\":false}"
send "{\"c\":\"searchquery\",\"query\":\"n\",\"gen\":8,\"count\":200}"
send "{\"c\":\"searchopen\",\"path\":\"$scope\",\"folder\":\"$folder\",\"hidden\":false}"
send "{\"c\":\"searchquery\",\"query\":\"n\",\"gen\":9,\"count\":200}"
send "{\"c\":\"searchclose\"}"
send "{\"c\":\"list\",\"path\":\"$folder\",\"first\":200,\"hidden\":false}"
send "{\"c\":\"searchopen\",\"path\":\"$scope\",\"folder\":\"$folder\",\"hidden\":false}"
sleep 0.4
send "{\"c\":\"searchquery\",\"query\":\"n\",\"gen\":10,\"count\":200}"
send "{\"c\":\"searchclose\"}"
sleep 0.5
echo '{"c":"quit"}'
sleep 0.5
} | timeout 60 "$bin" --backend >"$fixture/raw.log" 2>"$fixture/stderr.log" || { echo "search-live.sh: the backend exited nonzero"; cat "$fixture/stderr.log"; exit 1; }

# Sample input, one backend line in raw.log: {"t":"searched","n":4,"scanned":9,"ms":0.040,"cancelled":false,"gen":1,"walking":false}
python3 - "$fixture/sends" "$fixture/raw.log" "$scope" "$folder" "$transcript" <<'PYEOF'
import json, sys
sends_path, raw_path, scope, folder, transcript = sys.argv[1:6]
sends = [json.loads(l) for l in open(sends_path) if l.strip().startswith('{')]
received = [json.loads(l) for l in open(raw_path) if l.strip().startswith('{')]
fails = []
def check(label, actual, expected):
    if actual != expected:
        fails.append("%s: got %r, expected %r" % (label, actual, expected))
# The keystroke plan the qml replay types, with the send indices each keystroke owns; the reveal closes its session on the wire, so its key owns that close.
plan = [('f', [0]), ('n', [1]), ('o', [2]), ('Down', []), ('Up', []), ('Down', []),
        ('BS', [3]), ('BS', [4]), ('q', [5]), ('BS', [6]), ('n', [7]),
        ('Tab', [8, 9]), ('Tab', [10, 11]), ('Return', []), ('Down', []),
        ('Escape', [12, 13]), ('f', [14]), ('n', [15]), ('Return', []),
        ('Reveal', [16]), ('Escape', [])]
opens = [m for m in received if m.get('t') == 'searchopened']
check("four sessions open", [(m.get('path')) for m in opens], [scope, folder, scope, scope])
closes = [m for m in received if m.get('t') == 'searchclosed']
check("two closes answer, the tab rescope closing in silence", len(closes), 2)
sessions, current = [], None
for m in received:
    if m.get('t') == 'searchopened':
        current = []
        sessions.append(current)
    elif m.get('t') == 'searched' and current is not None:
        current.append(m)
terms = [m for s in sessions for m in s]
check("ten queries answer with their own generation",
      [(m.get('gen'), m.get('n')) for m in terms],
      [(1, 4), (2, 3), (3, 4), (4, 4), (5, 0), (6, 4), (7, 4), (8, 1), (9, 4), (10, 4)])
triples = []
for j, m in enumerate(received):
    if m.get('t') != 'searched':
        continue
    triples.append([received[j - 2].get('t'), received[j - 1].get('t'), m.get('t')])
check("every answer is listed, rows, searched", triples, [['listed', 'rows', 'searched']] * 10)
rows = [m for m in received if m.get('t') == 'rows']
listed = [m for m in received if m.get('t') == 'listed']
check("session listed and rows lines carry their query gen",
      [m.get('gen') for m in listed if 'gen' in m] + [m.get('gen') for m in rows if 'gen' in m],
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
check("the n query ranks notes first", [r['n'] for r in rows[0]['rows']],
      ['notes.md', 'north.txt', 'docs/notes-old.md', 'sub/photo.png'])
check("and no narrows it", [r['n'] for r in rows[1]['rows']],
      ['notes.md', 'north.txt', 'docs/notes-old.md'])
fourth = [j for j, m in enumerate(received) if m.get('t') == 'searched'][3]
check("an empty query answers the folder in its own order",
      (received[fourth - 2].get('path'), [r['n'] for r in received[fourth - 1]['rows']]),
      (folder, ['archive.zip', 'music.mp3', 'photo.png', 'todo.txt']))
check("a query with no match lands an honest empty window",
      (terms[4]['n'], rows[4]['rows']), (0, []))
relist = []
for j, m in enumerate(received):
    if m.get('t') == 'listed' and j + 2 < len(received) \
            and received[j + 1].get('t') == 'rows' and received[j + 2].get('t') != 'searched':
        relist.append(m)
check("the escape relist is one ordinary folder listing", [(m.get('n'), m.get('path')) for m in relist], [(4, folder)])
if fails:
    print("search-live.sh wire FAIL:")
    print('\n'.join(fails))
    sys.exit(1)
print("search-live.sh: wire ok, %d sends, %d replies" % (len(sends), len(received)))
queries = {}
seen_opens = 0
for j, m in enumerate(received):
    if m.get('t') == 'searchopened':
        seen_opens += 1
    if m.get('t') == 'searched':
        queries[(seen_opens, m.get('gen'))] = [received[j - 2], received[j - 1], m]
relist_pair = None
for j, m in enumerate(received):
    if m.get('t') == 'listed' and received[j + 1].get('t') == 'rows' and received[j + 2].get('t') != 'searched':
        relist_pair = [m, received[j + 1]]
opens_iter = iter([m for m in received if m.get('t') == 'searchopened'])
closes_iter = iter([m for m in received if m.get('t') == 'searchclosed'])
session_no = 0
with open(transcript, 'w') as f:
    for key, idxs in plan:
        f.write('# key %s\n' % key)
        for i in idxs:
            f.write('S %s\n' % json.dumps(sends[i], sort_keys=True))
            c = sends[i].get('c')
            if c == 'searchopen':
                session_no += 1
                f.write('R %s\n' % json.dumps(next(opens_iter), sort_keys=True))
            elif c == 'searchquery':
                for m in queries[(session_no, sends[i]['gen'])]:
                    f.write('R %s\n' % json.dumps(m, sort_keys=True))
            elif c == 'searchclose':
                f.write('R %s\n' % json.dumps(next(closes_iter), sort_keys=True))
            elif c == 'list':
                for m in relist_pair:
                    f.write('R %s\n' % json.dumps(m, sort_keys=True))
PYEOF
[ $? -eq 0 ] || exit 1
# Sample input, one backend line on the reader's stdin: {"t":"searched","n":3,"scanned":9,"ms":0.031,"cancelled":false,"gen":2,"walking":false}
dup=$( { sleep 0.5; echo "{\"c\":\"searchopen\",\"path\":\"$scope\",\"folder\":\"$folder\",\"hidden\":false}";
    sleep 1; echo "{\"c\":\"searchquery\",\"query\":\"n\",\"gen\":2,\"count\":200}";
    sleep 1; echo "{\"c\":\"searchquery\",\"query\":\"n\",\"gen\":2,\"count\":200}";
    sleep 1; echo '{"c":"quit"}'; sleep 0.5; } | timeout 30 "$bin" --backend 2>/dev/null \
    | python3 -c "import sys, json; ms=[json.loads(l) for l in sys.stdin]; print(sum(1 for m in ms if m.get('t')=='searched' and m.get('gen') == 2))" )
[ "$dup" = 1 ] || { echo "search-live.sh: duplicate gen answered $dup times, want 1"; exit 1; }
echo "search-live.sh: stale gen dropped"
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    QML_XHR_ALLOW_FILE_READ=1 timeout 120 qml6 tests/search-live.qml -- "$transcript" >"$fixture/qml.log" 2>&1
code=$?
if [ "$code" != 0 ]; then echo "search-live.sh: qml6 exited $code:"; cat "$fixture/qml.log"; exit 1; fi
if grep -a -qE '(^|[: ])FAIL[: ]' "$fixture/qml.log"; then grep -a -E '(^|[: ])FAIL[: ]' "$fixture/qml.log"; exit 1; fi
grep -a 'SEARCHLIVE DONE' "$fixture/qml.log" || { echo "search-live.sh: no DONE receipt:"; cat "$fixture/qml.log"; exit 1; }
if grep -a -iE 'warning|TypeError|ReferenceError' "$fixture/qml.log"; then echo "search-live.sh: warnings above"; exit 1; fi
