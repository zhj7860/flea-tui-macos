#!/usr/bin/env bash
# The capture sweep's chooser process finds the compositor through its private runtime, as the shipped chooser does under the desktop's own; offscreen qs, fake Hyprland sockets.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "sweep-picker-env.sh: qs is not installed, cannot start the chooser double"
    exit 1
fi

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-sweep-picker-env-XXXXXX") || exit 1
# The allocated path must be absolute and non-empty before the sandbox trusts it.
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" || exit 1
cat > "$test_root/config/shell.qml" <<'EOF'
//@ pragma ShellId flea-sweep-picker-env-test
import Quickshell
import Quickshell.Hyprland
import QtQuick

// Reading a Hyprland property is what makes Quickshell look for the compositor, as every Flea shell does through qs.Commons.
ShellRoot {
    readonly property var monitor: Hyprland.focusedMonitor
    Timer { interval: 1500; running: true; onTriggered: Qt.quit() }
}
EOF

python3 -I - "$PWD/tests/ui-captures-sweep-picker.py" "$test_root" <<'PY'
import ast
import os
from pathlib import Path
import socket
import subprocess
import sys
import threading

script, root = Path(sys.argv[1]), Path(sys.argv[2])
source = script.read_text()
failed = False


def check(label, good, detail=""):
    global failed
    print(f"{'ok  ' if good else 'FAIL'} {label}{'' if good else ': ' + detail}", flush=True)
    failed = failed or not good


# Sample input: the picker script's own HYPRLAND_ALIAS constant and the two functions that build the chooser environment, cut out by name.
wanted = {"HYPRLAND_ALIAS", "hyprland_environment", "picker_environment"}
namespace = {"Path": Path}
tree = ast.parse(source)
for node in tree.body:
    name = node.name if isinstance(node, ast.FunctionDef) else next((t.id for t in getattr(node, "targets", []) if isinstance(t, ast.Name)), None)
    if name in wanted:
        exec(ast.get_source_segment(source, node), namespace)
        wanted.discard(name)
if wanted:
    print(f"FAIL the picker script lacks {sorted(wanted)}")
    sys.exit(1)

# Sample input: a real signature, a 40-hex commit, a unix time and a 9-digit number joined by underscores.
signature = "0123456789abcdef0123456789abcdef01234567_1760000000_123456789"
real = root / "real"
instance = real / "hypr" / signature
instance.mkdir(parents=True)
real.chmod(0o700)
drive_env = {"XDG_RUNTIME_DIR": str(real), "HYPRLAND_INSTANCE_SIGNATURE": signature, "WAYLAND_DISPLAY": "wayland-1"}

REQUEST_BYTES = 4096


requests = root / "requests"
requests.mkdir()


def note(name, line):
    with (requests / name).open("a") as log:
        log.write(line + "\n")


def seen(name):
    # One line per request a server accepted, so a count that did not grow means the socket was never reached.
    log = requests / name
    return len(log.read_text().splitlines()) if log.exists() else 0


def serve(name, answer):
    # The real path is too long for sockaddr_un, so each server binds by a relative name from inside the instance directory.
    previous = os.getcwd()
    os.chdir(instance)
    try:
        listener = socket.socket(socket.AF_UNIX)
        listener.bind(name)
        listener.listen(8)
    finally:
        os.chdir(previous)

    def loop():
        while True:
            try:
                connection, _ = listener.accept()
            except OSError:
                return
            with connection:
                if answer:
                    request = connection.recv(REQUEST_BYTES)
                    note(name, repr(request))
                    connection.sendall(answer(request))
                else:
                    note(name, "connected")
                    threading.Event().wait(2)

    threading.Thread(target=loop, daemon=True).start()


# Sample input: b"j/monitors", the command Quickshell sends; every list command gets an empty answer.
serve(".socket.sock", lambda request: b"{}" if request.endswith(b"status") else b"[]")
serve(".socket2.sock", None)

runtime = root / "runtime"
runtime.mkdir(mode=0o700)
reachable = f"{runtime}/hypr/{signature}/.socket2.sock"
check("the real signature would push the socket path past sockaddr_un", len(os.fsencode(reachable)) > 107,
      f"{len(os.fsencode(reachable))} bytes")


def chooser_log(environment):
    base = {"HOME": str(root / "home"), "PATH": os.environ["PATH"], "QT_QPA_PLATFORM": "offscreen",
            "QT_QPA_PLATFORMTHEME": "generic", "QT_FORCE_STDERR_LOGGING": "1"}
    done = subprocess.run(["timeout", "30", "qs", "-p", str(root / "config")], env={**base, **environment},
                          text=True, capture_output=True, stdin=subprocess.DEVNULL)
    return done.stdout + done.stderr, done.returncode


