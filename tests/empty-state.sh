#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.." || exit 1

ui_dir=${FLEA_EMPTY_STATE_UI_DIR:-ui}
# The hint used to be bound in shell.qml, then on the pane, and now on the states tile it draws. The file
# is named here rather than in each check, and the check below fails loudly when it moves again
# rather than matching nothing and passing.
hint_file="$ui_dir/PaneStates.qml"
column_file="$ui_dir/ColumnPane.qml"
tip='Press %1 for a new folder.'

fail() {
    printf 'empty-state: %s\n' "$1" >&2
    exit 1
}

[ -r "$hint_file" ] || fail "cannot read $hint_file"
[ -r "$column_file" ] || fail "cannot read $column_file"

# The tip is the Menus section's "Show keyboard hints" row, off by default, so an ordinary empty
# folder is as quiet as it was when the tip was removed outright. A copy of it anywhere that does
# not name that setting is a tip nothing can switch off.
if grep -Fq "$tip" "$column_file"; then
    fail 'the columns empty tile carries the new-folder tip'
fi
ungated=$(grep -F "$tip" "$hint_file" | grep -Fcv 'ViewState.keyHints' || true)
if [ "$ungated" != 0 ]; then
    fail 'the new-folder tip is drawn without the keyboard-hints setting'
fi

shell_hint=$(sed -n '/hint: Search.live(root.pane)/,/^[[:space:]]*}/p' "$hint_file")
shell_hint=$(printf '%s' "$shell_hint" | tr -s '[:space:]' ' ')
[ -n "$shell_hint" ] || fail "no hint binding found in $hint_file"
expected_hint='hint: Search.live(root.pane) ? "Press Escape to clear." : ViewState.keyHints ? KeyName.hinted("Press %1 for a new folder.", "newFolder") : ""'
case "$shell_hint" in
    *"$expected_hint"*) ;;
    *) fail 'the hint must show Escape for a live search and the tip only behind the setting' ;;
esac

# The caption is one whole sentence with a placeholder, filled by Search.nothingMatches.
shell_caption=$(grep -F 'caption: Search.live(root.pane)' "$hint_file" | tr -s '[:space:]' ' ')
[ -n "$shell_caption" ] || fail "no search caption binding found in $hint_file"
expected_caption='caption: Search.live(root.pane) ? Search.nothingMatches(root.pane.swap.answeredQuery) : ""'
case "$shell_caption" in
    *"$expected_caption"*) ;;
    *) fail 'the caption must fill one whole Nothing-matches sentence from the answered query' ;;
esac

column_empty=$(sed -n '/id: emptyTile/,/^[[:space:]]*}/p' "$column_file")
[ -n "$column_empty" ] || fail 'ColumnPane emptyTile is missing'
if printf '%s\n' "$column_empty" | grep -Eq '^[[:space:]]*hint:'; then
    fail 'ColumnPane emptyTile must not bind a hint'
fi

printf 'empty-state: search hint always, new-folder tip gated, column hint absent\n'
