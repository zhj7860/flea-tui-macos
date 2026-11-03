#!/usr/bin/env python3
"""Reject direct OEM links and exercise the shared headless fixture contract."""
import os
from pathlib import Path
import re
import subprocess
import sys

# External-stub callers must finish promptly even if a loop's refusal guard regresses.
CALLER_TIMEOUT_SECONDS = 10


def native_capture_source(path, line):
    # This real-window RHI specimen needs OEM compositor reloads; copies remain offscreen-scanned.
    native = Path(__file__).resolve().with_name('ui-captures-html.sh')
    return (path.resolve() == native
            and line.strip() == 'ln -s "$(readlink -m "$repo/ui/boot/Commons")" "$dir/boot/Commons"')


def direct_sources(root):
    bad = []
    sources = ('ui/boot/' + 'Commons', 'ui/' + 'Commons', '/usr/share/omarchy/shell/' + 'Commons')
    for path in sorted(root.glob('*.sh')):
        if path.name == 'headless-commons.sh':
            continue
        for n, line in enumerate(path.read_text().splitlines(), 1):
            # Sample input: ln -s "$(readlink -f ui/boot/Commons/)" "$root/config/Commons" also links the live OEM source.
            if (not line.lstrip().startswith('#') and not native_capture_source(path, line)
                    and any(re.search(r'(?<![\w$])' + re.escape(source) + r'(?!\w)', line) for source in sources)):
                bad.append(f'{path}:{n}: use headless_commons instead of a direct OEM Commons source')
    return bad


