#!/usr/bin/env bash
# tools/flea-mpris on a private session bus: fed state lines it owns an MPRIS name, and a media key's calls reach stdout as command lines.
set -u
set -o pipefail
# Hard rule 9's guard, which owns FIXTURE_ROOT and every create and delete this suite makes.
. "$(dirname "$0")/../tools/flea-sandbox-guard"

root=$(cd "$(dirname "$0")/.." && pwd)
helper="$root/tools/flea-mpris"
fixture="$FIXTURE_ROOT/flea-mpris-$$"
object=/org/mpris/MediaPlayer2
bus_pid=0
helper_pid=0
monitor_pid=0
failed=0

pass() { printf 'PASS %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*"; failed=$((failed + 1)); }

for tool in dbus-daemon gdbus python3; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'FAIL %s is not installed, so nothing below was run\n' "$tool"; exit 1; }
done
python3 -c 'import gi' 2>/dev/null || { printf 'FAIL python3 has no gi module, so nothing below was run\n'; exit 1; }

stop_helper() {
    exec 3>&-
    if [[ "$helper_pid" != 0 ]] && kill -0 "$helper_pid" 2>/dev/null; then
        kill "$helper_pid" 2>/dev/null
        wait "$helper_pid" 2>/dev/null
    fi
    helper_pid=0
}

cleanup() {
    stop_helper
    [[ "$monitor_pid" != 0 ]] && kill "$monitor_pid" 2>/dev/null
    if [[ "$bus_pid" != 0 ]] && kill -0 "$bus_pid" 2>/dev/null; then
        kill "$bus_pid" 2>/dev/null
        wait "$bus_pid" 2>/dev/null
    fi
    sandbox_remove "$fixture"
}
trap cleanup EXIT

# The bus listens inside the fixture, so nothing registers on the real session bus; the first case is the negative control, a helper never fed owns no name.
sandbox_make "$fixture"
cat > "$fixture/bus.conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:path=$fixture/bus</listen>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
CONF
dbus-daemon --config-file="$fixture/bus.conf" --fork --print-pid=3 3>"$fixture/bus.pid" \
    || { printf 'FAIL the private bus would not start\n'; exit 1; }
bus_pid=$(cat "$fixture/bus.pid")
export DBUS_SESSION_BUS_ADDRESS="unix:path=$fixture/bus"

name() { printf 'org.mpris.MediaPlayer2.flea.instance%s' "$helper_pid"; }

# Every name on the bus that belongs to an MPRIS player.
players() { gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ListNames | grep -o "org.mpris.MediaPlayer2[A-Za-z0-9_.]*"; }

wait_until() {
    local step
    for step in $(seq 1 40); do
        "$@" && return 0
        sleep 0.1
    done
    return 1
}

named() { players | grep -qxF "$(name)"; }
unnamed() { ! players | grep -qxF "$(name)"; }
helper_gone() { ! kill -0 "$helper_pid" 2>/dev/null; }
logged() { [[ "$(wc -l < "$1" | tr -d ' ')" -ge "$2" ]]; }

# Prints the bare value of one property, e.g. "'Flea'" or "int64 2500000".
get() {
    gdbus call --session --dest "$(name)" --object-path "$object" --method org.freedesktop.DBus.Properties.Get "$1" "$2" \
        | sed -e 's/^(<//' -e 's/>,)$//'
}

call() { gdbus call --session --dest "$(name)" --object-path "$object" --method "org.mpris.MediaPlayer2.Player.$1" "${@:2}" >/dev/null; }

feed() { printf '%s\n' "$1" >&3; }

start_helper() {
    rm -f "$fixture/in"
    mkfifo "$fixture/in"
    : > "$fixture/out"
    "$helper" < "$fixture/in" > "$fixture/out" 2> "$fixture/err" &
    helper_pid=$!
    exec 3> "$fixture/in"
}

start_helper
sleep 0.5
if players | grep -q 'flea'; then
    fail "silent: a helper that was fed nothing owns a name"
else
    pass "silent: a helper that was fed nothing owns no name"
fi

feed '{"status":"Playing","title":"clip.mp4","url":"file:///tmp/clip.mp4","length":6000,"position":1000}'
if wait_until named; then
    pass "name: org.mpris.MediaPlayer2.flea.instance<pid> appeared on the first line"
else
    fail "name: nothing appeared after the first state line"
    cat "$fixture/err"
    exit 1
fi

root_ok=1
[[ "$(get org.mpris.MediaPlayer2 Identity)" == "'Flea'" ]] || root_ok=0
[[ "$(get org.mpris.MediaPlayer2 DesktopEntry)" == "'com.thisisgm.flea'" ]] || root_ok=0
[[ "$(get org.mpris.MediaPlayer2 CanQuit)" == false ]] || root_ok=0
[[ "$(get org.mpris.MediaPlayer2 CanRaise)" == false ]] || root_ok=0
if [[ "$root_ok" == 1 ]]; then
    pass "root: Identity Flea, DesktopEntry com.thisisgm.flea, CanQuit and CanRaise false"