CONNECTION_FAULTS = ("Unable to find hyprland socket", "Unable to connect to hyprland event socket", "Error making request")

# The chooser as the sweep started it before: a private runtime with no hypr directory in it.
control, _ = chooser_log({"XDG_RUNTIME_DIR": str(runtime), "HYPRLAND_INSTANCE_SIGNATURE": signature})
check("a private runtime with no hypr directory makes Quickshell warn it cannot find the socket",
      "Unable to find hyprland socket" in control, control)

# The environment comes from the function the sweep itself calls, with the sweep's globals standing in as sample input.
namespace.update(drive_env=drive_env, root=root / "picker", theme_home=root / "home")
(root / "picker").mkdir()
picker_env = namespace["picker_environment"](runtime)

# Sample input: "picker_env = picker_environment(runtime)" at the top level of the picker script, then only new keys added to it, never a rewrite of what the function built.
MUTATORS = {"update", "setdefault", "pop", "popitem", "clear", "__setitem__", "__delitem__"}


def on_env(node):
    return isinstance(node, ast.Name) and node.id == "picker_env"


augmented = {id(node.target) for node in ast.walk(tree) if isinstance(node, ast.AugAssign)}
stores = [node for node in ast.walk(tree) if on_env(node) and isinstance(node.ctx, ast.Store) and id(node) not in augmented]
built = [node for node in tree.body if isinstance(node, ast.Assign) and [t.id for t in node.targets if isinstance(t, ast.Name)] == ["picker_env"]
         and isinstance(node.value, ast.Call) and isinstance(node.value.func, ast.Name) and node.value.func.id == "picker_environment"]
rewrites = []
for node in ast.walk(tree):
    if isinstance(node, ast.AugAssign) and on_env(node.target):
        rewrites.append((node.lineno, "augmented assignment of picker_env"))
    elif isinstance(node, ast.Subscript) and on_env(node.value) and isinstance(node.ctx, ast.Del):
        rewrites.append((node.lineno, "subscript delete on picker_env"))
    elif isinstance(node, ast.Subscript) and on_env(node.value) and isinstance(node.ctx, ast.Store):
        key = node.slice.value if isinstance(node.slice, ast.Constant) else None
        if key is None or key in picker_env:
            rewrites.append((node.lineno, "subscript store on picker_env of " + (f"{key!r}, which picker_environment built" if key else "a key that is not a constant")))
    elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and on_env(node.func.value) and node.func.attr in MUTATORS:
        rewrites.append((node.lineno, f"call of picker_env.{node.func.attr}"))
check("the picker script builds its own picker_env from picker_environment, once, and never rewrites it afterward",
      len(built) == 1 and len(stores) == 1 and not rewrites,
      f"{len(built)} top-level picker_environment(...) assignments, {len(stores)} assignments of picker_env, rewrites: "
      + "; ".join(f"line {line}: {form}" for line, form in sorted(rewrites)))
sockets = (".socket.sock", ".socket2.sock")
before = {name: seen(name) for name in sockets}
shipped, code = chooser_log(picker_env)
silent = [name for name in sockets if seen(name) == before[name]]
check("the chooser environment the script builds reaches both Hyprland sockets", code == 0 and not silent,
      f"qs returned {code}, no request reached {silent}\n{shipped}")
faults = [line for line in shipped.splitlines() if any(fault in line for fault in CONNECTION_FAULTS)]
check("the chooser log carries no Hyprland connection warning", not faults, "\n".join(faults))
chosen = runtime / "hypr" / picker_env["HYPRLAND_INSTANCE_SIGNATURE"]
check("the chooser environment resolves its Hyprland instance to the live one, by a path that fits the socket",
      chosen.resolve() == instance.resolve() and len(os.fsencode(chosen / ".socket2.sock")) <= 107, str(chosen))

missing = root / "missing"
missing.mkdir(mode=0o700)
try:
    namespace["hyprland_environment"](runtime, {"XDG_RUNTIME_DIR": str(missing), "HYPRLAND_INSTANCE_SIGNATURE": signature})
    refused = False
except AssertionError as error:
    refused = "the Hyprland instance directory is missing" in str(error)
check("a desktop with no Hyprland instance directory is refused, not warned about later", refused)

if failed:
    sys.exit(1)
print("SWEEPPICKERENV DONE")
PY
