#!/usr/bin/env python3
"""Run the shipped loop eject command against stub tools and a marked fake sysfs tree."""
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
assert root.is_absolute() and (root / '.flea-test-sandbox').is_file()
receipt = [line.split('LOOP_EJECT_COMMAND ', 1)[1] for line in (root / 'command.log').read_text().splitlines()
           if 'LOOP_EJECT_COMMAND ' in line]
assert len(receipt) == 1, 'the loop command must come from the production JS fixture exactly once'
command = json.loads(receipt[0])
assert command[:2] == ['sh', '-c']
tools = root / 'bin'
tools.mkdir()
gio = tools / 'gio'
gio.write_text('''#!/bin/sh
[ "$1" = mount ] && [ "$2" = -u ] && [ "$3" = "$TEST_MOUNT" ] || exit 65
case "$TEST_CHANGE" in
    changed) printf '%s\\n' '/images/other.iso' > "$TEST_BACKING" ;;
    missing) python3 -c 'import os; p=os.environ["TEST_BACKING"]; r=os.environ["TEST_ROOT"]; assert p and os.path.isabs(p) and p.startswith(r + "/") and os.path.isfile(r + "/.flea-test-sandbox"); os.unlink(p)' ;;
    empty) : > "$TEST_BACKING" ;;
    reused) printf '%s\\n' 0 > "$TEST_AUTOCLEAR" ;;
    unreadable-now-readable) printf '%s\\n' 0 > "$TEST_AUTOCLEAR" ;;
esac
exit "$TEST_UNMOUNT_EXIT"
''')
udisks = tools / 'udisksctl'
udisks.write_text('''#!/bin/sh
[ "$1" = loop-delete ] && [ "$2" = --no-user-interaction ] && [ "$3" = -b ] && [ "$4" = /dev/loop0 ] || exit 66
printf 'detach\\n' >> "$TEST_DETACH_LOG"
exit "$TEST_DETACH_EXIT"
''')
gio.chmod(0o700)
udisks.chmod(0o700)
backing = root / 'sys/block/loop0/loop/backing_file'
backing.parent.mkdir(parents=True)
autoclear = backing.with_name('autoclear')
mount = '/run/media/user/ISO "quoted"; $(touch SHOULD_NOT_EXIST)'
failed = 0
cases = [('changed', 0, 0, 0, 0), ('missing', 0, 0, 0, 0), ('empty', 0, 0, 0, 0),
         ('same', 0, 0, 1, 0), ('same', 1, 0, 1, 1), ('same', 1, 1, 1, 3),
         ('same', 0, 1, 1, 3), ('changed', 1, 0, 0, 1), ('missing', 1, 0, 0, 1),
         ('initial-empty', 0, 0, 0, 0), ('initial-missing', 0, 0, 0, 0)]
cases = [('0', *case) for case in cases]
for value in ['1', 'unreadable']:
    for unmount_exit in [0, 1]:
        for change in ['same', 'changed', 'missing', 'empty', 'reused', 'unreadable-now-readable']:
            cases.append((value, change, unmount_exit, 1, 0, unmount_exit))
for index, (value, change, unmount_exit, detach_exit, detach_count, status) in enumerate(cases):
    if change == 'initial-missing':
        assert backing.is_absolute() and str(backing).startswith(str(root) + '/')
        backing.unlink(missing_ok=True)
    else:
        backing.write_text('' if change == 'initial-empty' else '/images/original with spaces.iso\n')
    if value == 'unreadable':
        assert autoclear.is_absolute() and str(autoclear).startswith(str(root) + '/')
        autoclear.unlink(missing_ok=True)
    else:
        autoclear.write_text(value + '\n')
    log = root / ('detach-' + str(index))
    env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'], TEST_MOUNT=mount,
               TEST_ROOT=str(root), TEST_BACKING=str(backing), TEST_AUTOCLEAR=str(autoclear), TEST_CHANGE=change,
               TEST_UNMOUNT_EXIT=str(unmount_exit), TEST_DETACH_EXIT=str(detach_exit), TEST_DETACH_LOG=str(log))
    argv = command[:]
    argv[4] = mount
    if len(argv) > 6:
        argv[6] = str(backing)
    if len(argv) > 7:
        argv[7] = str(autoclear)
    result = subprocess.run(argv, cwd=root, env=env, capture_output=True, text=True, timeout=5)
    count = len(log.read_text().splitlines()) if log.exists() else 0
    ok = (result.returncode, count) == (status, detach_count) and not (root / 'SHOULD_NOT_EXIST').exists()
    print(('ok   ' if ok else 'FAIL ') + f'loop eject autoclear={value} {change} unmount={unmount_exit} detach={detach_exit}: '
          f'exit={result.returncode} calls={count}; expected exit={status} calls={detach_count}')
    failed += not ok
raise SystemExit(bool(failed))
