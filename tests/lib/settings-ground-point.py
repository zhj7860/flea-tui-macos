#!/usr/bin/env python3
"""Choose and verify R0's visible row point outside Settings and the pane rail."""
import json
import math
import sys


def rectangle(value):
    # Sample input: "220 290 1000 32" is x, y, width and height separated by spaces.
    result = tuple(map(float, value.split()))
    if len(result) != 4 or not all(map(math.isfinite, result)) or min(result[2:]) <= 0:
        raise ValueError("invalid rectangle")
    return result


def ground_point(row, card, area, rail, window, margin, point=None):
    rx, ry, rw, rh = rectangle(row)
    cx, cy, cw, ch = rectangle(card)
    ax, ay, aw, ah = rectangle(area)
    wx, wy, ww, wh = rectangle(window)
    # Sample input: '{"x":0,"width":220}' is the pane rail's window-local geometry.
    rail = json.loads(rail)
    rail_x, rail_width = float(rail["x"]), float(rail["width"])
    if not math.isfinite(rail_x) or not math.isfinite(rail_width) or rail_width < 0 or margin < 1:
        raise ValueError("invalid rail or pointer margin")
    left, right = max(rx, ax, 0) + margin, min(rx + rw, ax + aw, ww) - margin
    if math.ceil(left) > math.floor(right):
        raise ValueError("no visible row width")
    top, bottom = max(ry, ay, 0) + margin, min(ry + rh, ay + ah, wh) - margin
    if point is not None:
        # Sample input: "1102 306" is the absolute screen x and y separated by a space.
        px, py = map(int, point.split())
        y = py - wy
    else:
        y = math.floor((top + bottom) / 2)
    if top > y or y > bottom:
        raise ValueError("no visible row height")
    spans = [(math.ceil(left), math.floor(right))]
    exclusions = [(rail_x - margin, rail_x + rail_width + margin)] if rail_width else []
    if cy - margin <= y <= cy + ch + margin:
        exclusions.append((cx - margin, cx + cw + margin))
    for lo, hi in exclusions:
        spans = [(a, b) for start, end in spans for a, b in
                 ((start, min(end, math.ceil(lo) - 1)), (max(start, math.floor(hi) + 1), end)) if a <= b]
    if point is not None:
        x = px - wx
        if not any(a <= x <= b for a, b in spans):
            raise ValueError("press point is not on the visible row ground")
        return px, py
    if not spans:
        raise ValueError("no row ground outside Settings and the rail")
    start, end = max(spans, key=lambda span: span[1] - span[0])
    return int(wx + (start + end) // 2), int(wy + y)


def self_test():
    common = ("220 290 1000 32", "220 80 1000 720", '{"x":0,"width":220}', "0 0 1400 900", 4)
    row, area, rail, window, margin = common
    card = "420 280 560 550"
    point = ground_point(row, card, area, rail, window, margin)
    assert point[0] > 984 and point[1] == 306
    assert ground_point(row, card, area, rail, window, margin, "%s %s" % point) == point
    try:
        ground_point(row, card, area, rail, window, margin, "720 306")
    except ValueError:
        pass
    else:
        raise AssertionError("old row centre was accepted inside the grown card")
    for blocked in ("0 280 1400 550", "420 280 560 nan"):
        try:
            ground_point(row, blocked, area, rail, window, margin)
        except ValueError:
            pass
        else:
            raise AssertionError("unusable ground was accepted")
    shifted = ground_point(row, card, area, rail, "-1400 10 1400 900", margin)
    assert shifted == (point[0] - 1400, point[1] + 10)
    hidden_rail = ground_point(row, "420 400 560 400", area, '{"x":0,"width":0}', window, margin)
    assert 224 <= hidden_rail[0] <= 1216
    rail_cover = ground_point(row, card, area, '{"x":220,"width":400}', window, margin)
    assert rail_cover[0] > 984
    clear_card, middle_rail = "420 400 560 400", '{"x":500,"width":400}'
    rail_point = ground_point(row, clear_card, area, middle_rail, window, margin)
    assert rail_point[0] < 496 or rail_point[0] > 904, "rail exclusion did not move the candidate off the rail"
    assert ground_point(row, clear_card, area, middle_rail, window, margin, "%s %s" % rail_point) == rail_point
    try:
        ground_point(row, clear_card, area, middle_rail, window, margin, "720 306")
    except ValueError:
        pass
    else:
        raise AssertionError("a press point covered only by the rail was accepted")
    try:
        ground_point("1300 290 80 32", card, area, rail, window, margin)
    except ValueError:
        pass
    else:
        raise AssertionError("a row outside the viewport was accepted")
    print("SETTINGS_GROUND_POINT PASS 12 checks")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    else:
        try:
            values = sys.argv[1:]
            if len(values) not in (6, 7):
                raise ValueError("expected row, card, viewport, rail, window, margin and optional press point")
            print(*ground_point(*values[:5], int(values[5]), values[6] if len(values) == 7 else None))
        except (ValueError, KeyError, TypeError) as error:
            print("DRAG_R0_GROUND_REFUSED " + json.dumps({"reason": str(error), "coordinates": sys.argv[1:]}), file=sys.stderr)
            sys.exit(1)