def call_scopes(source, comments=None):
    depth = 0
    cases = []
    scopes = {}
    quoted = False
    substitutions = []
    heredocs = []
    arithmetic = []
    conditionals = []
    groups = []
    closed_calls = set()
    pipe_next = False
    command_start = True
    word_start = True
    unmatched_tail = False
    unknown_pipeline = False
    functions = {}
    function_groups = {}
    owners = {}
    commands = {}
    uncertain_dispatch = False
    references = []
    pending_function = None
    prefix_assignment = False
    array_depth = None
    command_name = None
    parameter_depth = 0
    shell_boundaries = '();|&<>'
    compound_ends = {'{': '}', 'if': 'fi', 'for': 'done', 'while': 'done', 'until': 'done', 'select': 'done', 'case': 'esac'}
    # Sample input: prepare() { and function prepare { are supported literal function headers, not brace arguments.
    function_head = re.compile(r'(?:^|[;{}])\s*(?:function\s+)?\w+\s*\(\s*\)\s*$|(?:^|[;{}])\s*function\s+\w+\s*$')
    # Sample input: prepare() followed by a newline and { is the same literal definition as function prepare {.
    function_header = re.compile(r'(?:function[ \t]+([^\s(){};|&<>]+)(?:[ \t]*\([ \t]*\))?|([^\s(){};|&<>]+)[ \t]*\([ \t]*\))(?=[ \t\r\n#{}(])')
    words = re.compile(r'\w+|;;&|;;|;&|&&|\|\||\|&|[();{}!|&]')
    delimiters = re.compile(r'(?<!<)<<(-?)(?!<)[ \t]*[\'"]?([A-Za-z_]\w*)[\'"]?')
    redirects = re.compile(r'&>>?|[<>]&')
    literal_executable = re.compile(r'(?:[A-Za-z0-9_./:+-]+|\[)(?=$|[\s();|&<>])')
    assignment_head = re.compile(r'[A-Za-z_]\w*\+?=')
    dispatchers = ('eval', 'trap', 'command', 'builtin', 'exec', 'export', 'declare', 'typeset')
    command_query = re.compile(r'[ \t]+-[vV](?=$|[\s();|&<>])')
    at = 0
    while at < len(source):
        char = source[at]
        # Sample input: pre"pare", pre\pare and "$target" are unsupported executable words; prepare "pre"pare is argument data.
        data = quoted or arithmetic or parameter_depth or array_depth is not None or conditionals and conditionals[-1] == depth or cases and cases[-1] == 'pattern'
        continuation = char == '\\' and source[at + 1:at + 2] == '\n'
        if not data and not continuation and word_start and (command_start or prefix_assignment) and not char.isspace() and char not in '#;|&(){}!':
            assignment = assignment_head.match(source, at)
            if assignment:
                prefix_assignment = True
                command_start = False
                command_name = None
                if source[assignment.end():assignment.end() + 1] == '(':
                    array_depth = depth
            else:
                prefix_assignment = False
                command_start = True
                literal = literal_executable.match(source, at)
                command_name = literal[0] if literal else None
                if literal is None and not source.startswith('[[', at):
                    uncertain_dispatch = True
        # Sample input: checks=${checks%% *} contains parameter data, while ${name} as an executable remains opaque.
        if source.startswith('${', at):
            parameter_depth += 1
        elif char == '}' and parameter_depth:
            parameter_depth -= 1
        if char == '\\':
            if source[at + 1:at + 2] != '\n':
                command_start = False
                word_start = False
            at += 2
            continue
        if char == '\n' and heredocs:
            at += 1
            for delimiter, strip_tabs in heredocs:
                while at < len(source):
                    end = source.find('\n', at)
                    end = len(source) if end < 0 else end + 1
                    # Sample input: <<EOF requires column zero; <<-EOF permits leading tabs, never spaces or trailing whitespace.
                    line = source[at:end].removesuffix('\n')
                    if strip_tabs:
                        line = line.lstrip('\t')
                    at = end
                    if line == delimiter:
                        break
            heredocs.clear()
            command_start = True
            word_start = True
            prefix_assignment = False
            command_name = None
            continue
        if char == '"':
            if not quoted and command_name in dispatchers:
                literal = re.match(r'"([A-Za-z_]\w*)"', source[at:])
                if literal:
                    references.append(literal[1])
            quoted = not quoted
            command_start = False
            word_start = False
            at += 1
            continue
        # Sample input: <(printf x)#suffix and >(cat)#suffix join a word just as $(printf x)#suffix does.
        if source.startswith('$(', at) or not quoted and source[at:at + 2] in ('<(', '>('):
            if source.startswith('$((', at):
                arithmetic.append(depth)
            # Sample input: prepare > >(cat; :) | cat keeps the caller's pending pipeline context outside the substitution.
            substitutions.append((depth, quoted, closed_calls, unmatched_tail, prefix_assignment, array_depth, command_name, parameter_depth))
            closed_calls = set()
            unmatched_tail = False
            prefix_assignment = False
            array_depth = None
            command_name = None
            parameter_depth = 0
            quoted = False
            command_start = True
            word_start = True
            depth += 1
            at += 2
            continue
        if quoted:
            at += 1
            continue
        # Sample input: $'it\'s' keeps escapes, ordinary single quotes do not; backticks run a child and hide no accepted call.
        if char in "'`":
            command_start = False
            word_start = False
            ansi = char == '`' or at > 0 and source[at - 1] == '$'
            pattern = re.escape(char) + (r'(?:\\.|[^' + re.escape(char) + r'\\])*' if ansi else "[^']*") + re.escape(char)
            literal = re.compile(pattern, re.S).match(source, at)
            if literal and command_name in dispatchers:
                references.append(literal[0][1:-1])
            at = len(source) if literal is None else literal.end()
            continue
        # Sample input: (# comment ) starts a comment; $(printf x)#suffix and \)#suffix continue the current shell word.
        if char == '#' and word_start:
            if comments is not None:
                comments[source.count('\n', 0, at) + 1] = at - source.rfind('\n', 0, at) - 1
            end = source.find('\n', at)
            at = len(source) if end < 0 else end
            continue
        # Sample input: [[ x == y || if == if ]] contains data words, but $(commands) inside it still run in a child.
        if not arithmetic and command_start and word_start and source.startswith('[[', at) and source[at + 2:at + 3].isspace():
            conditionals.append(depth)
            command_start = False
            word_start = True
            at += 2
            continue
        if conditionals and conditionals[-1] == depth:
            # Sample input: ([[ x == x ]]) closes the conditional before closing its containing subshell.
            if word_start and source.startswith(']]', at) and (at + 2 == len(source) or source[at + 2].isspace() or source[at + 2] in shell_boundaries):
                conditionals.pop()
                at += 2
                word_start = False
            else:
                word_start = char.isspace()
                at += 1
            command_start = False
            continue
        # Sample input: cat <<'TEXT' skips its body; cat <<<ready is a here-string, never a heredoc at either trailing <<.
        heredoc = delimiters.match(source, at) if not arithmetic else None
        if heredoc:
            heredocs.append((heredoc[2], heredoc[1] == '-'))
            at += len(heredoc[0])
            continue
        # Sample input: } 2>&1 redirects; } >out\>& ends with an escaped filename character and a real background &.
        redirect = redirects.match(source, at) if not arithmetic else None
        if redirect:
            at = redirect.end()
            word_start = True
            command_start = False
            continue
        if source.startswith('((', at):
            arithmetic.append(depth)
        token = words.match(source, at)
        if token is None:
            if char == '\n':
                command_start = True
                closed_calls.clear()
                unmatched_tail = False
                prefix_assignment = False
                command_name = None
            elif not char.isspace():
                command_start = False
            word_start = char.isspace() or char in '<>'
            at += 1
            continue
        word = token[0]
        line = source.count('\n', 0, at) + 1
        # Sample input: (( if || case )) and $(( if + case )) use variable names, not shell reserved words.
        if arithmetic and word not in ('(', ')'):
            at = token.end()
            command_start = False
            word_start = False
            continue
        pattern_close = word == ')' and not arithmetic and cases and cases[-1] == 'pattern'
        # Sample input: echo } is an argument; fi | cat closes a compound command only at a reserved-word position.
        separated = token.end() == len(source) or source[token.end()].isspace() or source[token.end()] in shell_boundaries
        keyword = command_start and word_start and separated
        in_pattern = not arithmetic and cases and cases[-1] == 'pattern'
        header = function_header.match(source, at) if keyword and not in_pattern else None
        if header:
            pending_function = header[1] or header[2]
            at = header.end()
            command_start = word_start = True
            continue
        opens_brace = word == '{' and not in_pattern and word_start and separated and (command_start or function_head.search(source[:at].rsplit('\n', 1)[-1]))
        opens_compound = opens_brace or keyword and word in compound_ends and not in_pattern
        # Sample input: printf '' | case x in esac closes an empty case before the next parent-shell guard.
        case_end = word == 'esac' and cases and word_start and separated and (command_start or in_pattern) and not re.match(r'\s*\)', source[token.end():])
        closes_compound = keyword and word in ('}', 'fi', 'done') and not in_pattern or case_end
        joins_word = False
        array_ended = False
        at += len(word)
        # Sample input: command -- "$@" can invoke eval; only literal command -v/-V forms query without executing.
        if keyword and not in_pattern and word in ('command', 'builtin'):
            uncertain_dispatch |= word != 'command' or not command_query.match(source, at)
        owner = next((function_groups[id(calls)] for _, _, calls in reversed(groups) if id(calls) in function_groups), None)
        # Sample input: prepare | cat, a subshell's prepare and wrapper() { prepare; } inherit their actual call context.
        if keyword and not opens_compound and word not in ('}', 'fi', 'done', 'esac', 'then', 'else', 'elif', 'do', 'in', '!', 'time') and re.fullmatch(r'\w+', word):
            site = (line, token.start())
            commands[site] = word
            owners[site] = owner
            scopes[site] = max(depth, int(pipe_next or any(piped for _, piped, _ in groups)))
            closed_calls.add(site)
            for _, _, calls in groups:
                calls.add(site)
        elif command_name in dispatchers and word_start and separated:
            references.append(word)
        # Sample input: (\n headless_commons "$root" || exit 1\n) exits only a child; case x in x) is not a subshell close.
        if word == 'headless_commons':
            owners[line] = owner
            scopes[line] = max(depth, int(any(piped for _, piped, _ in groups)))
            for _, _, calls in groups:
                calls.add(line)
        elif word == 'case' and keyword and (not cases or cases[-1] == 'body'):
            cases.append('subject')
        elif word == 'in' and word_start and separated and cases and cases[-1] == 'subject':
            cases[-1] = 'pattern'
        elif case_end:
            cases.pop()
        elif in_pattern:
            if word == ')':
                cases[-1] = 'body'
        elif word in (';;', ';&', ';;&') and cases:
            cases[-1] = 'pattern'
        elif word == '(':
            depth += 1
        elif word == ')':
            depth = max(0, depth - 1)
            if array_depth == depth:
                array_depth = None
                array_ended = True
            if arithmetic and depth == arithmetic[-1]:
                arithmetic.pop()
            if substitutions and depth == substitutions[-1][0]:
                _, quoted, closed_calls, unmatched_tail, prefix_assignment, array_depth, command_name, parameter_depth = substitutions.pop()
                joins_word = True
        # Sample input: if true; then\n headless_commons "$root" || exit 1\nfi | cat is an unsupported compound pipeline.
        if opens_compound:
            groups.append((compound_ends[word], pipe_next, set()))
            if pending_function is not None:
                functions.setdefault(pending_function, []).append(groups[-1][2])
                function_groups[id(groups[-1][2])] = pending_function
                pending_function = None
            closed_calls.clear()
            unmatched_tail = False
        elif closes_compound:
            if groups and groups[-1][0] == word:
                _, _, closed_calls = groups.pop()
            else:
                closed_calls.clear()
                unmatched_tail = True
        elif word in ('|', '|&', '&'):
            for call in closed_calls:
                scopes[call] = max(scopes[call], 1)
            closed_calls.clear()
            unknown_pipeline |= unmatched_tail
        elif word in (';', ';;', ';&', ';;&', '&&', '||'):
            closed_calls.clear()
            unmatched_tail = False
        if word not in ('!', 'time'):
            pipe_next = word in ('|', '|&')
        if word in (';', ';;', ';&', ';;&', '&&', '||', '|', '|&', '&', '(', ')') and not array_ended:
            prefix_assignment = False
            command_name = None
        # Sample input: echo if case in esac keeps argument words; ; case and a case arm's ) start commands.
        word_start = not joins_word and word in (';', ';;', ';&', ';;&', '&&', '||', '|', '|&', '&', '(', ')')
        command_start = (word in (';', ';;', ';&', ';;&', '&&', '||', '|', '|&', '&', '(') or bool(pattern_close) or bool(opens_brace)
                         or command_start and word in ('if', 'elif', 'while', 'until', 'then', 'else', 'do', 'time', '!'))
    if unknown_pipeline:
        scopes = {line: max(scope, 1) for line, scope in scopes.items()}
    resolved = {}

    def function_scope(name, visiting):
        if name in resolved:
            return resolved[name]
        # Sample input: target=prepare; "$target" and unused/recursive definitions have no proven literal invocation context.
        sites = [site for site, command in commands.items() if command == name]
        if uncertain_dispatch or name in visiting or len(functions.get(name, [])) != 1 or name in references or not sites:
            return 1
        resolved[name] = max(max(scopes[site], function_scope(owners[site], visiting | {name}) if owners[site] else 0) for site in sites)
        return resolved[name]

    return {line: max(scope, function_scope(owners[line], set()) if owners.get(line) else 0)
            for line, scope in scopes.items() if isinstance(line, int)}


