#!/usr/bin/env python3
"""Keep framegap's picker mock aligned with the answer strip's real owner."""
import re
from pathlib import Path
from staticgates import masked


def object_body(source, name):
    code = masked(source, '.qml', fill=' ')
    # Sample input: QtObject { id: mockPicker; Item { property bool saving: false } } keeps the whole balanced mock block.
    match = re.search(r'\bid\s*:\s*' + re.escape(name) + r'\b', code)
    if match is None:
        raise ValueError(f'{name} was not found')
    stack = []
    for at, char in enumerate(code[:match.start()]):
        if char == '{':
            stack.append(at)
        elif char == '}':
            stack.pop()
    start = stack[-1]
    depth = 1
    for at in range(start + 1, len(code)):
        depth += (code[at] == '{') - (code[at] == '}')
        if depth == 0:
            return source[start + 1:at]
    raise ValueError(f'{name} has no closing brace')


def members(source):
    code = masked(source, '.qml', fill=' ')
    depths = []
    depth = 0
    for char in code:
        depths.append(depth)
        depth += (char == '{') - (char == '}')
    # Sample input: property bool saving: false; Item { property bool child: false } declares only saving on the owner.
    properties = re.finditer(r'\bproperty\s+\w+\s+(\w+)\s*:', code)
    declared = {m[1] for m in properties if depths[m.start()] == 0}
    previous = None
    # Sample input: helper: /* note */ function accept() {} has ':' before function; a quoted value remains one token.
    tokens = re.finditer(r'''//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\w+|[^\s]''', source, re.S)
    for token in tokens:
        if token[0].startswith(('//', '/*')):
            continue
        boundary = previous is None or previous[0] in (';', '}')
        if previous is not None and '\n' in source[previous.end():token.start()]:
            boundary |= previous[0] not in (':', '=', ',', '(', '[', '?', '+', '-', '*', '/', '%', '&', '|', '^', '!', '~', '<', '>', '.',
                                            'return', 'throw', 'new', 'void', 'typeof', 'delete', 'yield', 'await', 'in', 'instanceof')
        if token[0] == 'function' and boundary and depths[token.start()] == 0:
            # Sample input: function accept() {} starts a statement; property var helper: function accept() {} does not.
            match = re.match(r'function\s+(\w+)\s*\(', code[token.start():])
            if match:
                declared.add(match[1])
        previous = token
    return declared


def contract(owner, harness, readers):
    # FloatingWindow supplies contentItem; the other members belong to the window with id win.
    provided = members(object_body(owner, 'win')) | {'contentItem'}
    mocked = members(object_body(harness, 'mockPicker'))
    required = set()
    for file, source in readers.items():
        # Sample input: enabled: root . picker .\n saving reads saving across whitespace and comments around each dot.
        used = set(re.findall(r'\broot\s*\.\s*picker\s*\.\s*(\w+)', masked(source, '.qml', fill=' ')))
        required |= used
        if used - provided:
            raise ValueError(f'{file} has no owner member: {", ".join(sorted(used - provided))}')
        if used - mocked:
            raise ValueError(f'mockPicker lacks {file} member: {", ".join(sorted(used - mocked))}')
    return required


def controls():
    owner = 'ShellRoot { FloatingWindow { id: win; property bool saving: false; function accept() {} } }'
    mock = 'QtObject { id: mockPicker; property bool saving: false; function accept() {} }'
    readers = {'control.qml': 'enabled: root.picker.saving; onClicked: root.picker.accept()'}
    assert contract(owner, mock, readers) == {'saving', 'accept'}
    literal_owner = owner.replace('function accept()', 'property string label: "ok" // note\nfunction accept()')
    literal_mock = mock.replace('function accept()', 'property string label: "ok" // note\nfunction accept()')
    assert contract(literal_owner, literal_mock, readers) == {'saving', 'accept'}
    for declaration in ('property bool saving: false', 'function accept() {}'):
        for replacement in ('Item { ' + declaration + ' }', '// ' + declaration + '\n', '/* ' + declaration + ' */'):
            for subject in ('owner', 'mock'):
                try:
                    contract(owner.replace(declaration, replacement) if subject == 'owner' else owner,
                             mock.replace(declaration, replacement) if subject == 'mock' else mock, readers)
                except ValueError:
                    continue
                raise AssertionError(f'{subject} accepted a child or commented declaration: {replacement}')
    expressions = ('property var helper: function accept() {}', 'property var helper:\nfunction accept() {}',
                   'property var helper: (\nfunction accept() {})', 'property var helper: /* note */\nfunction accept() {}')
    for expression in expressions:
        for subject in ('owner', 'mock'):
            try:
                contract(owner.replace('function accept() {}', expression) if subject == 'owner' else owner,
                         mock.replace('function accept() {}', expression) if subject == 'mock' else mock, readers)
            except ValueError as error:
                assert 'accept' in str(error), error
                continue
            raise AssertionError(f'{subject} accepted a named function expression as a method: {expression}')
    assert members('property string label: "ok" // note\nfunction accept() {}') == {'label', 'accept'}
    spaced_readers = ('root.picker.\naccept()', 'root .\n picker .\n accept()', 'root /* owner */ . picker . // member\n accept()')
    for reader in spaced_readers:
        spaced = {'spaced.qml': 'onClicked: ' + reader}
        assert contract(owner, mock, spaced) == {'accept'}
        for subject in ('owner', 'mock'):
            try:
                contract(owner.replace('function accept() {}', '') if subject == 'owner' else owner,
                         mock.replace('function accept() {}', '') if subject == 'mock' else mock, spaced)
            except ValueError as error:
                assert 'accept' in str(error), error
                continue
            raise AssertionError(f'{subject} accepted a missing spaced reader member: {reader}')
    print('FRAMEGAP PICKER_CONTROLS 12 missing root declarations and 8 named function expressions rejected')
    print(f'FRAMEGAP PICKER_SPACING {len(spaced_readers)} reader forms checked against owner and mock')


if __name__ == '__main__':
    try:
        controls()
        required = contract(Path('ui/PickerWindow.qml').read_text(), Path('tests/framegap.qml').read_text(),
                            {file: Path(file).read_text() for file in ('ui/PickerAnswers.qml', 'ui/PickerFilter.qml')})
    except (ValueError, AssertionError) as error:
        raise SystemExit(f'FAIL framegap picker contract: {error}')
    print(f'FRAMEGAP PICKER_CONTRACT members={len(required)} owner=PickerWindow.qml mock=mockPicker')
