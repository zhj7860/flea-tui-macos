#!/usr/bin/env python3
"""Exercise the actual capture runner and Trash teardown with isolated process groups."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

POLL_S = 0.02
TICK_POLL_S = 0.002
NEAR_TICK_S = 0.95
NEAR_TICK_MIN_S = 0.90
GRACE_MAX_S = 2.5
COOPERATIVE_STOP_MAX_S = 0.8
READINESS_FAILURE_WAIT_S = 0.2
SENTINEL_LIFETIME_S = 60

repo, parent, marker = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
if not parent.is_absolute() or not (parent / marker).is_file():
    raise SystemExit("FAIL capture-lifecycle: missing absolute owned fixture root")
root = Path(tempfile.mkdtemp(prefix="lifecycle-", dir=parent))
(root / marker).touch()
checks = 0
failed = 0


def check(ok, name, detail=""):
    global checks, failed
    checks += 1
    failed += not ok
    print(f"{'CAPTURELIFECYCLE PASS' if ok else 'FAIL capture-lifecycle'} {name}: {detail}", flush=True)


def await_condition(condition, seconds=3):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if condition():
            return True
        time.sleep(POLL_S)
    return condition()


def running(pid):
    try:
        # Sample stat: '123 (sleep helper) S 1 123 123 ...'; state follows the final closing parenthesis.
        return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0] != "Z"
    except FileNotFoundError:
        return False


def members(group):
    found = []
    for path in Path("/proc").iterdir():
        if path.name.isdigit():
            try:
                if os.getpgid(int(path.name)) == group and running(int(path.name)):
                    found.append(int(path.name))
            except ProcessLookupError:
                pass
    return found


def send_group(group, sig):
    assert group > 1 and group != os.getpgrp(), "refusing own or invalid process group"
    try:
        os.killpg(group, sig)
    except ProcessLookupError:
        pass


def stop(process):
    force_stop_session(process)


def session_groups(process):
    # start_new_session makes the launched PID its SID; every matching group belongs to that owned session.
    groups = set()
    for path in Path("/proc").iterdir():
        if path.name.isdigit():
            try:
                pid = int(path.name)
                if os.getsid(pid) == process.pid and running(pid):
                    groups.add(os.getpgid(pid))
            except (ProcessLookupError, PermissionError):
                pass
    return groups


def force_stop_session(process):
    send_group(process.pid, signal.SIGKILL)
    process.wait(timeout=3)
    def stopped():
        groups = session_groups(process)
        for group in groups:
            send_group(group, signal.SIGKILL)
        return not groups
    assert await_condition(stopped), "owned session groups survived forced cleanup"


def launch(script, case, *args, env=None):
    with (case / "runner.log").open("w") as log:
        return subprocess.Popen(["bash", str(script), str(case), *args], stdout=log,
                                stderr=subprocess.STDOUT, start_new_session=True, env=env)


source = subprocess.run(["bash", "-c", '. "$1/tests/ui-captures-cohesion.sh"; '
                         'declare -f coh_bounded coh_surface_work coh_release_held', "bash", str(repo)],
                        env={**os.environ, "repo": str(repo)}, capture_output=True, text=True, check=True).stdout
actual = root / "actual.sh"
actual.write_text(source)
runner = root / "signal-runner.sh"
runner.write_text('''set -u
case_root=$1
. "$(dirname "$0")/actual.sh"
coh_theme=signal-proof coh_budget_s=60 coh_teardown_s=1 coh_poll_s=0.02 coh_usec_per_s=1000000
coh_deadline=$((SECONDS + 60))
coh_held=0
child_disposition=${2:-ignore}
tick_poll_s=''' + str(TICK_POLL_S) + '''
kill() {
    case "$1" in -TERM|-KILL) printf '%s %s %s\\n' "$1" "$SECONDS" "$EPOCHREALTIME" >> "$case_root/signals" ;; esac
    builtin kill "$@"
}
coh_ydotool() {
    printf 'RELEASE_BEGIN\\n'
    command sleep 0.1
    printf '%s\\n' "$*" >> "$case_root/release"
    printf 'RELEASE_DONE\\n'
}
trap 'printf "ORIGINAL HUP\\n"; exit 129' HUP
trap 'printf "ORIGINAL INT\\n"; exit 130' INT
trap 'printf "ORIGINAL TERM\\n"; exit 143' TERM
publish_ready() {
    if [[ "$child_disposition" == partial-publication ]]; then
        : > "$case_root/publication-open"
        until [[ -f "$case_root/publication-continue" ]]; do
            (( SECONDS < coh_deadline )) || return 1
            command sleep "$tick_poll_s"
        done
    fi
    printf '%s %s\\n' "$SECONDS" "$EPOCHREALTIME"
}
coh_run_surface() {
    set -x
    coh_held=1
    printf '%s\\n' "$BASHPID" > "$case_root/worker.pid"
    bash -c '[[ "$2" != ignore ]] || trap "" TERM; printf "%s\\n" "$BASHPID" > "$1"; exec sleep 60' bash "$case_root/child.pid" "$child_disposition" &
    local child=$!
    while [[ ! -s "$case_root/child.pid" ]]; do command sleep 0.01; done
    if [[ "$child_disposition" != not-ready ]]; then
        set +x
        local tick=$SECONDS
        while (( SECONDS == tick )); do command sleep "$tick_poll_s"; done
        publish_ready > "$case_root/ready.pending"
        mv -- "$case_root/ready.pending" "$case_root/ready"
        set -x
    fi
    wait "$child"
}
coh_bounded signal 60 coh_surface_work
printf 'UNEXPECTED_RETURN %s\\n' "$?"
''')

case = root / "partial-publication"
case.mkdir()
(case / marker).touch()
sentinel = process = None
try:
    sentinel = subprocess.Popen(["sleep", str(SENTINEL_LIFETIME_S)], start_new_session=True)
    process = launch(runner, case, "partial-publication")
    assert await_condition(lambda: (case / "publication-open").exists()), "publisher never paused after opening its output"
    try:
        exposed = (case / "ready").exists()
        if exposed:
            # Sample ready: '1 1792005217.002345\n' contains SECONDS and EPOCHREALTIME, separated by one space.
            tick_seconds, tick_at = (case / "ready").read_text().split()
        detail = f"ready exists={exposed} while timestamp printf is gated"
    except ValueError as error:
        detail = str(error)
    check(not exposed, "partial publication hides the incomplete readiness record", detail)
    (case / "publication-continue").touch()
    assert await_condition(lambda: (case / "ready").exists() and (case / "ready").read_text().endswith("\n")), "publisher never completed readiness"
    # Sample ready: '1 1792005217.002345\n' contains SECONDS and EPOCHREALTIME, separated by one space.
    tick_seconds, tick_at = (case / "ready").read_text().split()
    check(int(tick_seconds) >= 0 and float(tick_at) > 0,
          "partial publication exposes the complete timestamp after release", f"record={tick_seconds} {tick_at}")
    discovered = session_groups(process)
    stop(process)
    check(not any(members(group) for group in discovered), "partial publication cleanup removes owned groups")
    check(sentinel.poll() is None, "partial publication cleanup leaves unrelated sentinel alive")
except Exception as error:
    check(False, "partial publication probe completed", str(error))
finally:
    try:
        if process is not None:
            stop(process)
    finally:
        if sentinel is not None:
            stop(sentinel)

signal_cases = [(sig, target, "ignore") for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)
                for target in ("pid", "group")]
signal_cases.append((signal.SIGTERM, "pid", "cooperative"))
for sig, target, disposition in signal_cases:
    label = f"{sig.name}/{target}/{disposition}"
    case = root / f"{sig.name}-{target}-{disposition}"
    case.mkdir()
    (case / marker).touch()
    sentinel = subprocess.Popen(["sleep", "60"], start_new_session=True)
    process = launch(runner, case, disposition)
    groups = []
    try:
        ready = await_condition(lambda: (case / "ready").exists() or process.poll() is not None)
        assert ready and (case / "ready").exists(), "surface did not become ready"
        worker = int((case / "worker.pid").read_text())
        child = int((case / "child.pid").read_text())
        def children_ready():
            # Sample children: '123 124 ' lists decimal child PIDs separated by whitespace.
            children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
            groups[:] = [int(pid) for pid in children]
            return len(groups) == 2
        assert await_condition(children_ready), "worker/watchdog groups unavailable"
        assert worker in groups and all(os.getpgid(pid) == pid for pid in groups), "groups are not owned children"
        check(os.getpgid(child) == worker, f"{label} descendant belongs to the worker")
        # Sample ready: '1 1792005217.002345\n' contains SECONDS and EPOCHREALTIME, separated by one space.
        tick_seconds, tick_at = (case / "ready").read_text().split()
        target_at = float(tick_at) + NEAR_TICK_S
        while time.time() < target_at:
            time.sleep(min(POLL_S, max(0.0, target_at - time.time())))
        sent_at = time.monotonic()
        if target == "pid":
            os.kill(process.pid, sig)
        else:
            send_group(process.pid, sig)
        stopped = await_condition(lambda: not any(members(group) for group in groups))
        status = process.wait(timeout=3)
        elapsed = time.monotonic() - sent_at
        released = (case / "release").read_text().splitlines() if (case / "release").exists() else []
        log = (case / "runner.log").read_text()
        if not stopped or released != ["click 0x80"]:
            print(f"CAPTURELIFECYCLE TRACE {label}\n{log}", flush=True)
        # Sample signals: '-TERM 1 1792005217.952345\n-KILL 2 1792005218.965432\n' records signal, SECONDS and EPOCHREALTIME.
        signals = [line.split() for line in (case / "signals").read_text().splitlines()]
        term = next(row for row in signals if row[0] == "-TERM")
        kill_at = next((float(row[2]) for row in signals if row[0] == "-KILL"), None)
        near_tick = int(term[1]) == int(tick_seconds) and NEAR_TICK_MIN_S <= float(term[2]) - float(tick_at) < 1
        check(near_tick, f"{label} signal lands near the runner's actual SECONDS tick",
              f"tick={tick_at} TERM={term[2]} seconds={tick_seconds}/{term[1]}")
        if disposition == "ignore":
            grace = kill_at - float(term[2]) if kill_at is not None else 0
            check(1 <= grace < GRACE_MAX_S, f"{label} KILL follows a full bounded one-second grace", f"seconds={grace:.6f}")
        else:
            check(kill_at is None and elapsed < COOPERATIVE_STOP_MAX_S, f"{label} stopped groups skip the remaining grace",
                  f"seconds={elapsed:.6f} KILL={kill_at}")
        check(stopped, f"{label} worker and watchdog descendants stop", f"remaining={[members(g) for g in groups]}")
        check(released == ["click 0x80"], f"{label} held button releases once", str(released))
        check(status == 128 + sig and f"ORIGINAL {sig.name[3:]}" in log,
              f"{label} original caller trap runs after cleanup", f"exit={status}")
        check(sentinel.poll() is None, f"{label} unrelated process survives")
    except Exception as error:
        check(False, f"{label} probe completed", str(error))
    finally:
        for group in groups:
            send_group(group, signal.SIGKILL)
        stop(process)
        stop(sentinel)

case = root / "not-ready"
case.mkdir()
(case / marker).touch()
sentinel = subprocess.Popen(["sleep", "60"], start_new_session=True)
process = launch(runner, case, "not-ready")
try:
    assert await_condition(lambda: (case / "child.pid").exists()), "unready surface never spawned"
    assert await_condition(lambda: len(session_groups(process) - {process.pid}) == 2), "unready groups never spawned"
    discovered = session_groups(process) - {process.pid}
    ready = await_condition(lambda: (case / "ready").exists(), READINESS_FAILURE_WAIT_S)
    check(not ready, "readiness failure control actually times out before group registration")
    stop(process)
    check(not any(members(group) for group in discovered), "readiness failure cleanup removes undiscovered owned groups",
          f"groups={sorted(discovered)} remaining={[members(g) for g in discovered]}")
    check(sentinel.poll() is None, "readiness failure cleanup leaves unrelated sentinel alive")
except Exception as error:
    check(False, "readiness failure probe completed", str(error))
finally:
    force_stop_session(process)
    stop(sentinel)

normal = root / "normal-runner.sh"
normal.write_text('''set -u
case_root=$1
. "$(dirname "$0")/actual.sh"
coh_theme=normal-proof coh_budget_s=60 coh_teardown_s=1 coh_poll_s=0.02 coh_usec_per_s=1000000
coh_deadline=$((SECONDS + 60))
trap 'printf "ORIGINAL HUP\\n"' HUP
trap 'printf "ORIGINAL INT\\n"' INT
trap 'printf "ORIGINAL TERM\\n"' TERM
trap 'printf "ORIGINAL EXIT\\n"' EXIT
[[ "$2" != monitor ]] || set -m
before=$(trap -p HUP INT TERM EXIT)
before_options=$-
case "$3" in
    success) coh_bounded normal 1 true ;;
    failed) coh_bounded normal 1 bash -c 'exit 7' ;;
    timeout) coh_bounded normal 1 command sleep 60 ;;
esac
status=$?
[[ "$(trap -p HUP INT TERM EXIT)" == "$before" && "$-" == "$before_options" ]] || exit 9
for signal in HUP INT TERM; do kill -"$signal" "$BASHPID"; done
printf 'RETURN %s RESTORED\\n' "$status"
''')
for monitor in ("plain", "monitor"):
    for kind, expected in (("success", 0), ("failed", 7), ("timeout", 124)):
        case = root / f"normal-{monitor}-{kind}"
        case.mkdir()
        (case / marker).touch()
        process = launch(normal, case, monitor, kind)
        try:
            status = process.wait(timeout=5)
            log = (case / "runner.log").read_text()
            check(status == 0 and f"RETURN {expected} RESTORED" in log and
                  all(f"ORIGINAL {name}" in log for name in ("HUP", "INT", "TERM", "EXIT")),
                  f"normal/{monitor}/{kind} retains status, traps and job control", f"exit={status}")
        except Exception as error:
            check(False, f"normal/{monitor}/{kind} probe completed", str(error))
        finally:
            stop(process)

trash_source = subprocess.run(["bash", "-c", '. "$1/tests/ui-trash.sh"; '
                               'declare -f trash_cleanup trash_private_pids trash_owned_pid', "bash", str(repo)],
                              capture_output=True, text=True, check=True).stdout
(root / "trash-actual.sh").write_text(trash_source)
trash_runner = root / "trash-runner.sh"
trash_runner.write_text('''set -u
trash_box=$1 SANDBOX_MARKER=$2 trash_bus_address=$3
export XDG_DATA_HOME="$trash_box/data"
trash_private_bus_id=stand-in trash_checks=0 trash_bus_pid=""
. "$(dirname "$0")/trash-actual.sh"
kill_flea() { : > "$trash_box/touched"; }
trash_cleanup 0
''')
for kind in ("renamed", "missing", "bad-bus"):
    case = root / f"trash-{kind}"
    case.mkdir()
    custom_marker = ".capture-owned-marker"
    (case / (custom_marker if kind != "missing" else marker)).touch()
    bus = f"unix:path={case}/bus"
    env = {**os.environ, "DBUS_SESSION_BUS_ADDRESS": bus, "XDG_DATA_HOME": str(case / "data")}
    private = subprocess.Popen(["sleep", "60"], env=env, start_new_session=True)
    sentinel = subprocess.Popen(["sleep", "60"], env={**env, "XDG_DATA_HOME": str(case / "other-data")},
                                start_new_session=True)
    process = launch(trash_runner, case, custom_marker, bus if kind != "bad-bus" else bus + "-other")
    try:
        status = process.wait(timeout=5)
        accepted = kind == "renamed"
        check(status == (0 if accepted else 1), f"Trash/{kind} marker and bus guard", f"exit={status}")
        check((case / "touched").exists() == accepted, f"Trash/{kind} refuses before candidate cleanup")
        check(running(private.pid) != accepted, f"Trash/{kind} only accepted teardown stops its private process")
        check(sentinel.poll() is None, f"Trash/{kind} unrelated process survives")
    except Exception as error:
        check(False, f"Trash/{kind} probe completed", str(error))
    finally:
        stop(process)
        stop(private)
        stop(sentinel)

print(f"CAPTURELIFECYCLE DONE checks={checks} failed={failed}")
sys.exit(bool(failed))