def unchecked_calls(root):
    bad = []
    for path in sorted(root.glob('*.sh')):
        if path.name == 'headless-commons.sh':
            continue
        source = path.read_text()
        if 'headless_commons' not in source:
            continue
        comments = {}
        scopes = call_scopes(source, comments)
        for n, line in enumerate(source.splitlines(), 1):
            # Sample input: helper "$root" # || exit 1 has no guard; quoted "#" and escaped \# remain argument data.
            line = line[:comments[n]] if n in comments else line
            # Sample input: headless_commons "$root" must carry an exit guard even when the suite uses set -e.
            if line.lstrip().startswith('#') or not re.search(r'\bheadless_commons\b', line):
                continue
            # Sample input: headless_commons "$root" || exit 1; thumbs also keeps its sandbox_remove cleanup before exit.
            if scopes.get(n) != 0 or not re.fullmatch(r'\s*headless_commons\s+[^;&|]+\s+\|\|\s+(?:exit\s+1|\{\s*sandbox_remove\s+[^;&|{}]+;\s*exit\s+1;\s*\})\s*', line):
                bad.append(f'{path}:{n}: headless_commons refusal must abort the suite with || exit 1 in the parent shell')
    return bad


def controls(box):
    fixture = box / 'headless-commons-controls'
    fixture.mkdir()
    scanner = fixture / 'tests'
    scanner.mkdir()
    direct = scanner / 'new-suite.sh'
    native = Path(__file__).resolve().with_name('ui-captures-html.sh')
    native_link = 'ln -s "$(readlink -m "$repo/ui/boot/Commons")" "$dir/boot/Commons"'
    assert native_capture_source(native, native_link)
    assert not native_capture_source(native, 'ln -s ui/boot/Commons "$root/config/Commons"')
    assert not native_capture_source(native, native_link + '; qs -p "$dir/boot"')
    assert not native_capture_source(native, native_link.replace('$dir/boot/Commons', '$root/config/Commons'))
    for name in ('new-suite.sh', native.name):
        copied = scanner / name
        copied.write_text(native_link + '\nQT_QPA_PLATFORM=offscreen qs -p "$root/config"\n')
        errors = direct_sources(scanner)
        assert len(errors) == 1 and f'{name}:1:' in errors[0], (name, errors)
        copied.unlink()
    print('HEADLESS_COMMONS_NATIVE_BOUNDARY exact native RHI link accepted; copied/offscreen and altered links rejected')
    direct_controls = 0
    for source in ('ui/boot/' + 'Commons', 'ui/' + 'Commons', '/usr/share/omarchy/shell/' + 'Commons'):
        for suffix in ('', '/', '/.', '/Style.qml'):
            for line in (f'ln -s "$(readlink -f {source}{suffix})" "$root/config/Commons"', f'commons={source}{suffix}\nln -s "$commons" "$target"'):
                direct.write_text(line)
                assert len(direct_sources(scanner)) == 1 and 'new-suite.sh:1:' in direct_sources(scanner)[0]
                direct_controls += 1
    direct.write_text('# ui/boot/' + 'Commons is supplied by the helper\nheadless_commons "$root" || exit 1\ncp -a "$flea_ui/boot/Commons" "$target"\n')
    assert not direct_sources(scanner)
    assert not unchecked_calls(scanner)
    checker = Path('tests/headless-commons-check.py').resolve()
    for call in ('headless_commons "$root"', 'headless_commons "$root" || true',
                 'headless_commons "$root" | cat', '(headless_commons "$root" || exit 1)',
                 'copy=$(headless_commons "$root" || exit 1)', 'if headless_commons "$root"; then :; fi'):
        direct.write_text(call + '\nqs -p "$root/config"\n')
        assert len(unchecked_calls(scanner)) == 1 and 'new-suite.sh:1:' in unchecked_calls(scanner)[0], call
        result = subprocess.run([sys.executable, '-B', str(checker), str(box)], cwd=fixture, capture_output=True, text=True)
        assert result.returncode == 1 and 'refusal must abort the suite' in result.stderr, (call, result)
    calls = sum(len(call_scopes(path.read_text())) for path in Path('tests').glob('*.sh') if path.name != 'headless-commons.sh')
    # Sample input: python3 - "$target/Style.qml" <<'PY' followed by Python lines and a bare PY closing delimiter.
    helper = Path('tests/headless-commons.sh').read_text().split("<<'PY'\n", 1)[1].split('\nPY\n', 1)[0]
    original = 'import Quickshell.Hyprland\nQtObject {\n  id: root\n  Connections {\n    target: Hyprland\n  }\n}\n'
    variants = {
        'whitespace': original.replace('import Quickshell.', 'import  Quickshell.').replace('    target:', '  target :'),
        'alias': original.replace('import Quickshell.Hyprland', 'import Quickshell.Hyprland as Compositor').replace('target: Hyprland', 'target: Compositor'),
        'qualified': original.replace('import Quickshell.Hyprland\n', 'import Quickshell\n').replace('target: Hyprland', 'target: Quickshell.Hyprland'),
        'extra-read': original.replace('  Connections {', '  property var extra: Hyprland\n  Connections {'),
        'template-url': original.replace('  Connections {', '  property string url: `http://example`; property var live: Hyprland\n  Connections {'),
        'template-interpolation': original.replace('  Connections {', '  property string url: `file://${Hyprland}`\n  Connections {'),
        'multiline-template': original.replace('  Connections {', '  property string url: `http://example\n${Hyprland}`\n  Connections {'),
    }
    comments = '// Hyprland rounding\n/* Hyprland config */\n'
    tokens = '  property string url: `http://example`\n  property string other: "/* literal */ // data"\n'
    for name, before in {'current': comments + 'QtObject {\n  id: root\n' + tokens + '}\n', 'dev': comments + original.replace('  Connections {', tokens + '  Connections {'), **variants}.items():
        path = fixture / f'{name}.qml'
        path.write_text(before)
        result = subprocess.run(['python3', '-B', '-', str(path)], input=helper, text=True, capture_output=True)
        if name in variants:
            assert result.returncode == 1 and 'reader changed' in result.stderr and path.read_text() == before, (name, result)
        else:
            assert result.returncode == 0, (name, result)
            expected = before if name == 'current' else before.replace('import Quickshell.Hyprland\n', '').replace('  id: root\n', '  id: root\n  property QtObject headlessEvents: QtObject { signal rawEvent(var event) }\n').replace('    target: Hyprland\n', '    target: root.headlessEvents\n')
            assert path.read_text() == expected, name
    env = dict(os.environ, HOME=str(fixture / 'home'), FLEA_FIXTURE_ROOT=str(fixture / 'fixtures'))
    root = Path(env['FLEA_FIXTURE_ROOT']) / 'owned'
    root.mkdir(parents=True)
    (root / '.flea-test-sandbox').touch()
    source_root = fixture / 'source'
    commons = source_root / 'ui/boot/Commons'
    commons.mkdir(parents=True)
    (commons / 'Style.qml').write_text(original)
    repo = Path.cwd()
    (source_root / 'tests').mkdir()
    (source_root / 'tests/staticgates.py').symlink_to(repo / 'tests/staticgates.py')
    shell = '. "$3/tools/flea-sandbox-guard"; . "$3/tests/headless-commons.sh"; headless_commons "$1" "$2" || exit 1; printf "QS_REACHED\\n"'
    targets = [(root, root / name) for name in ('config/Commons', 'config-KEYS/Commons', 'config/boot/Commons')]
    targets.append((root / 'work', root / 'work/pane/config/Commons'))
    for owner, target in targets:
        owner.mkdir(exist_ok=True)
        result = subprocess.run(['bash', '-c', shell, 'control', str(owner), str(target), str(repo)], cwd=source_root, env=env, capture_output=True, text=True)
        assert result.returncode == 0 and (target / 'Style.qml').is_file() and not (target / 'Style.qml').is_symlink(), result
    sibling = Path(env['FLEA_FIXTURE_ROOT']) / 'unowned/Commons'
    result = subprocess.run(['bash', '-c', shell, 'control', str(root), str(sibling), str(repo)], cwd=source_root, env=env, capture_output=True, text=True)
    assert result.returncode == 1 and not sibling.exists(), result
    (commons / 'Style.qml').write_text(variants['whitespace'])
    result = subprocess.run(['bash', '-c', shell, 'control', str(root), str(root / 'refused/Commons'), str(repo)], cwd=source_root, env=env, capture_output=True, text=True)
    assert result.returncode == 1 and 'reader changed' in result.stderr and 'QS_REACHED' not in result.stdout, result
    prologue = '. "$3/tools/flea-sandbox-guard"\n. "$3/tests/headless-commons.sh"\nqs() { printf "QS_REACHED\\n"; }\n'
    call = 'headless_commons "$1" "$2" || exit 1\n'
    parents = {
        'root': call,
        'function': 'prepare() {\n' + call + '}\nprepare "$@"\n',
        'loop': 'for leg in current; do\n' + call + 'done\n',
        'case': 'case current in\ncurrent)\n' + call + ';;\nesac\n',
        'literal-parentheses': 'printf "%s\\n" "("\ncat <<\'TEXT\'\n( sample data\nTEXT\n' + call,
        'nested-quotes': 'out=ready\nprintf "%s\\n" "$(printf "%s" "$out" | grep \'ready\')"\n' + call,
        'arithmetic-shift': 'bits=2\nvalue=$((1 << bits))\n' + call,
        'keyword-arguments': 'printf "%s\\n" if case in esac\n' + call,
    }
    children = {
        'subshell': '(\n' + call + ')\n',
        'substitution': 'copy=$(\n' + call + ')\n',
        'quoted-substitution': 'copy="$(\n' + call + ')"\n',
        'subshell-case': '(\ncase current in\ncurrent)\n' + call + ';;\nesac\n)\n',
        'subshell-keywords': 'printf "%s\\n" if case in\n(\ncase current in\ncurrent)\nprintf "%s\\n" esac\n' + call + ';;\nesac\n)\n',
    }
    extra_parents = {
        'brace': '{\n' + call + '}\n',
        'brace-prefix-comment': '{ # comment ) | (\n' + call + '}\n',
        'parent-prefix-comment': ':;# comment ( | { }\n' + call,
        'here-string': 'cat <<<ready\n' + call,
        'here-string-quoted': 'cat <<<"ready ) | { #"\n' + call,
        'here-string-spaced': "cat <<< 'ready ( | #'\n" + call,
        'unrelated-pipe': 'printf "ready\\n" | cat\n' + call,
        'literal-pipes': 'printf "%s\\n" "|" "{ }"\n' + call,
        'multiline-comments': '# |\n# {\n# (\n' + call,
    }
    extra_children = {
        'pipeline-left': '{\n' + call + '} | cat\n',
        'pipeline-right': 'printf "" | {\n' + call + '}\n',
        'pipeline-left-prefix-comment': '{\n# comment ) |\n' + call + '} |# comment } (\ncat\n',
        'pipeline-right-prefix-comment': 'printf "" |# comment ) {\n{ # comment )\n' + call + '}\n',
        'pipeline-both': 'printf "" | {\n' + call + '} | cat\n',
        'pipeline-nested': '{\n{\n' + call + '}\n} | cat\n',
        'pipeline-left-stderr': '{\n' + call + '} |& cat\n',
        'pipeline-right-stderr': 'printf "" |& {\n' + call + '}\n',
        'pipeline-redirect': '{\n' + call + '} 2>&1 | cat\n',
        'background-brace': '{\n' + call + '} &\n',
        'comment-after-paren': '(# comment )\n' + call + ')\n',
        'comment-multiline': '(\n# comment )\n' + call + ')\n',
        'comment-after-semi': '(:;# comment )\n' + call + ')\n',
        'comment-after-pipe': 'printf "" | (# comment )\n' + call + ')\n',
    }
    for name, body in {**parents, **children, **extra_parents, **extra_children}.items():
        direct.write_text(prologue + body + 'qs -p "$2"\n')
        child = name in children or name in extra_children
        assert bool(unchecked_calls(scanner)) == child, name
        syntax = subprocess.run(['bash', '-n', str(direct)], capture_output=True, text=True)
        assert syntax.returncode == 0, (name, syntax)
        result = subprocess.run(['bash', str(direct), str(root), str(root / name / 'Commons'), str(repo)], cwd=source_root, env=env, capture_output=True, text=True)
        assert 'reader changed' in result.stderr + result.stdout, (name, result)
        if child:
            assert result.returncode == 0 and 'QS_REACHED' in result.stdout, (name, result)
            gate = subprocess.run([sys.executable, '-B', str(checker), str(box)], cwd=fixture, capture_output=True, text=True)
            assert gate.returncode == 1 and 'parent shell' in gate.stderr, (name, gate)
        else:
            assert result.returncode == 1 and 'QS_REACHED' not in result.stdout, (name, result)
    for file in ('tests/framegap.sh', 'tests/headless-commons.sh', 'tests/framegap-picker.py',
                 'tests/framegap.qml', 'ui/PickerWindow.qml', 'ui/PickerAnswers.qml', 'ui/PickerFilter.qml', 'tools/flea-sandbox-guard'):
        target = source_root / file
        target.parent.mkdir(parents=True, exist_ok=True)
        target.symlink_to(repo / file)
    bin_dir = fixture / 'bin'
    bin_dir.mkdir()
    fake_qs = bin_dir / 'qs'
    fake_qs.write_text('#!/bin/sh\nprintf "QS_REACHED\\n"\n')
    fake_qs.chmod(0o755)
    for cwd, script in ((repo, str(source_root / 'tests/framegap.sh')), (source_root / 'tests', 'framegap.sh')):
        result = subprocess.run(['bash', script], cwd=cwd, env=dict(env, PATH=str(bin_dir) + os.pathsep + env['PATH']), capture_output=True, text=True)
        assert result.returncode == 1 and 'reader changed' in result.stderr and 'QS_REACHED' not in result.stdout, result
    helper_stub = bin_dir / 'headless_commons'
    helper_stub.write_text('#!/bin/sh\ncase "$1" in /?*) [ -f "$1/.flea-test-sandbox" ] || exit 2;; *) exit 2;; esac\nprintf "HELPER_REFUSED\\n" >> "$1/refusals"\nexit 1\n')
    helper_stub.chmod(0o755)
    contract_env = dict(env, PATH=str(bin_dir) + os.pathsep + env['PATH'])
    contract_call = 'headless_commons "$root" || exit 1\n'
    contract_parents = {
        'redirect-truncate': '{\n' + contract_call + '} &>"$root/output"\n',
        'redirect-append': '{\n' + contract_call + '} &>>"$root/output"\n',
        'redirect-compact': '{\n' + contract_call + '}&>"$root/output"\n',
        'redirect-descriptor': '{\n' + contract_call + '} 2>&1\n',
        'substitution-suffix-parent': 'printf "%s\\n" $(printf x)#suffix\n' + contract_call,
        'escaped-suffix-parent': 'printf "%s\\n" \\)#suffix\n' + contract_call,
        'quoted-suffix-parent': 'printf "%s\\n" ")"#suffix\n' + contract_call,
        'brace-arguments-parent': 'printf "%s\\n" } {\n' + contract_call,
        'if-parent': 'if true; then\n' + contract_call + 'fi\n',
        'unrelated-if-pipeline': 'if true; then printf "ready\\n"; fi | cat\n' + contract_call,
        'unrelated-for-pipeline': 'for leg in current; do printf "ready\\n"; done | cat\n' + contract_call,
        'unrelated-case-pipeline': 'case "{" in {) printf "ready\\n";; esac | cat\n' + contract_call,
        'keyword-arguments-parent': 'printf "%s\\n" if fi done esac\n' + contract_call,
    }
    contract_children = {
        'substitution-suffix-child': 'printf "%s\\n" $(printf x)#suffix; (\n' + contract_call + ')\n',
        'nested-suffix-child': 'printf "%s\\n" $(printf "$(printf x)")#suffix; (\n' + contract_call + ')\n',
        'escaped-suffix-child': 'printf "%s\\n" \\)#suffix; (\n' + contract_call + ')\n',
        'if-left': 'if true; then\n' + contract_call + 'fi | cat\n',
        'if-right': 'printf "" | if true; then\n' + contract_call + 'fi\n',
        'if-stderr': 'if true; then\n' + contract_call + 'fi |& cat\n',
        'if-background': 'if true; then\n' + contract_call + 'fi &\n',
        'if-nested': 'if true; then\nif true; then\n' + contract_call + 'fi\nfi | cat\n',
        'for-left': 'for leg in current; do\n' + contract_call + 'done | cat\n',
        'for-right': 'printf "" | for leg in current; do\n' + contract_call + 'done\n',
        'while-left': 'while true; do\n' + contract_call + 'done | cat\n',
        'until-right': 'printf "" | until false; do\n' + contract_call + 'done\n',
        'case-left': 'case current in current)\n' + contract_call + ';; esac | cat\n',
        'case-right': 'printf "" | case current in current)\n' + contract_call + ';; esac\n',
        'brace-argument-left': '{\necho }\n' + contract_call + '} | cat\n',
        'brace-arguments-right': 'printf "" | {\nprintf "%s\\n" } }\n' + contract_call + '}\n',
        'brace-open-argument': '{\necho {\n' + contract_call + '} | cat\n',
        'if-brace-argument': 'if true; then\necho }\n' + contract_call + 'fi | cat\n',
    }
    # Sample inputs below execute complete callers with external helpers, so lexical data cannot hide parent QS reachability.
    boundary_parents = {
        'process-input-parent': 'printf "%s\\n" <(printf x)#suffix\n' + contract_call,
        'process-output-parent': 'printf "%s\\n" >(cat)#suffix\nwait\n' + contract_call,
        'quoted-process-parent': 'printf "%s\\n" "<(printf x)"#suffix\n' + contract_call,
        'escaped-process-parent': 'printf "%s\\n" \\<\\(x\\)#suffix\n' + contract_call,
        'process-comment-parent': 'printf "%s\\n" <(printf x) # comment (\n' + contract_call,
        'redirect-even-escape': '{\n' + contract_call + r'} > "$root/output"\\>&1' + '\n',
        'redirect-input-descriptor': '{\n' + contract_call + '} <&0\n',
        'conditional-words-parent': '[[ x == y || if == if ]]\n' + contract_call,
        'conditional-pipe-parent': '[[ x == if || fi == fi ]] | cat\n' + contract_call,
        'conditional-quoted-parent': '[[ "if || case" == "if || case" ]]\n' + contract_call,
        'conditional-nested-parent': '[[ ( x == y || if == if ) && done == done ]]\n' + contract_call,
        'arithmetic-words-parent': 'if=1; case=1; (( if || case ))\n' + contract_call,
        'arithmetic-substitution-parent': 'if=1; case=1; printf "%s\\n" "$(( if + case ))"#suffix\n' + contract_call,
        'arithmetic-for-parent': 'for (( if = 0; if < 1; if++ )); do :; done\n' + contract_call,
        'empty-case-right': 'printf "" | case x in esac\n' + contract_call,
        'empty-case-left': 'case x in esac | cat\n' + contract_call,
        'empty-case-middle': 'printf "" | case x in esac | cat\n' + contract_call,
        'empty-case-comment': 'printf "" | case x in\n# comment ) | if\nesac\n' + contract_call,
        'empty-case-subject': 'printf "" | case esac in esac\n' + contract_call,
        'empty-case-nested': 'case x in x) case x in esac; printf "%s\\n" esac;; esac | cat\n' + contract_call,
        'quoted-case-pattern': 'case esac in "esac") :;; esac | cat\n' + contract_call,
    }
    boundary_children = {
        'process-input-suffix-child': 'printf "%s\\n" <(printf x)#suffix; (\n' + contract_call + ')\n',
        'process-output-suffix-child': 'printf "%s\\n" >(cat)#suffix; (\n' + contract_call + ')\nwait\n',
        'process-nested-suffix-child': 'printf "%s\\n" <(printf "%s" "$(printf x)")#suffix; (\n' + contract_call + ')\n',
        'process-comment-suffix-child': 'printf "%s\\n" <(# comment )\nprintf x)#suffix; (\n' + contract_call + ')\n',
        'process-input-inner-child': 'cat <(\n' + contract_call + ')\n',
        'process-output-inner-child': 'printf "" > >(\n' + contract_call + ')\nwait\n',
        'redirect-escaped-output-child': '{\n' + contract_call + r'} > "$root/output"\>&' + '\nwait\n',
        'redirect-escaped-input-child': '{\n' + contract_call + r'} > "$root/output"\<&' + '\nwait\n',
        'redirect-odd-escape-child': '{\n' + contract_call + r'} > "$root/output"\\\>&' + '\nwait\n',
        'redirect-quoted-tail-child': '{\n' + contract_call + '} > "$root/output>"&\nwait\n',
        'redirect-then-background-child': '{\n' + contract_call + '} &>"$root/output" &\nwait\n',
        'conditional-words-left': 'if true; then\n' + contract_call + '[[ x == y || if == if ]]\nfi | cat\n',
        'conditional-words-right': 'printf "" | if true; then\n' + contract_call + '[[ x == y || if == if ]]\nfi\n',
        'conditional-substitution-child': '[[ "$(\n' + contract_call + ')" == "" ]]\n',
        'arithmetic-words-child': 'if true; then\n' + contract_call + '(( if || case ))\nfi | cat\n',
        'arithmetic-suffix-child': 'printf "%s\\n" "$(( 1 + 1 ))"#suffix; (\n' + contract_call + ')\n',
        'empty-case-nested-child': 'case x in x)\n' + contract_call + 'case x in esac\n;; esac | cat\n',
        'quoted-case-pattern-child': 'case esac in "esac")\n' + contract_call + ';; esac | cat\n',
    }
    # Sample inputs below retain legal conditional token boundaries without extending unsupported arithmetic grammar.
    nesting_parents = {
        'conditional-paren-parent': '([[ x == x ]])\n' + contract_call,
        'conditional-semicolon-parent': '[[ x == x ]];\n' + contract_call,
        'conditional-and-parent': '[[ x == x ]]&& :\n' + contract_call,
        'conditional-or-parent': '[[ x == x ]]|| :\n' + contract_call,
        'conditional-pipe-parent': '[[ x == x ]]|cat\n' + contract_call,
        'conditional-background-parent': '[[ x == x ]]&\nwait\n' + contract_call,
        'conditional-output-parent': '[[ x == x ]]>"$root/output"\n' + contract_call,
        'conditional-input-parent': ': > "$root/input"\n[[ x == x ]]<"$root/input"\n' + contract_call,
        'conditional-comment-parent': '[[ x == x ]] # comment ) | if\n' + contract_call,
    }
    nesting_children = {
        'conditional-paren-left': 'if true; then\n' + contract_call + '([[ x == x ]])\nfi | cat\n',
        'conditional-paren-right': 'printf "" | if true; then\n' + contract_call + '([[ x == x ]])\nfi\n',
        'conditional-paren-background': 'if true; then\n' + contract_call + '([[ x == x ]])\nfi &\nwait\n',
        'conditional-paren-brace': '{\n' + contract_call + '([[ x == x ]])\n} | cat\n',
    }
    # Sample input: $(( $(guard) + 1 )) can reach parent QS, but unchecked_calls rejects a missing scope with != 0.
    unsupported_children = {
        'arithmetic-executable-unsupported': 'printf "%s\\n" "$(( $(\n' + contract_call + ') + 1 ))"\n',
    }
    for name, body in {**contract_parents, **contract_children, **boundary_parents, **boundary_children, **nesting_parents, **nesting_children, **unsupported_children}.items():
        owner = root / ('external-' + name)
        owner.mkdir()
        (owner / '.flea-test-sandbox').touch()
        direct.write_text('root=$1\n' + body + 'qs -p "$root"\n')
        syntax = subprocess.run(['bash', '-n', str(direct)], capture_output=True, text=True)
        assert syntax.returncode == 0, (name, syntax)
        child = name in contract_children or name in boundary_children or name in nesting_children or name in unsupported_children
        errors = unchecked_calls(scanner)
        assert bool(errors) == child, (name, errors)
        if name in nesting_parents or name in nesting_children:
            guard_line = next(n for n, line in enumerate(direct.read_text().splitlines(), 1) if line == contract_call.rstrip())
            scope = call_scopes(direct.read_text()).get(guard_line)
            assert scope is not None and (scope > 0) == child, (name, scope)
        result = subprocess.run(['bash', str(direct), str(owner)], cwd=source_root, env=contract_env,
                                capture_output=True, text=True, timeout=CALLER_TIMEOUT_SECONDS)
        assert (owner / 'refusals').read_text() == 'HELPER_REFUSED\n', (name, result)
        assert result.returncode == (0 if child else 1) and ('QS_REACHED' in result.stdout) == child, (name, result)
        if child:
            gate = subprocess.run([sys.executable, '-B', str(checker), str(box)], cwd=fixture, capture_output=True,
                                  text=True, timeout=CALLER_TIMEOUT_SECONDS)
            assert gate.returncode == 1 and 'parent shell' in gate.stderr, (name, gate)
        print(f'HEADLESS_COMMONS_EXTERNAL_CALLER {name} bash_n=0 scan_errors={len(errors)} caller_exit={result.returncode} qs={int(child)}')
    # Sample inputs execute whole callers: a real refusing helper and an external QS sentinel expose any lost parent abort.
    safety_parents = {
        'guard-trailing-comment': contract_call.rstrip() + ' # || ignored guard text\n',
        'guard-quoted-hash': 'headless_commons "$root" "# literal" || exit 1\n',
        'guard-escaped-hash': 'headless_commons "$root" \\#literal || exit 1\n',
        'guard-word-hash': 'headless_commons "$root" word#suffix || exit 1\n',
        'guard-substitution-hash': 'headless_commons "$root" "$(printf \'#literal\')" || exit 1\n',
        'function-parent': 'prepare() {\n' + contract_call + '}\nprepare\n',
        'function-keyword-parent': 'function prepare {\n' + contract_call + '}\nprepare\n',
        'function-keyword-parens-parent': 'function prepare() {\n' + contract_call + '}\nprepare\n',
        'function-multiline-parent': 'prepare()\n# comment ) |\n{\n' + contract_call + '}\nprepare\n',
        'function-wrapper-parent': 'prepare() {\n' + contract_call + '}\nwrapper() { prepare; }\nwrapper\n',
        'function-loop-parent': 'prepare() {\n' + contract_call + '}\nfor leg in current; do prepare; done\n',
        'function-negated-parent': 'prepare() {\n' + contract_call + '}\n! prepare\n',
        'function-quoted-name-argument': 'prepare() {\n' + contract_call + '}\nprepare "prepare"\n',
        'function-concatenated-argument': 'prepare() {\n' + contract_call + '}\nprepare pre"pare"\n',
        'function-forwarded-external': 'prepare() {\n' + contract_call + '}\ndispatch() { "$@"; }\ndispatch printf "%s" ready\nprepare\n',
        'function-command-forwarded-external': 'prepare() {\n' + contract_call + '}\ndispatch() { command -- "$@"; }\ndispatch printf "%s" ready\nprepare\n',
        'function-env-forwarded-external': 'prepare() {\n' + contract_call + '}\ndispatch() { env -- "$@"; }\ndispatch printf "%s" ready\nprepare\n',
        'function-command-query': 'prepare() {\n' + contract_call + '}\ncommand -v printf\nprepare\n',
        'function-command-query-verbose': 'prepare() {\n' + contract_call + '}\ncommand -V printf\nprepare\n',
        'heredoc-normal-parent': "cat <<'EOF'\n) # body only\nEOF\n" + contract_call,
        'heredoc-tabs-parent': "cat <<-'EOF'\n\t) # body only\n\tEOF\n" + contract_call,
    }
    unsafe_callers = {
        'commented-guard': 'headless_commons "$root" # || exit 1\n',
        'commented-guard-after-hash': 'headless_commons "$root" "# literal" # || exit 1\n',
        'function-left': 'prepare() {\n' + contract_call + '}\nprepare | cat\n',
        'function-right': 'prepare() {\n' + contract_call + '}\nprintf "" | prepare\n',
        'function-both': 'prepare() {\n' + contract_call + '}\nprintf "" | prepare | cat\n',
        'function-background': 'prepare() {\n' + contract_call + '}\nprepare &\nwait\n',
        'function-subshell': 'prepare() {\n' + contract_call + '}\n(prepare)\n',
        'function-substitution': 'prepare() {\n' + contract_call + '}\nout=$(prepare)\n',
        'function-process': 'prepare() {\n' + contract_call + '}\ncat <(prepare)\n',
        'function-redirect-pipe': 'prepare() {\n' + contract_call + '}\nprepare > >(cat; :) | cat\n',
        'function-wrapper-left': 'prepare() {\n' + contract_call + '}\nwrapper() { prepare; }\nwrapper | cat\n',
        'function-wrapper-right': 'prepare() {\n' + contract_call + '}\nwrapper() { prepare; }\nprintf "" | wrapper\n',
        'function-multiline-left': 'prepare()\n# comment ) |\n{\n' + contract_call + '}\nprepare | cat\n',
        'function-keyword-left': 'function prepare {\n' + contract_call + '}\nprepare | cat\n',
        'function-mixed-context': 'prepare() {\n' + contract_call + '}\nif false; then prepare; fi\nprepare | cat\n',
        'function-dynamic-alias': 'prepare() {\n' + contract_call + '}\ntarget=prepare\n"$target" | cat\n',
        'function-dynamic-quoted-alias': 'prepare() {\n' + contract_call + '}\ntarget="prepare"\n"$target" | cat\n',
        'function-eval': 'prepare() {\n' + contract_call + '}\neval prepare | cat\n',
        'function-quoted-name': 'prepare() {\n' + contract_call + '}\n"prepare" | cat\n',
        'function-escaped-name': 'prepare() {\n' + contract_call + '}\npre\\pare | cat\n',
        'function-dead-literal-concatenated': 'prepare() {\n' + contract_call + '}\nif false; then prepare; fi\npre"pare" | cat\n',
        'function-dead-literal-escaped': 'prepare() {\n' + contract_call + '}\nif false; then prepare; fi\npre\\pare | cat\n',
        'function-dead-literal-expansion': 'prepare() {\n' + contract_call + '}\nif false; then prepare; fi\ntarget=pre; target+=pare\n"$target" | cat\n',
        'function-dead-literal-wrapper': 'prepare() {\n' + contract_call + '}\nif false; then prepare; fi\nwrapper() { pre"pare"; }\nwrapper | cat\n',
        'function-dead-literal-assignment': 'prepare() {\n' + contract_call + '}\nif false; then prepare; fi\nFLAG=1 pre"pare" | cat\n',
        'function-forwarded-eval': 'prepare() {\n' + contract_call + '}\ndispatch() { "$@"; }\nif false; then prepare; fi\ndispatch eval prepare | cat\n',
        'function-forwarded-shift': 'prepare() {\n' + contract_call + '}\nif false; then prepare; fi\ndispatch() { shift; "$@"; }\ndispatch printf prepare | cat\n',
        'function-command-forwarded-eval': 'prepare() {\n' + contract_call + '}\ndispatch() { command -- "$@"; }\nif false; then prepare; fi\ndispatch eval \'pre"pare"\' | cat\n',
        'function-command-literal-eval': 'prepare() {\n' + contract_call + '}\nif false; then prepare; fi\ncommand eval \'pre"pare"\' | cat\n',
        'function-builtin-forwarded-eval': 'prepare() {\n' + contract_call + '}\ndispatch() { builtin "$@"; }\nif false; then prepare; fi\ndispatch eval \'pre"pare"\' | cat\n',
        'heredoc-space-child': "(\ncat <<'EOF'\n EOF\n)\nEOF\n" + contract_call + ') | cat\n',
        'heredoc-normal-tab-child': "(\ncat <<'EOF'\n\tEOF\n)\nEOF\n" + contract_call + ') | cat\n',
        'heredoc-trailing-space-child': "(\ncat <<'EOF'\nEOF \n)\nEOF\n" + contract_call + ') | cat\n',
        'heredoc-dash-space-child': "(\ncat <<-'EOF'\n EOF\n)\nEOF\n" + contract_call + ') | cat\n',
        'heredoc-dash-tab-space-child': "(\ncat <<-'EOF'\n\t EOF\n)\nEOF\n" + contract_call + ') | cat\n',
        'heredoc-dash-trailing-tab-child': "(\ncat <<-'EOF'\nEOF\t\n)\nEOF\n" + contract_call + ') | cat\n',
        'heredoc-multiple-child': "(\ncat <<'FIRST' <<-'SECOND'\n FIRST\n)\nFIRST\n\tbody\n\tSECOND\n" + contract_call + ') | cat\n',
        'compound-process-redirect': '{\n' + contract_call + '} > >(cat; :) | cat\n',
    }
    # Sample input: dispatch printf looks safe at runtime, but "$@" and command -- "$@" have no supported dispatch proof.
    unresolved_parents = {'function-forwarded-external', 'function-command-forwarded-external'}
    for name, body in {**safety_parents, **unsafe_callers}.items():
        owner = root / ('safety-' + name)
        owner.mkdir()
        (owner / '.flea-test-sandbox').touch()
        direct.write_text('root=$1\n' + body + 'qs -p "$root"\n')
        syntax = subprocess.run(['bash', '-n', str(direct)], capture_output=True, text=True)
        assert syntax.returncode == 0, (name, syntax)
        child = name in unsafe_callers
        rejected = child or name in unresolved_parents
        errors = unchecked_calls(scanner)
        assert bool(errors) == rejected, (name, errors)
        result = subprocess.run(['bash', str(direct), str(owner)], cwd=source_root, env=contract_env,
                                capture_output=True, text=True, timeout=CALLER_TIMEOUT_SECONDS)
        assert (owner / 'refusals').read_text() == 'HELPER_REFUSED\n', (name, result)
        assert result.returncode == (0 if child else 1) and ('QS_REACHED' in result.stdout) == child, (name, result)
        if rejected:
            gate = subprocess.run([sys.executable, '-B', str(checker), str(box)], cwd=fixture, capture_output=True,
                                  text=True, timeout=CALLER_TIMEOUT_SECONDS)
            assert gate.returncode == 1 and 'parent shell' in gate.stderr, (name, gate)
        print(f'HEADLESS_COMMONS_SAFETY_CALLER {name} bash_n=0 scan_errors={len(errors)} caller_exit={result.returncode} qs={int(child)}')
    print(f'HEADLESS_COMMONS_CONTROLS direct sources={direct_controls} reader drift={len(variants)} targets=5 passed; OEM token bytes preserved')
    print(f'HEADLESS_COMMONS_CALL_CONTROLS unchecked=6 rejected exit=1; callers={calls} scope-checked')
    print(f'HEADLESS_COMMONS_WHOLE_CALLERS parents={len(parents)} refusal exit=1 qs=not-started; children={len(children)} reach qs but gate rejects exit=1')
    print(f'HEADLESS_COMMONS_PIPE_COMMENT_CONTROLS parents={len(extra_parents)} refusal exit=1 qs=not-started; children={len(extra_children)} gate rejects exit=1')
    print('HEADLESS_COMMONS_ACTUAL_CALLER unmodified framegap.sh from repo and tests: refusal exit=1 qs=not-started')
    print(f'HEADLESS_COMMONS_EXTERNAL_CONTROLS parents={len(contract_parents)} refusal exit=1 qs=not-started; children={len(contract_children)} gate rejects exit=1')
    print(f'HEADLESS_COMMONS_BOUNDARY_CONTROLS parents={len(boundary_parents)} refusal exit=1 qs=not-started; children={len(boundary_children)} gate rejects exit=1')
    print(f'HEADLESS_COMMONS_NESTING_CONTROLS parents={len(nesting_parents)} refusal exit=1 qs=not-started; children={len(nesting_children)} recorded child scope and gate rejects exit=1')
    print(f'HEADLESS_COMMONS_UNSUPPORTED_CONTROLS children={len(unsupported_children)} reach parent qs but gate rejects exit=1; missing scope fails closed')
    print(f'HEADLESS_COMMONS_SAFETY_CONTROLS parents={len(safety_parents)} refusal exit=1 qs=not-started; unresolved={len(unresolved_parents)} gate rejects exit=1; unsafe={len(unsafe_callers)} reach parent qs but gate rejects exit=1')


if __name__ == '__main__':
    errors = direct_sources(Path('tests')) + unchecked_calls(Path('tests'))
    if errors:
        raise SystemExit('FAIL headless Commons rule: ' + '\n'.join(errors))
    box = Path(sys.argv[1])
    if not box.is_absolute() or not (box / '.flea-test-sandbox').is_file():
        raise SystemExit('FAIL headless Commons controls need an absolute marked fixture')
    try:
        controls(box)
    except AssertionError as error:
        raise SystemExit(f'FAIL headless Commons controls: {error}')
    print('HEADLESS_COMMONS_RULE offscreen suites use the shared fixture; native capture keeps live Commons')