else
    fail "root: the org.mpris.MediaPlayer2 properties differ from the contract"
fi

caps_ok=1
for cap in CanPlay CanPause CanSeek CanControl; do
    [[ "$(get org.mpris.MediaPlayer2.Player "$cap")" == true ]] || caps_ok=0
done
for cap in CanGoNext CanGoPrevious; do
    [[ "$(get org.mpris.MediaPlayer2.Player "$cap")" == false ]] || caps_ok=0
done
if [[ "$caps_ok" == 1 ]]; then
    pass "caps: CanPlay, CanPause, CanSeek and CanControl true; CanGoNext and CanGoPrevious false"
else
    fail "caps: a Can* property differs from the contract"
fi

[[ "$(get org.mpris.MediaPlayer2.Player PlaybackStatus)" == "'Playing'" ]] \
    && pass "status: PlaybackStatus reads Playing as fed" || fail "status: PlaybackStatus is not Playing"

meta=$(get org.mpris.MediaPlayer2.Player Metadata)
meta_ok=1
for part in "'xesam:title': <'clip.mp4'>" "'xesam:url': <'file:///tmp/clip.mp4'>" "'mpris:length': <int64 6000000>" "'mpris:trackid': <objectpath '/com/thisisgm/flea/track/"; do
    [[ "$meta" == *"$part"* ]] || { meta_ok=0; printf '  metadata lacks %s in %s\n' "$part" "$meta"; }
done
[[ "$meta_ok" == 1 ]] && pass "metadata: trackid, length, title and url read as fed" || fail "metadata: a key differs from the line fed"

# Playing, so the position is the line's plus the time since, which only ever grows.
first=$(get org.mpris.MediaPlayer2.Player Position | sed 's/int64 //')
sleep 0.4
second=$(get org.mpris.MediaPlayer2.Player Position | sed 's/int64 //')
if [[ "$first" -ge 1000000 && "$second" -gt "$first" ]]; then
    pass "position: while playing it starts at the fed 1000 ms and advances with the clock"
else
    fail "position: while playing it read $first then $second"
fi

# A watcher on the name, started before the status changes it reports.
gdbus monitor --session --dest "$(name)" > "$fixture/monitor.log" 2>&1 &
monitor_pid=$!
sleep 0.5
feed '{"status":"Paused","title":"clip.mp4","url":"file:///tmp/clip.mp4","length":6000,"position":2500}'
if wait_until grep -q "PlaybackStatus.*Paused" "$fixture/monitor.log"; then
    pass "changed: a status change emitted PropertiesChanged naming Paused"
else
    fail "changed: no PropertiesChanged followed the status change"
fi
sleep 0.4
if [[ "$(get org.mpris.MediaPlayer2.Player Position)" == "int64 2500000" ]]; then
    pass "position: paused, it holds the fed 2500 ms"
else
    fail "position: paused, it read $(get org.mpris.MediaPlayer2.Player Position), not int64 2500000"
fi

feed '{"status":"Paused","title":"clip.mp4","url":"file:///tmp/clip.mp4","length":6000,"position":4000,"seeked":true}'
if wait_until grep -q "Seeked.*4000000" "$fixture/monitor.log"; then
    pass "seeked: a seek line emitted Seeked at 4000000 microseconds"
else
    fail "seeked: no Seeked signal followed the seek line"
fi
kill "$monitor_pid" 2>/dev/null
monitor_pid=0

trackid=$(printf '%s' "$meta" | grep -o "/com/thisisgm/flea/track/[0-9]*")
call PlayPause
call Seek 2500000
call SetPosition "$trackid" 3000000
call SetPosition /com/thisisgm/flea/track/0 9000000
call Pause
wait_until logged "$fixture/out" 4
if [[ "$(cat "$fixture/out")" == $'PlayPause\nSeek 2500\nSetPosition 3000\nPause' ]]; then
    pass "commands: PlayPause, Seek and SetPosition arrive as one line each, and a foreign track id is ignored"
else
    fail "commands: stdout read $(tr '\n' '|' < "$fixture/out")"
fi

printf 'not json\n' >&3
feed '{"status":"Nonsense"}'
sleep 0.3
if kill -0 "$helper_pid" 2>/dev/null && [[ "$(get org.mpris.MediaPlayer2.Player PlaybackStatus)" == "'Paused'" ]]; then
    pass "refused: a bad line and an unknown status leave the player as it was"
else
    fail "refused: a bad line ended or changed the player"
fi

exec 3>&-
if wait_until helper_gone && wait_until unnamed; then
    pass "eof: closing stdin ended the helper and released the name"
else
    fail "eof: the helper or its name outlived its stdin"
fi
helper_pid=0

printf 'mpris: %d failure(s)\n' "$failed"
exit "$failed"
