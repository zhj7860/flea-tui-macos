#!/usr/bin/env python3
"""Compare real-window fence records and require painted ink and document-scroll evidence."""
import json
import sys


def records(path):
    # Sample input: a qs log line ending in 'FENCEPARITY RECORD {"host":"list","ordinal":0,...}'.
    marker = 'FENCEPARITY RECORD '
    with open(path) as log:
        return [json.loads(line.split(marker, 1)[1]) for line in log if marker in line]


def compare(left, right):
    errors = []

    def require(ok, why):
        if not ok:
            errors.append(why)

    require(len(left) == len(right) == 3, 'each window must record all three fences')
    for host, rows in [('list', left), ('column', right)]:
        for i, row in enumerate(rows):
            label = '%s fence %d' % (host, i)
            require(row['host'] == host and row['ordinal'] == i, label + ' has another host or order')
            require(row['blocks'] == 5 and row['blockIndex'] == i + 1, label + ' has another block count or index')
            require(row['info'] == ('rust' if i != 1 else ''), label + ' has another language')
            require(row['family'] == row['expectedFamily'] and bool(row['family']), label + ' lost the monospace family')
            require(row['background'] == row['expectedBackground'], label + ' lost its approved host background')
            require(row['pixels']['background'] > 0, label + ' painted no block background')
            require(bool(row['pixels']['inks']) and all(ink['pixels'] > 0 for ink in row['pixels']['inks']), label + ' did not paint every span ink')
            if i == 1:
                require(not row['coloured'] and len({s['ink'] for s in row['spans']}) == 1, label + ' must stay plain')
            else:
                require(row['coloured'] and len({s['ink'] for s in row['spans']}) > 1, label + ' lost syntax colours')
            if i == 2:
                require(row['lines'] == 96 and row['rect']['h'] > row['viewportHeight'], label + ' is not longer than its viewport')
                require(row['documentScroll'] is not None and row['documentScroll']['together'], label + ' did not scroll with its document')
    for i, (a, b) in enumerate(zip(left, right)):
        require(a['spans'] == b['spans'], 'token inks differ for fence %d' % i)
        require(a['textFormat'] == b['textFormat'], 'text formats differ for fence %d' % i)
        require(a['family'] == b['family'], 'monospace families differ for fence %d' % i)
        require(a['blocks'] == b['blocks'] and a['lines'] == b['lines'], 'blocks or lines differ for fence %d' % i)
    return errors


def main():
    try:
        left, right = (records(path) for path in sys.argv[1:])
        errors = compare(left, right)
    except (OSError, ValueError, KeyError, TypeError) as error:
        errors = ['invalid real-window evidence: %s' % error]
    for error in errors:
        print('FAIL fenceparity: ' + error)
    if errors:
        return 1
    for i, (a, b) in enumerate(zip(left, right)):
        print('ok fenceparity: fence %d, %d blocks, inks=%s family=%s backgrounds=%s/%s documentScroll=%s/%s' %
              (i, a['blocks'], sorted({s['ink'] for s in a['spans']}), a['family'], a['background'], b['background'], a['documentScroll'], b['documentScroll']))
    return 0


if __name__ == '__main__':
    sys.exit(main())
