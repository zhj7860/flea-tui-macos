#!/usr/bin/env python3
# Regression checks exercise the static gates without changing the real tree.
import ast
import contextlib
import inspect
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

import staticgates as gates

# A function expression stays indented here; the column-0 house style keeps column 0 for declarations.
DUPDECL_FIXTURES = {
    'F1-opacity': ('ui/A.qml', 'Item { Behavior on opacity { property int value: 0; property int value: 1 } }\n', 'Duplicate property name'),
    'F1-x': ('ui/A.qml', 'Item { Behavior on x { property int wire: 0; property int wire: 1 } }\n', 'Duplicate property name'),
    'F2-increment': ('ui/A.js', 'function wire() {}\nvar counter = 0\ncounter++\nfunction wire() {}\n', 'wire declared again (first at 1)'),
    'F2-decrement': ('ui/A.js', 'function wire() {}\nvar counter = 0\ncounter--\nfunction wire() {}\n', 'wire declared again (first at 1)'),
    'F3-object-division': ('ui/A.qml', 'Item {\nfunction first() { var x = {} / 2; } function wire() { return /x/; }\nfunction wire() {}\n}\n', 'Duplicate method name'),
    'F3-template-return': ('ui/A.qml', 'Item {\nproperty int wire: 0\nproperty string text: `${({return:10}).return / 2}/s`\nproperty int wire: 1\n}\n', 'Duplicate property name'),
    'F3-ratio-return': ('ui/Ratio.js', 'function wire() {}\nvar ratio = ({return: 4}).return / 2;\nfunction wire() {}', 'wire declared again (first at 1)'),
    'F4-binding-return': ('ui/A.qml', 'Item {\nproperty int wire: 0\nproperty var result: ({return:10}).return\nproperty int wire: 1\n}\n', 'Duplicate property name'),
    'F5-void': ('ui/Plain.js', 'function wire() {}\nvoid\n    function wire() {}()\n', None),
    'F5-typeof': ('ui/Plain.js', 'function wire() {}\nvar type = typeof\n    function wire() {}\n', None),
}


# The qmllint command places its JSON output before the requested source paths.
QMLLINT_JSON_ARGUMENT = 2
QMLLINT_FIRST_FILE_ARGUMENT = 3
REAL_QMLLINT = Path(os.environ.get('FLEA_QMLLINT', '/usr/lib/qt6/bin/qmllint'))


class StaticGateTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='staticgates-tests-')
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)

    def write(self, file, source):
        path = self.root / file
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source)
        return path

    def syntax(self, function):
        # Sample input: for _ in range(ALIAS_FIXPOINT_CAP): pass
        return ast.parse(inspect.getsource(function))

    def import_failure(self, module):
        return {'id': 'import', 'message': f'Failed to import {module}. Are your import paths set up properly?'}

    def import_roots(self, command):
        return {Path(command[i + 1]).name for i, argument in enumerate(command) if argument == '-I'}

    def stub_roots(self):
        for module in (gates.QMLLINT_ALWAYS_STUB, *gates.QMLLINT_PROBED_MODULES):
            (self.root / gates.QMLLINT_STUBS / module).mkdir(parents=True)

    @contextlib.contextmanager
    def qmllint(self, warnings=None, missing=()):
        def run(command, **kwargs):
            files = [argument for argument in command[QMLLINT_FIRST_FILE_ARGUMENT:] if argument.endswith('.qml')]
            probe = [self.import_failure(module) for module in missing]
            data = {'files': [{'filename': file, 'warnings': list((warnings or {}).get(file, [])) + (probe if file.endswith('Probe.qml') else [])}
                              for file in files]}
            Path(command[QMLLINT_JSON_ARGUMENT]).write_text(json.dumps(data))
            return subprocess.CompletedProcess(command, 0, stdout='', stderr='')

        with mock.patch.dict(os.environ, {'FLEA_QMLLINT': sys.executable}):
            with mock.patch.object(gates.subprocess, 'run', side_effect=run) as called:
                with contextlib.redirect_stdout(io.StringIO()):
                    yield called

    def test_F3_alias_caps_are_named(self):
        for function in (gates.pane_references, gates.del_printable):
            with self.subTest(function=function.__name__):
                ranges = [node for node in ast.walk(self.syntax(function))
                          if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                          and node.func.id == 'range']
                self.assertEqual(len(ranges), 1)
                self.assertIsInstance(ranges[0].args[0], ast.Name, 'alias cap is a bare literal')
                self.assertEqual(ranges[0].args[0].id, 'ALIAS_FIXPOINT_CAP')
                self.assertEqual(gates.ALIAS_FIXPOINT_CAP, 8)

    def test_F3_qmllint_timeout_is_named(self):
        keywords = [node for node in ast.walk(self.syntax(gates.qml_undeclared_read))
                    if isinstance(node, ast.keyword) and node.arg == 'timeout']
        self.assertEqual(len(keywords), 1)
        self.assertIsInstance(keywords[0].value, ast.Name, 'qmllint timeout is a bare literal')
        self.assertEqual(keywords[0].value.id, 'QMLLINT_TIMEOUT_SECONDS')
        self.assertEqual(gates.QMLLINT_TIMEOUT_SECONDS, 120)

    def test_F3_stderr_excerpt_is_named(self):
        slices = [node for node in ast.walk(self.syntax(gates.qml_undeclared_read))
                  if isinstance(node, ast.Subscript) and isinstance(node.value, ast.Attribute)
                  and node.value.attr == 'stderr']
        self.assertEqual(len(slices), 1)
        self.assertIsInstance(slices[0].slice.upper, ast.Name, 'stderr excerpt is a bare literal')
        self.assertEqual(slices[0].slice.upper.id, 'STDERR_EXCERPT_LENGTH')
        self.assertEqual(gates.STDERR_EXCERPT_LENGTH, 200)

    def test_F5_archive_inventory_without_git(self):
        archive = self.root / 'tree.tar'
        with tarfile.open(archive, 'w') as source:
            member = tarfile.TarInfo('sample.txt')
            source.addfile(member, io.BytesIO())
        empty_path = self.root / 'empty-path'
        empty_path.mkdir()
        program = ('import json, sys; from pathlib import Path; '
                   'sys.path.insert(0, sys.argv[1]); from staticgates import inventory; '
                   'print(json.dumps(inventory(Path(sys.argv[2]))))')
        result = subprocess.run([sys.executable, '-B', '-c', program, str(Path(gates.__file__).parent), str(self.root)],
                                env={**os.environ, 'PATH': str(empty_path), 'FLEA_SOURCE_ARCHIVE': str(archive)},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), '["sample.txt"]')

    def test_F8_shell_single_quote_closes_after_literal_backslash(self):
        source = "printf 'a\\' ; x    y\n"
        file = self.write('sample.sh', source)
        syntax = subprocess.run(['/bin/bash', '-n', str(file)], capture_output=True, text=True)
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        self.assertEqual(gates.fused_line(self.root, ['sample.sh']),
                         (1, ['sample.sh:1: fused code gap (4 spaces)']))

    def test_F8_other_quotes_keep_escape_handling(self):
        for suffix, source in (('.sh', 'printf "a\\"    b" ; x    y\n'),
                               ('.sh', 'printf `a\\`    b` ; x    y\n'),
                               ('.js', "var text = 'a\\'    b'; x    y\n")):
            with self.subTest(suffix=suffix, source=source):
                file = 'control' + suffix
                self.write(file, source)
                self.assertEqual(gates.fused_line(self.root, [file]),
                                 (1, [f'{file}:1: fused code gap (4 spaces)']))

    def test_F10_parsers_have_sample_input_comments(self):
        lines = inspect.getsource(gates.qml_undeclared_read).splitlines()
        for parser in ('json.loads(', "line.split('\\t', 3)"):
            with self.subTest(parser=parser):
                index = next(i for i, line in enumerate(lines) if parser in line)
                self.assertIn('# Sample input:', lines[index - 1])

    def test_commons_color_rejects_every_bare_color_read(self):
        self.write('ui/Bare.qml', 'Rectangle {\n    color: Color.accent\n}\n')
        self.write('shelf/Optional.qml', 'Rectangle {\n    color: Color?.accent\n}\n')
        self.write('ui/js/Subscript.js', '.pragma library\nfunction ink() { return Color["foreground"] }\n')
        self.write('ui/Qualified.qml', 'import qs.Commons as Commons\nRectangle {\n    color: Commons.Color.accent\n    border.color: Theme.color.accent\n    property color myColor: "red"\n}\n')
        self.write('shelf/Unbound.qml', 'import qs.Commons\nRectangle {\n    color: Commons.Color.accent\n}\n')
        self.write('ui/Versioned.qml', 'import qs.Commons 1.0 as Commons\nRectangle { color: Commons.Color.accent }\n')
        self.write('ui/js/Bound.js', '.pragma library\n.import qs.Commons 1.0 as Commons\nfunction ink() { return Commons.Color.accent }\n')
        self.write('ui/js/Context.js', 'function ink() { return Commons.Color.accent }\n')
        self.write('ui/js/Imported.js', '.import qs.Commons as Commons\nfunction ink() { return Commons.Color.accent }\n')
        self.write('ui/js/Unbound.js', '.pragma library\nfunction ink() { return Commons.Color.accent }\n')
        self.write('ui/Prose.qml', 'Item { // Color.loadColors runs first\n    property string s: "Color.accent"\n}\n')
        self.write('ui/Other.py', 'Color.accent\n')
        files = ['ui/Bare.qml', 'shelf/Optional.qml', 'ui/js/Subscript.js', 'ui/Qualified.qml', 'shelf/Unbound.qml', 'ui/Versioned.qml',
                 'ui/js/Bound.js', 'ui/js/Context.js', 'ui/js/Imported.js', 'ui/js/Unbound.js', 'ui/Prose.qml', 'ui/Other.py']
        bare = ": bare Color, which Qt 6.12 resolves to QtQuick's own; read Commons.Color"
        unbound = ': reads Commons without import qs.Commons as Commons'
        self.assertEqual(gates.commons_color(self.root, files),
                         (11, ['ui/Bare.qml:2' + bare, 'shelf/Optional.qml:2' + bare, 'ui/js/Subscript.js:2' + bare,
                               'shelf/Unbound.qml:3' + unbound, 'ui/js/Context.js:1' + unbound, 'ui/js/Unbound.js:2' + unbound]))

    def test_easing_rejects_every_curve_but_outcubic_and_linear(self):
        self.write('ui/Quad.qml', 'Item {\n    NumberAnimation { duration: 140; easing.type: Easing.OutQuad }\n}\n')
        self.write('ui/Spaced.qml', 'Item {\n    Behavior on x { NumberAnimation { easing.type: Easing .InQuad } }\n}\n')
        self.write('ui/js/Curve.js', 'function curve() {\n    return Easing.InOutSine\n}\n')
        self.write('ui/Cubic.qml', 'Item {\n    NumberAnimation { easing.type: Easing.OutCubic }\n    NumberAnimation { easing.type: Easing.Linear }\n}\n')
        self.write('ui/Prose.qml', 'Item { // was Easing.OutQuad\n    property string s: "Easing.InQuad"\n    property int myEasing.OutQuad: 0\n}\n')
        self.write('shelf/Other.qml', 'Item { NumberAnimation { easing.type: Easing.OutQuad } }\n')
        self.write('ui/Other.py', 'Easing.OutQuad\n')
        files = ['ui/Quad.qml', 'ui/Spaced.qml', 'ui/js/Curve.js', 'ui/Cubic.qml', 'ui/Prose.qml', 'shelf/Other.qml', 'ui/Other.py']
        rule = ', every transition uses Easing.OutCubic'
        self.assertEqual(gates.easing(self.root, files),
                         (5, ['ui/Quad.qml:2: Easing.OutQuad' + rule, 'ui/Spaced.qml:2: Easing.InQuad' + rule,
                              'ui/js/Curve.js:2: Easing.InOutSine' + rule]))

    def test_ellipsis_rejects_three_stops_in_string_literals(self):
        self.write('ui/Busy.qml', 'Item {\n'
                   '    property string saving: "Saving..."\n'
                   '    property string fixed: "Saving…"\n'
                   '    // "Saving..." is a comment\n'
                   '    property string uri: "smb://x..."\n'
                   '    property string tail: "Saving…" // "Saving..." tail\n'
                   '    property string dots: "..."\n'
                   '}\n')
        self.write('ui/js/Busy.js', 'function label() { return "Working..." }\n')
        self.write('shelf/Busy.qml', 'Item { property string s: "Saving..." }\n')
        files = ['ui/Busy.qml', 'ui/Missing.qml', 'ui/js/Busy.js', 'shelf/Busy.qml']
        stops = ': three full stops after a letter, use the ellipsis character'
        self.assertEqual(gates.ellipsis(self.root, files),
                         (2, ['ui/Busy.qml:2' + stops, 'ui/Busy.qml:5' + stops, 'ui/js/Busy.js:1' + stops]))

    def test_ellipsis_reads_all_string_kinds_and_skips_block_comments(self):
        self.write('ui/Kinds.qml', 'Item {\n'
                   "    property string single: 'Working...'\n"
                   '    property string mixed: \'smb://h\' + "Loading..."\n'
                   '    property string escaped: "a\\"//b..."\n'
                   '    property string fixed: "Saving…"\n'
                   '}\n')
        self.write('ui/js/Ticks.js', 'function label() { return `Saving...` }\n')
        self.write('ui/Block.qml', '/* "Saving..." */\n'
                   '/* open\n'
                   ' * "Saving..."\n'
                   ' close */\n'
                   'Item { property string ok: "fine" }\n')
        files = ['ui/Kinds.qml', 'ui/js/Ticks.js', 'ui/Block.qml']
        stops = ': three full stops after a letter, use the ellipsis character'
        self.assertEqual(gates.ellipsis(self.root, files),
                         (3, ['ui/Kinds.qml:2' + stops, 'ui/Kinds.qml:3' + stops,
                               'ui/Kinds.qml:4' + stops, 'ui/js/Ticks.js:1' + stops]))

    def test_ellipsis_skips_line_comments_before_blocks_and_code(self):
        self.write('ui/LineApostrophe.qml', "// it's here\n"
                   '/* "Saving..." */\n'
                   'Item { property string saving: "Saving..." }\n'
                   'Item { property string ok: "fine" }\n')
        self.write('ui/LineBlock.qml', '// see /* note\n'
                   'Item { property string saving: "Saving..." }\n'
                   'Item { property string ok: "fine" }\n')
        files = ['ui/LineApostrophe.qml', 'ui/LineBlock.qml']
        stops = ': three full stops after a letter, use the ellipsis character'
        self.assertEqual(gates.ellipsis(self.root, files),
                         (2, ['ui/LineApostrophe.qml:3' + stops, 'ui/LineBlock.qml:2' + stops]))

    def test_ellipsis_checks_template_continuation_lines(self):
        self.write('ui/js/Spanning.js', 'function label(n) {\n'
                   '    return `Copied ${n}\n'
                   '    files, Saving...`\n'
                   '}\n')
        self.write('ui/js/Middle.js', 'function label() {\n'
                   '    return `first\n'
                   '    Saving... more\n'
                   '    last`\n'
                   '}\n')
        self.write('ui/js/Closed.js', 'function label() {\n'
                   '    return `done`\n'
                   '    // "Saving..." noted after the closed template\n'
                   '}\n')
        files = ['ui/js/Spanning.js', 'ui/js/Middle.js', 'ui/js/Closed.js']
        stops = ': three full stops after a letter, use the ellipsis character'
        self.assertEqual(gates.ellipsis(self.root, files),
                         (3, ['ui/js/Middle.js:3' + stops, 'ui/js/Spanning.js:3' + stops]))

    def test_worker_announce_allows_only_the_counted_worker(self):
        self.write('ui/Bare.qml', 'Item { WorkerScript { source: "W.js" } }\n')
        self.write('ui/Said.qml', 'WorkerScript {\n    // WORKER_STARTED\n    Component.onCompleted: console.info(log, "WORKER_STARTED " + source)\n}\n')
        self.write('ui/Prose.qml', 'Item { // a WorkerScript { here\n    property string s: "WorkerScript {"\n}\n')
        self.write('ui/Named.qml', 'Item { CountedWorker { source: "W.js" } }\n')
        self.write('ui/CountedWorker.qml', 'WorkerScript {\n    Component.onCompleted: console.info(startLog, "WORKER_STARTED " + source)\n}\n')
        files = ['ui/Bare.qml', 'ui/Said.qml', 'ui/Prose.qml', 'ui/Named.qml', 'ui/CountedWorker.qml']
        self.assertEqual(gates.worker_announce(self.root, files),
                         (5, ['ui/Bare.qml:1: WorkerScript outside ui/CountedWorker.qml', 'ui/Said.qml:1: WorkerScript outside ui/CountedWorker.qml']))
        missing = 'ui/CountedWorker.qml:1: no console.info(startLog, "WORKER_STARTED " ...) call in code'
        for body in ('WorkerScript {\n}\n', 'WorkerScript {\n    // console.info(startLog, "WORKER_STARTED " + source)\n}\n',
                     'WorkerScript {\n    Component.onCompleted: console.info(startLog, "started " + source)\n}\n'):
            with self.subTest(body=body):
                self.write('ui/CountedWorker.qml', body)
                self.assertEqual(gates.worker_announce(self.root, ['ui/CountedWorker.qml']), (1, [missing]))
        self.write('ui/CountedWorker.qml', 'WorkerScript {\n    function a() { console.info(startLog, "other") }\n    Component.onCompleted: console.info(startLog, "WORKER_STARTED " + source)\n}\n')
        self.assertEqual(gates.worker_announce(self.root, ['ui/CountedWorker.qml']), (1, []))

    def test_variadic_scan_runs_once_under_one_gate_name(self):
        self.write('src/a.rs', 'extern "C" {\n    fn syscall(number: i64) -> i64;\n    fn fcntl(fd: i32, cmd: i32, ...) -> i32;\n}\nfn open(path: i32) {}\n')
        (self.root / 'src/link.rs').symlink_to('a.rs')
        tail = ': fn syscall declared without its C variadic ... tail'
        self.assertEqual(gates.extern_variadic(self.root, ['src/a.rs', 'src/link.rs']), (1, ['src/a.rs:2' + tail]))
        self.assertEqual(gates.GATES.count('extern-variadic'), 1)
        self.assertNotIn('variadic-libc', gates.GATES)
        output = io.StringIO()
        with mock.patch.object(sys, 'argv', ['staticgates.py', '--gate', 'extern-variadic', '--root', str(self.root)]):
            with mock.patch.object(gates, 'inventory', return_value=['src/a.rs']):
                with contextlib.redirect_stdout(output):
                    result = gates.main()
        self.assertEqual(result, 1)
        self.assertEqual(output.getvalue(), f'STATICGATE extern-variadic FAIL src/a.rs:2{tail}\nSTATICGATES FAIL gates=1\n')

    def test_worker_report_rejects_each_branch_and_root_name(self):
        for file in ('RESULT.md', 'REPORT-1.md', 'STUDY-1.md', 'RUN.md', 'PREMISE-1.txt',
                     '.superpowers/hyg1/NOTES.md'):
            self.write(file, 'run notes\n')
        self.write('docs/notes.md', 'run notes\n')
        files = ['RESULT.md', 'REPORT-1.md', 'STUDY-1.md', 'RUN.md', 'PREMISE-1.txt',
                 '.superpowers/hyg1/NOTES.md', 'docs/notes.md']
        self.assertEqual(gates.worker_report(self.root, files),
                         (7, ['RESULT.md:1: worker report tracked at root',
                              'REPORT-1.md:1: worker report tracked at root',
                              'STUDY-1.md:1: worker report tracked at root',
                              'RUN.md:1: worker report tracked at root',
                              'PREMISE-1.txt:1: worker report tracked at root',
                              '.superpowers/hyg1/NOTES.md:1: worker report tracked at .superpowers']))

    def test_F10_malformed_tsv_names_file_and_line(self):
        self.write('ui/A.qml', 'import QtQuick\nItem {}\n')
        for row in ('ui/A.qml\t1\tmissing_reason',
                    'ui/A.qml\tnot-a-number\tasker\tDeclared QML id.',
                    'ui/A.qml\t1\tasker\t'):
            with self.subTest(row=row):
                self.write('tests/staticgates-unqualified.tsv', '# profile quickshell-present\n' + row + '\n')
                output = io.StringIO()
                with self.qmllint(), mock.patch.object(sys, 'argv', ['staticgates.py', '--gate',
                                        'qml-undeclared-read', '--root', str(self.root)]):
                    with mock.patch.object(gates, 'inventory', return_value=['ui/A.qml']):
                        with contextlib.redirect_stdout(output):
                            result = gates.main()
                self.assertEqual(result, 1)
                self.assertIn('tests/staticgates-unqualified.tsv:2:', output.getvalue())

    def test_watch_mark_observer_is_scoped_and_must_be_used(self):
        self.write('tests/js/watch.js', 'function pane() { var p = {cursorIndex: 0}; p.marked = []; return p }\n')
        self.write('ui/js/Live.js', 'function run(pane) { pane.marked = [] }\n')
        key = ('tests/js/watch.js', 'marked')
        with (mock.patch.object(gates, 'pane_members', return_value={'cursorIndex'}),
              mock.patch.object(gates, 'stub_allowances', return_value={key: gates.stub_allowances()[key]})):
            self.assertEqual(gates.paneprops(self.root, ['tests/js/watch.js']), (1, []))
            count, errors = gates.paneprops(self.root, ['tests/js/watch.js', 'ui/js/Live.js'])
            self.assertEqual(count, 2)
            self.assertEqual(errors, ['ui/js/Live.js:1: pane.marked absent from Pane/FocusScope'])
            self.write('tests/js/watch.js', 'function pane() { return {cursorIndex: 0} }\n')
            self.assertEqual(gates.paneprops(self.root, ['tests/js/watch.js']),
                             (1, ['tests/js/watch.js: stale stub instrumentation allowance marked']))

    def test_F11_pane_flow_skips_missing_inventory_entry(self):
        self.write('ui/js/Live.js', 'function run(pane) { pane.cursorIndex = 0 }\n')
        sources, _ = gates.pane_flow(self.root, ['ui/js/Old.js', 'ui/js/Live.js'], {'cursorIndex'})
        self.assertEqual(set(sources), {'ui/js/Live.js'})

    def test_F11_paneprops_skips_missing_inventory_entry_and_checks_live_file(self):
        self.write('ui/js/Live.js', 'function run(pane) { pane.removedProperty = true }\n')
        with mock.patch.object(gates, 'pane_members', return_value={'cursorIndex'}):
            count, errors = gates.paneprops(self.root, ['ui/js/Old.js', 'ui/js/Live.js'], sample=True)
        self.assertEqual(count, 1)
        self.assertEqual(errors, ['ui/js/Live.js:1: pane.removedProperty absent from Pane/FocusScope'])

    def test_F11_del_printable_skips_missing_inventory_entry_and_checks_live_file(self):
        self.write('ui/js/Live.js', 'function key(event) { return event.text.length === 1 }\n')
        self.assertEqual(gates.del_printable(self.root, ['ui/js/Old.js', 'ui/js/Live.js']),
                         (1, ['ui/js/Live.js:1: printable event.text decision bypasses Input.isPrintable']))

    def test_F11_paneprops_skips_allowances_for_missing_test_files(self):
        with mock.patch.object(gates, 'pane_members', return_value={'cursorIndex'}):
            with mock.patch.object(gates, 'stub_allowances', return_value={('tests/js/Old.js', 'said'): 'Records messages.'}):
                self.assertEqual(gates.paneprops(self.root, ['tests/js/Old.js']), (0, []))

    def test_pane_function_value_rejects_compared_without_call(self):
        self.write('ui/Pane.qml', 'import QtQuick\nFocusScope {\n    property string label: ""\n    function identityOf() { return "" }\n}\n')
        self.write('ui/js/Negative.js', 'function f(pane, id) { return id !== pane.identityOf }\n')
        self.write('ui/js/Left.js', 'function f(pane, id) { return pane.identityOf != id }\n')
        self.write('ui/Negative.qml', 'import QtQuick\nItem {\n    property var viewPane: null\n    function f(id) { return id === viewPane.identityOf }\n}\n')
        self.assertEqual(gates.pane_functions(self.root), {'identityOf'})
        count, errors = gates.pane_function_value(self.root, ['ui/js/Negative.js', 'ui/js/Left.js', 'ui/Negative.qml'])
        self.assertEqual(count, 3)
        self.assertEqual(errors, ['ui/Negative.qml:4: viewPane.identityOf compared without its call',
                                  'ui/js/Left.js:1: pane.identityOf compared without its call',
                                  'ui/js/Negative.js:1: pane.identityOf compared without its call'])

    def test_pane_function_value_passes_calls_and_value_uses(self):
        self.write('ui/Pane.qml', 'import QtQuick\nFocusScope {\n    property string label: ""\n    function identityOf() { return "" }\n}\n')
        self.write('ui/js/Called.js', 'function f(pane, id) { return id !== pane.identityOf() }\n')
        self.write('ui/js/Callback.js', 'function f(pane) { Qt.callLater(pane.identityOf) }\n')
        self.write('ui/js/Guard.js', 'function f(pane) { return typeof pane.identityOf !== "function" }\n')
        self.write('ui/js/Property.js', 'function f(pane, id) { return id !== pane.label }\n')
        self.write('ui/js/Prose.js', 'function f(pane, id) { return id !== "pane.identityOf" }\n// pane.identityOf !== id\n')
        files = ['ui/js/Called.js', 'ui/js/Callback.js', 'ui/js/Guard.js', 'ui/js/Property.js', 'ui/js/Prose.js']
        self.assertEqual(gates.pane_function_value(self.root, files), (5, []))

    def test_dead_module_call_rejects_a_function_the_module_lost(self):
        self.write('ui/js/Search.js', '.pragma library\nvar OFF = ""\nfunction start(root) {}\nfunction commit(root) {}\n')
        self.write('ui/TagState.qml', 'import QtQuick\nimport "js/Search.js" as Search\nItem {\n    function openTag(pane) { Search.run(pane) }\n}\n')
        self.write('ui/js/Nav.js', '.pragma library\n.import "Search.js" as Search\nfunction go(pane) { Search.leaveWalk(pane) }\n')
        self.write('ui/js/Deep/Walk.js', '.pragma library\n.import "../Search.js" as Search\nfunction go(pane) { return Search.sendQuery (pane) }\n')
        files = ['ui/js/Search.js', 'ui/TagState.qml', 'ui/js/Nav.js', 'ui/js/Deep/Walk.js']
        self.assertEqual(gates.dead_module_call(self.root, files),
                         (4, ['ui/TagState.qml:4: Search.run is called but ui/js/Search.js defines no function run',
                              'ui/js/Nav.js:3: Search.leaveWalk is called but ui/js/Search.js defines no function leaveWalk',
                              'ui/js/Deep/Walk.js:3: Search.sendQuery is called but ui/js/Search.js defines no function sendQuery']))

    def test_dead_module_call_passes_defined_names_and_other_reads(self):
        self.write('ui/js/Search.js', '.pragma library\nvar NOTE = { walking: "a" }\nfunction start(root) { function inner() {} }\nvar live = function (root) { return true }\n')
        self.write('ui/js/Plain.js', 'var shared = 1\nfunction visible() {}\n')
        self.write('ui/Calls.qml', 'import QtQuick\nimport "js/Search.js" as Search\nimport "js/Plain.js" as Plain\n'
                   'Item {\n    property bool a: Search.live(this)\n    property string b: Search.NOTE.walking.replace("a", "b")\n'
                   '    function f() { Search.start(this); Plain.missing(); return Search.NOTE }\n}\n')
        self.write('ui/js/Prose.js', '.pragma library\n.import "Search.js" as Search\n// Search.run(pane) was removed\nfunction f() { return "Search.run(pane)" }\n')
        self.write('ui/js/Local.js', '.pragma library\n.import "Search.js" as Search\nfunction f(Search) { return Search.run() }\n')
        self.write('ui/js/Member.js', '.pragma library\n.import "Search.js" as Search\nfunction f(pane) { return pane.Search.run() }\n')
        files = ['ui/js/Search.js', 'ui/js/Plain.js', 'ui/Calls.qml', 'ui/js/Prose.js', 'ui/js/Local.js', 'ui/js/Member.js']
        self.assertEqual(gates.dead_module_call(self.root, files), (6, []))

    def test_dead_module_call_reads_every_name_of_a_listed_var_and_an_async_function(self):
        self.write('ui/js/Lists.js', '.pragma library\nvar A = 1, B = f(2, 3),\n    C = [4, 5]\nlet D\nasync function go() {}\n')
        self.write('ui/Reads.qml', 'import QtQuick\nimport "js/Lists.js" as Lists\nItem {\n    function f() { Lists.B(); Lists.C(); Lists.D(); Lists.go() }\n}\n')
        self.write('ui/Misses.qml', 'import QtQuick\nimport "js/Lists.js" as Lists\nItem {\n    function f() { Lists.E() }\n}\n')
        self.assertEqual(gates.dead_module_call(self.root, ['ui/js/Lists.js', 'ui/Reads.qml']), (2, []))
        self.assertEqual(gates.dead_module_call(self.root, ['ui/js/Lists.js', 'ui/Misses.qml']),
                         (2, ['ui/Misses.qml:4: Lists.E is called but ui/js/Lists.js defines no function E']))

    def test_declared_names_reads_code_only(self):
        cases = [('var LABEL = "Copy, Move"\n', ['LABEL']),
                 ('var A = 1 // x, y\n', ['A']),
                 ('var OPEN = "(", B = 2\n', ['OPEN', 'B']),
                 ('var A = 1, // first\nB = function () {}\n', ['A', 'B']),
                 ('var A = 1, /* x, y */\n    B = `a, ${C}`, D = \'it\\\'s, E\'\n', ['A', 'B', 'D'])]
        for code, names in cases:
            with self.subTest(code=code):
                self.assertEqual(gates.declared_names(gates.masked(code, '.js', ' '), len('var ')), names)

    def test_module_names_masks_a_module_once(self):
        module = '.pragma library\n' + ''.join(f'var V{n} = "a, b"\n' for n in range(100))
        with mock.patch.object(gates, 'masked', wraps=gates.masked) as masking:
            names = gates.module_names(module)
        self.assertEqual(masking.call_count, 1)
        self.assertEqual(names, {f'V{n}' for n in range(100)})

    def test_dead_module_call_reads_a_var_list_past_a_line_comment(self):
        self.write('ui/js/Lists.js', '.pragma library\nvar A = 1, // first\n    B = function () {}\nvar LABEL = "Copy, Move"\n')
        self.write('ui/Reads.qml', 'import QtQuick\nimport "js/Lists.js" as Lists\nItem {\n    function f() { Lists.B(); Lists.Move() }\n}\n')
        self.assertEqual(gates.dead_module_call(self.root, ['ui/js/Lists.js', 'ui/Reads.qml']),
                         (2, ['ui/Reads.qml:4: Lists.Move is called but ui/js/Lists.js defines no function Move']))

    def test_dead_module_call_judges_a_file_that_passes_the_alias_as_an_argument(self):
        self.write('ui/js/Search.js', '.pragma library\nfunction start(root) {}\n')
        self.write('ui/Passes.qml', 'import QtQuick\nimport "js/Search.js" as Search\nItem {\n    function f(pane) { Nav.go(pane, Search); Search.run(pane) }\n}\n')
        self.write('ui/Arrow.qml', 'import QtQuick\nimport "js/Search.js" as Search\nItem {\n    property var g: (Search) => Search.run()\n}\n')
        self.write('ui/Param.qml', 'import QtQuick\nimport "js/Search.js" as Search\nItem {\n    function f(pane, Search) { return Search.run(pane) }\n}\n')
        self.assertEqual(gates.dead_module_call(self.root, ['ui/js/Search.js', 'ui/Passes.qml', 'ui/Arrow.qml', 'ui/Param.qml']),
                         (4, ['ui/Passes.qml:4: Search.run is called but ui/js/Search.js defines no function run']))

    def test_dead_module_call_is_registered(self):
        self.assertIn('dead-module-call', gates.GATES)
        self.assertIs(gates.CHECKS['dead-module-call'], gates.dead_module_call)

    def test_F11_qmllint_skips_missing_inventory_entry_and_allowance(self):
        self.write('ui/A.qml', 'import QtQuick\nItem {}\n')
        self.write('tests/staticgates-unqualified.tsv', '# profile quickshell-present\n'
                   'ui/Old.qml\t1\tasker\tDeclared QML id.\n')
        with self.qmllint() as called:
            self.assertEqual(gates.qml_undeclared_read(self.root, ['ui/Old.qml', 'ui/A.qml']), (1, []))
        self.assertEqual(called.call_args.args[0][QMLLINT_FIRST_FILE_ARGUMENT:], ['ui/A.qml'])

    def test_F11_qmllint_skips_inventory_with_only_missing_files(self):
        with mock.patch.dict(os.environ, {'FLEA_QMLLINT': str(self.root / 'unavailable')}):
            self.assertEqual(gates.qml_undeclared_read(self.root, ['ui/Old.qml'], sample=True), (0, []))

    def test_F12_markdown_setext_heading_passes(self):
        self.write('README.md', 'Install\n=======\n')
        self.assertEqual(gates.conflict_marker(self.root, ['README.md']), (1, []))

    def test_F12_conflict_separator_inside_span_is_rejected(self):
        self.write('README.md', '<<<<<<< left\nInstall\n=======\nSetup\n>>>>>>> right\n')
        self.assertEqual(gates.conflict_marker(self.root, ['README.md']),
                         (1, [f'README.md:{line}: unresolved conflict marker' for line in (1, 3, 5)]))

    def test_F12_separator_requires_complete_span_in_same_file(self):
        self.write('left.txt', '<<<<<<< left\n=======\n')
        self.write('README.md', 'Install\n=======\n>>>>>>> right\n')
        self.assertEqual(gates.conflict_marker(self.root, ['left.txt', 'README.md']),
                         (2, ['left.txt:1: unresolved conflict marker', 'README.md:3: unresolved conflict marker']))

    def test_F13_shell_ansi_c_and_plain_single_quotes(self):
        for source in ("printf $'it\\'s'; x    y\n", "printf 'a\\' ; x    y\n"):
            with self.subTest(source=source):
                file = self.write('sample.sh', source)
                syntax = subprocess.run(['/bin/bash', '-n', str(file)], capture_output=True, text=True)
                self.assertEqual(syntax.returncode, 0, syntax.stderr)
                self.assertEqual(gates.fused_line(self.root, ['sample.sh']),
                                 (1, ['sample.sh:1: fused code gap (4 spaces)']))

    def test_F14_shell_unquoted_escapes_do_not_hide_code(self):
        for source in (r"printf \$'a\' ; x    y", r"echo \' ; x    y",
                       r"printf \\$'it\'s'; x    y", r"printf \\\$'a\' ; x    y"):
            with self.subTest(source=source):
                file = self.write('sample.sh', source + '\n')
                syntax = subprocess.run(['/bin/bash', '-n', str(file)], capture_output=True, text=True)
                self.assertEqual(syntax.returncode, 0, syntax.stderr)
                self.assertEqual(gates.fused_line(self.root, ['sample.sh']),
                                 (1, ['sample.sh:1: fused code gap (4 spaces)']))

    def test_F15_shell_non_heredoc_openers_do_not_hide_code(self):
        for opener in ('echo "<<EOF"', '# <<EOF', '(( a << 2 ))', 'x=$(( a << 2 ))', 'cat <<<EOF'):
            with self.subTest(opener=opener):
                file = self.write('sample.sh', opener + '\nx    y\n')
                syntax = subprocess.run(['/bin/bash', '-n', str(file)], capture_output=True, text=True)
                self.assertEqual(syntax.returncode, 0, syntax.stderr)
                self.assertEqual(gates.fused_line(self.root, ['sample.sh']),
                                 (1, ['sample.sh:2: fused code gap (4 spaces)']))

    def test_F15_shell_nested_and_multiline_arithmetic_keeps_code_visible(self):
        for arithmetic in ('(( (a + 1) << 2 ))', 'x=$(( (a + 1) << 2 ))',
                           '((\n a << 2\n))', 'x=$((\n a << 2\n))'):
            with self.subTest(arithmetic=arithmetic):
                source = arithmetic + '\nx    y\n'
                file = self.write('sample.sh', source)
                syntax = subprocess.run(['/bin/bash', '-n', str(file)], capture_output=True, text=True)
                self.assertEqual(syntax.returncode, 0, syntax.stderr)
                self.assertEqual(gates.fused_line(self.root, ['sample.sh']),
                                 (1, [f'sample.sh:{source.count(chr(10))}: fused code gap (4 spaces)']))

    def test_F15_shell_real_heredoc_masks_only_its_body(self):
        for opener in ('cat <<EOF', "cat <<'EOF'", 'cat <<"EOF"', 'cat <<-EOF', "cat <<<EOF <<'EOF'",
                       "(( a << 2 )); cat <<'EOF'"):
            with self.subTest(opener=opener):
                file = self.write('sample.sh', opener + '\nx    y\nEOF\nx    y\n')
                syntax = subprocess.run(['/bin/bash', '-n', str(file)], capture_output=True, text=True)
                self.assertEqual(syntax.returncode, 0, syntax.stderr)
                self.assertEqual(gates.fused_line(self.root, ['sample.sh']),
                                 (1, ['sample.sh:4: fused code gap (4 spaces)']))

    def assert_qml_rejected(self, file, source, diagnostic):
        self.write(file, source)
        count, errors = gates.qml_duplicate_member(self.root, [file])
        self.assertEqual(count, 1)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn(diagnostic, errors[0])
        self.assertTrue(errors[0].startswith(file + ':'), errors)
        # Sample input: ui/A.qml:4:18: error: Duplicate property name
        self.assertRegex(errors[0], r':\d+:\d+: error: ')

    def test_duplicate_member_review_fixtures(self):
        for name, (file, source, diagnostic) in DUPDECL_FIXTURES.items():
            with self.subTest(fixture=name):
                self.write(file, source)
                count, errors = gates.qml_duplicate_member(self.root, [file])
                self.assertEqual(count, 1)
                if diagnostic is None:
                    self.assertEqual(errors, [])
                else:
                    self.assertEqual(len(errors), 1, errors)
                    self.assertIn(diagnostic, errors[0])
                    self.assertTrue(errors[0].startswith(file + ':'), errors)

    def test_duplicate_member_historical_pane(self):
        fixture = Path(__file__).with_name('staticgates-pane-338b343f.qml.txt')
        self.assert_qml_rejected('ui/Pane.qml', fixture.read_text(), 'Duplicate alias name')

    def test_duplicate_member_qt_declaration_kinds_and_ids(self):
        declarations = {
            'property int value: 0': 'Duplicate property name',
            'readonly property int value: 0': 'Duplicate property name',
            'default property list<QtObject> value': 'Duplicate property name',
            'required property int value': 'Duplicate property name',
            'property alias value: root.width': 'Duplicate alias name',
            'signal value()': 'Duplicate signal name',
            'function value() {}': 'Duplicate method name',
            'id: root': 'Property value set multiple times',
        }
        for declaration, diagnostic in declarations.items():
            with self.subTest(declaration=declaration):
                self.assert_qml_rejected('tests/Decl.qml',
                                         'QtObject {\n' + declaration + '\n' + declaration + '\n}\n', diagnostic)

    def test_duplicate_member_qt_sibling_and_nested_scopes_pass(self):
        self.write('ui/A.qml', 'Item { property int value: 0; function run() {}\n'
                   'QtObject { id: first; property int value: 1; signal done(); function run() {} }\n'
                   'QtObject { id: second; property int value: 2; signal done(); function run() {} }\n}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/A.qml']), (1, []))

    def test_duplicate_member_qt_bound_and_inline_objects_are_checked(self):
        sources = ('QQ.Item { property QtObject child: QQ.QtObject { property int value: 0; property int value: 1 } }',
                   'Item { data: [QtObject { property int value: 0; property int value: 1 }] }',
                   'Item { component Inner: QtObject { property int value: 0; property int value: 1 } }')
        for source in sources:
            with self.subTest(source=source):
                self.assert_qml_rejected('ui/A.qml', source, 'Duplicate property name')

    def test_duplicate_member_qt_does_not_resolve_imports(self):
        self.write('ui/A.qml', 'import Absent.Module\nItem { property int value: 0 }\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/A.qml']), (1, []))
        self.assert_qml_rejected('ui/A.qml', 'import Absent.Module\n'
                                 'Item { property int value: 0; property int value: 1 }\n', 'Duplicate property name')

    def test_duplicate_member_js_declaration_kinds_and_names(self):
        for declaration in ('function value$() {}', 'var $value = 0', 'let _value = 0', 'const value1 = 0'):
            with self.subTest(declaration=declaration):
                name = declaration.split()[1].split('(')[0]
                self.write('ui/A.js', declaration + '\n' + declaration + '\n')
                self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/A.js']),
                                 (1, [f'ui/A.js:2: {name} declared again (first at 1)']))
        self.write('ui/A.js', 'function wire() {}\nvar wire = 0\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/A.js']),
                         (1, ['ui/A.js:2: wire declared again (first at 1)']))

    def test_duplicate_member_js_plain_and_pragma_library(self):
        for pragma in ('', '.pragma library\n'):
            with self.subTest(pragma=pragma):
                self.write('ui/js/Twin.js', pragma + 'function wire() {}\nfunction wire() {}\n')
                first = 2 if pragma else 1
                self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/js/Twin.js']),
                                 (1, [f'ui/js/Twin.js:{first + 1}: wire declared again (first at {first})']))

    def test_duplicate_member_js_nested_and_expression_names_pass(self):
        source = ('function wire() { function wire() {}; return {wire: 1} }\n'
                  'var one = function wire() {}\nvar two =\n    function wire() {}\n'
                  'var object = {wire: function wire() {}}\n'
                  'if (true) { function wire() {} }\n')
        self.write('ui/Plain.js', source)
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Plain.js']), (1, []))
        self.write('ui/Plain.js', source + 'function wire() {}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Plain.js']),
                         (1, ['ui/Plain.js:7: wire declared again (first at 1)']))

    def test_duplicate_member_qmlcachegen_override_and_fallback(self):
        with mock.patch.dict(os.environ, {'FLEA_QMLCACHEGEN': sys.executable}):
            self.assertEqual(gates.qmlcachegen_binary(), sys.executable)
        with mock.patch.dict(os.environ, {'FLEA_QMLCACHEGEN': str(self.root / 'missing')}):
            with mock.patch.object(gates, 'QMLCACHEGEN_PATHS', (sys.executable,)):
                with self.assertRaisesRegex(ValueError, 'FLEA_QMLCACHEGEN is not an executable file: ' + str(self.root / 'missing')):
                    gates.qmlcachegen_binary()
        self.write('ui/plain.txt', 'not a compiler\n')
        with mock.patch.dict(os.environ, {'FLEA_QMLCACHEGEN': str(self.root / 'ui/plain.txt')}):
            with mock.patch.object(gates, 'QMLCACHEGEN_PATHS', (sys.executable,)):
                with self.assertRaisesRegex(ValueError, 'not an executable file'):
                    gates.qmlcachegen_binary()
        env = {k: v for k, v in os.environ.items() if k != 'FLEA_QMLCACHEGEN'}
        with mock.patch.dict(os.environ, env, clear=True):
            with mock.patch.object(gates, 'QMLCACHEGEN_PATHS', (str(self.root / 'absent'), sys.executable)):
                self.assertEqual(gates.qmlcachegen_binary(), sys.executable)

    def test_duplicate_member_missing_qmlcachegen_is_loud(self):
        override = str(self.root / 'override')
        fallback = str(self.root / 'fallback')
        env = {k: v for k, v in os.environ.items() if k != 'FLEA_QMLCACHEGEN'}
        with mock.patch.dict(os.environ, env, clear=True):
            with mock.patch.object(gates, 'QMLCACHEGEN_PATHS', (override, fallback)):
                with self.assertRaisesRegex(ValueError, 'qmlcachegen unavailable; tried: ' + override + ', ' + fallback):
                    gates.compile_qml(self.root, ['ui/A.qml'])
        self.assertEqual(gates.compile_qml(self.root, []), [])

    def test_duplicate_member_reports_each_compiler_error_line(self):
        self.write('ui/A.qml', 'Item {}\n')
        stderr = 'Error compiling qml file: ui/A.qml:4:18: error: Duplicate property name\nui/A.qml:6:18: error: Duplicate property name\n'
        with mock.patch.object(gates.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', stderr)):
            self.assertEqual(gates.compile_qml(self.root, ['ui/A.qml']),
                             ['ui/A.qml:4:18: error: Duplicate property name', 'ui/A.qml:6:18: error: Duplicate property name'])

    def test_duplicate_member_compiler_timeout_and_artifact_are_checked(self):
        self.write('ui/A.qml', 'Item {}\n')
        with mock.patch.object(gates.subprocess, 'run', side_effect=subprocess.TimeoutExpired('qmlcachegen', gates.QMLCACHEGEN_TIMEOUT_SECONDS)) as called:
            with self.assertRaises(subprocess.TimeoutExpired):
                gates.compile_qml(self.root, ['ui/A.qml'])
        self.assertEqual(called.call_args.kwargs['timeout'], gates.QMLCACHEGEN_TIMEOUT_SECONDS)
        with mock.patch.object(gates.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')):
            self.assertEqual(gates.compile_qml(self.root, ['ui/A.qml']),
                             ['ui/A.qml: qmlcachegen returned success without bytecode'])

    def test_duplicate_member_filters_paths_and_skips_missing_files(self):
        files = ('ui/A.qml', 'tests/nested/A.qml', 'ui/js/A.js', 'ui/Plain.js',
                 'tests/js/A.js', 'elsewhere/A.qml', 'ui/A.txt')
        for file in files:
            self.write(file, 'Item { property int value: 0; property int value: 1 }\n'
                       if file.endswith('.qml') else 'function value() {}\nfunction value() {}\n')
        count, errors = gates.qml_duplicate_member(self.root, ['ui/Missing.qml', *files])
        self.assertEqual(count, 4)
        self.assertEqual({error.split(':')[0] for error in errors}, set(files[:4]))

    def test_duplicate_member_cli_uses_tracked_inventory_and_qt_diagnostic(self):
        self.write('ui/Pane.qml', 'Item {\nproperty alias wire: root.width\nproperty alias wire: root.width\n}\n')
        output = io.StringIO()
        with mock.patch.object(sys, 'argv', ['staticgates.py', '--gate', 'qml-duplicate-member',
                                            '--root', str(self.root)]):
            with mock.patch.object(gates, 'inventory', return_value=['ui/Pane.qml']) as inventory:
                with contextlib.redirect_stdout(output):
                    result = gates.main()
        self.assertEqual(result, 1)
        inventory.assert_any_call(self.root, tracked=True)
        self.assertIn('STATICGATE qml-duplicate-member FAIL ui/Pane.qml:3:', output.getvalue())
        self.assertIn('Duplicate alias name\nSTATICGATES FAIL gates=1\n', output.getvalue())

    def test_undeclared_read_reports_stale_allowance(self):
        self.write('ui/A.qml', 'asker\nItem {}\n')
        warnings = {'ui/A.qml': [{'id': 'unqualified', 'line': 1, 'column': 1, 'length': 5}]}
        self.write('tests/staticgates-unqualified.tsv', '# profile quickshell-missing\n'
                   'ui/A.qml\t1\tasker\tDeclared QML id.\n'
                   'ui/A.qml\t2\tstale\tDeclared QML id.\n')
        with self.qmllint(warnings, missing=('Quickshell',)):
            with mock.patch.object(gates, 'inventory', return_value=['ui/A.qml']):
                count, errors = gates.qml_undeclared_read(self.root, ['ui/A.qml'])
        self.assertEqual(count, 1)
        self.assertEqual(errors, ['ui/A.qml:2: stale unqualified allowance stale'])

    def test_undeclared_read_planted_name_is_rejected(self):
        self.write('ui/A.qml', 'asker\nItem {}\n')
        warnings = {'ui/A.qml': [{'id': 'unqualified', 'line': 1, 'column': 1, 'length': 5}]}
        self.write('tests/staticgates-unqualified.tsv', '# profile quickshell-missing\n')
        with self.qmllint(warnings, missing=('Quickshell',)):
            with mock.patch.object(gates, 'inventory', return_value=['ui/A.qml']):
                count, errors = gates.qml_undeclared_read(self.root, ['ui/A.qml'])
        self.assertEqual(count, 1)
        self.assertEqual(errors, ['ui/A.qml:1: new unqualified read asker'])

    def test_probe_names_the_modules_qmllint_failed_to_import(self):
        modules = gates.QMLLINT_PROBED_MODULES
        noise = [{'id': 'import', 'message': 'Warnings occurred while importing module "Quickshell":'},
                 {'id': 'unqualified', 'message': 'Failed to import Quickshell. in another diagnostic'},
                 self.import_failure('QtQuick'), self.import_failure('Absent.Module')]
        for missing in ((), *[(module,) for module in modules], modules):
            with self.subTest(missing=missing):
                seen = []

                def run(command, **kwargs):
                    seen.append((command, Path(command[-1]).read_text()))
                    data = {'files': [{'filename': 'Probe.qml', 'warnings': noise + [self.import_failure(m) for m in missing]}]}
                    Path(command[QMLLINT_JSON_ARGUMENT]).write_text(json.dumps(data))
                    return subprocess.CompletedProcess(command, 1, stdout='', stderr='')

                with mock.patch.object(gates.subprocess, 'run', side_effect=run):
                    self.assertEqual(gates.qmllint_missing_modules(self.root, 'qmllint'), set(missing))
                command, source = seen[0]
                self.assertNotIn('-I', command)
                for module in modules:
                    self.assertIn(f'import {module}\n', source)

    def test_probe_failure_fails_the_gate_naming_the_probe(self):
        self.write('ui/A.qml', 'import QtQuick\nItem {}\n')
        self.write('tests/staticgates-unqualified.tsv', '# profile quickshell-present\n# profile quickshell-missing\n')

        def answers(text):
            def run(command, **kwargs):
                Path(command[QMLLINT_JSON_ARGUMENT]).write_text(text)
                return subprocess.CompletedProcess(command, 1, stdout='', stderr='')
            return run

        failures = {
            'timeout': ({'side_effect': subprocess.TimeoutExpired('qmllint', gates.QMLLINT_TIMEOUT_SECONDS)}, 'timed out after 120 s'),
            'no JSON': ({'return_value': subprocess.CompletedProcess([], 2, '', 'boom')}, 'returned 2 without JSON: boom'),
            'unreadable JSON': ({'side_effect': answers('not json')}, 'invalid JSON: '),
            'no files': ({'side_effect': answers('{}')}, "JSON lacks 'files'"),
            'files not a list': ({'side_effect': answers('{"files": 1}')}, 'JSON of the wrong shape: '),
            'file not an object': ({'side_effect': answers('{"files": [1]}')}, 'JSON of the wrong shape: '),
            'vanished binary': ({'side_effect': FileNotFoundError('qmllint vanished')}, 'qmllint vanished'),
        }
        for name, (kwargs, reason) in failures.items():
            with self.subTest(failure=name), mock.patch.dict(os.environ, {'FLEA_QMLLINT': sys.executable}):
                with mock.patch.object(gates.subprocess, 'run', **kwargs) as called:
                    count, errors = gates.qml_undeclared_read(self.root, ['ui/A.qml'])
                self.assertEqual(count, 1)
                self.assertEqual(len(errors), 1, errors)
                self.assertTrue(errors[0].startswith('qmllint import probe failed: ' + reason), errors)
                self.assertEqual(called.call_count, 1, 'the main qmllint run followed a failed probe')
        output = io.StringIO()
        with mock.patch.dict(os.environ, {'FLEA_QMLLINT': sys.executable}):
            with mock.patch.object(gates.subprocess, 'run', **failures['timeout'][0]):
                with mock.patch.object(sys, 'argv', ['staticgates.py', '--gate', 'qml-undeclared-read', '--root', str(self.root)]):
                    with mock.patch.object(gates, 'inventory', return_value=['ui/A.qml']):
                        with contextlib.redirect_stdout(output):
                            self.assertEqual(gates.main(), 1)
        self.assertEqual(output.getvalue(), 'STATICGATE qml-undeclared-read FAIL qmllint import probe failed: timed out after 120 s\n'
                         'STATICGATES FAIL gates=1\n')

    def test_profile_follows_the_probe_and_the_stub_follows_the_profile(self):
        self.write('ui/A.qml', 'asker\nItem {}\n')
        self.stub_roots()
        warnings = {'ui/A.qml': [{'id': 'unqualified', 'line': 1, 'column': 1, 'length': 5}]}
        self.write('tests/staticgates-unqualified.tsv', '# profile quickshell-present\n# profile quickshell-missing\n'
                   'ui/A.qml\t1\tasker\tDeclared QML id.\n')
        for missing, errors in (((), ['ui/A.qml:1: new unqualified read asker']), (('Quickshell',), [])):
            with self.subTest(missing=missing), self.qmllint(warnings, missing) as called:
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    self.assertEqual(gates.qml_undeclared_read(self.root, ['ui/A.qml']), (1, errors))
                self.assertEqual(self.import_roots(called.call_args.args[0]), {gates.QMLLINT_ALWAYS_STUB, *missing})
                self.assertEqual(output.getvalue(), f'STATICGATE qml-undeclared-read PROBE missing={",".join(missing) or "none"}\n')

    def test_each_stub_is_on_the_import_root_only_where_its_module_is_missing(self):
        self.write('ui/A.qml', 'import QtQuick\nItem {}\n')
        self.write('tests/staticgates-unqualified.tsv', '# profile quickshell-present\n# profile quickshell-missing\n')
        self.stub_roots()
        modules = gates.QMLLINT_PROBED_MODULES
        for module in modules:
            for missing in ((module,), tuple(other for other in modules if other != module)):
                with self.subTest(module=module, missing=missing), self.qmllint(missing=missing) as called:
                    self.assertEqual(gates.qml_undeclared_read(self.root, ['ui/A.qml']), (1, []))
                    roots = self.import_roots(called.call_args.args[0])
                    self.assertEqual(roots, {gates.QMLLINT_ALWAYS_STUB, *missing})
                    self.assertEqual(module in roots, module in missing)

    @unittest.skipUnless(REAL_QMLLINT.is_file(), 'qmllint binary is required to prove the probe reads its message')
    def test_probe_reads_the_message_the_real_qmllint_writes(self):
        self.assertEqual(gates.qmllint_missing_modules(self.root, str(REAL_QMLLINT), ('Absent.Module', 'QtQml')), {'Absent.Module'})

    @unittest.skipUnless(REAL_QMLLINT.is_file(), 'qmllint binary is required to prove the stubs resolve')
    def test_qmllint_stubs_resolve_tooling_names_but_hide_no_planted_read(self):
        shutil.copytree(Path(gates.__file__).parent / 'staticgates-stubs', self.root / gates.QMLLINT_STUBS)
        self.write('ui/Tooling.qml', '\n'.join((
            'import QtQuick',
            'import QtQuick.Shapes',
            'import QtQuick.Layouts',
            'import Quickshell',
            'import Quickshell.Io',
            'import Quickshell.Wayland',
            'import qs.Commons',
            'Item {',
            '    property int renderer: Shape.CurveRenderer',
            '    property int cap: ShapePath.RoundCap',
            '    property var palette: Style',
            '    property var ink: Color',
            '    property var helper: Util',
            '    property var edge: Border',
            '    property var shell: Quickshell',
            '    property int failure: FileViewError.Success',
            '    property int layer: WlrLayer.Bottom',
            '    property int focus: WlrKeyboardFocus.None',
            '    property int exclusion: ExclusionMode.Ignore',
            '    property int planted: asker',
            '    Item {',
            '        Layout.fillWidth: true',
            '        WlrLayershell.namespace: "probe"',
            '    }',
            '}',
            '')))
        every = set(gates.QMLLINT_PROBED_MODULES)
        with contextlib.redirect_stdout(io.StringIO()), mock.patch.object(gates, 'qmllint_missing_modules', return_value=every):
            count, errors = gates.qml_undeclared_read(self.root, ['ui/Tooling.qml'], sample=True)
        self.assertEqual(count, 1)
        names = {error.rsplit(' ', 1)[-1] for error in errors}
        self.assertEqual(names, {'asker'})


if __name__ == '__main__':
    unittest.main(verbosity=2)
