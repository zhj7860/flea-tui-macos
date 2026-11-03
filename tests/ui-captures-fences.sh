#!/usr/bin/env bash
# Runs the fence14 case's README reader and ui/js/Markdown.js on every fixture the case pins, on fence shapes a README may grow and on the README, so both halves agree before a capture.
set -uo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)" || exit 1
. "$repo/tools/flea-sandbox-guard"
. "$repo/tests/ui-captures-markdown.sh"
for tool in jq qml6 expand; do
    command -v "$tool" >/dev/null || { printf 'FAIL ui-captures-fences: %s is required\n' "$tool"; exit 1; }
done
sandbox_root_ok
scratch=$(mktemp -d "$SANDBOX_ROOT/flea-capfences.XXXXXX") || exit 1
: > "$scratch/$SANDBOX_MARKER"
trap 'sandbox_remove "$scratch"' EXIT
checks=0
failed=0

# Sample input: "shapes/quote.md read" fence:js fence:js passes; a row that differs from the one it is held to fails and names both.
check() {
    checks=$((checks + 1))
    if [[ "$2" == "$3" ]]; then
        printf 'ok   %s [%s]\n' "$1" "$2"
    else
        failed=$((failed + 1))
        printf 'FAIL %s: [%s], want [%s]\n' "$1" "$2" "$3"
    fi
}

mkdir -p "$scratch/listing" "$scratch/shapes"
capmarkdownfences_fixture "$scratch/listing"
capmarkdownfences14_fixture "$scratch/listing"
files=()
declare -A rows=()
# Each pinned fixture's row is its capmdfence14_want row, which the native case checks against the pane itself.
for file in "$scratch"/listing/fence*.md; do
    [[ "${file##*/}" != fence-readme.md ]] || continue
    files+=("$file")
    if row="$(capmdfence14_want "${file##*/}")"; then
        rows[$file]="$(jq -Rr "$capmdfence14_tagged" <<< "$row")"
    else
        rows[$file]="no pinned row"
    fi
done

# Sample input: shape name, the document with \n escapes, the tagged fences ui/js/Markdown.js builds for it.
shape() {
    printf '%b' "$2" > "$scratch/shapes/$1.md"
    files+=("$scratch/shapes/$1.md")
    rows[$scratch/shapes/$1.md]="$3"
}
shape info-words '```sh title="x"\nls\n```\n' fence:sh
shape figures '```mermaid\ngraph TD\n```\n\n```math\nx^2\n```\n\n```sh\nls\n```\n' fence:sh
shape inline-ticks 'a\n\n```a`b\n\n```sh\nls\n```\n' fence:sh
shape quote '> ```js\n> x\n> ```\n' fence:js
shape nested-list '- a\n  - b\n\n    ```py\n    x\n    ```\n' fence:py
shape tilde-holds-ticks '~~~rust\n```\n~~~\n\n```toml\nk = 1\n```\n' fence:rust,fence:toml
shape longer-close '```sh\nx\n````\n\n```toml\nk = 1\n```\n' fence:sh,fence:toml
shape indented-block 'a\n\n    plain code\n\n```sh\nls\n```\n' fence:sh
shape indented-fence-line 'a\n\n    ```sh\n    ls\n    ```\n\n```toml\nk = 1\n```\n' fence:toml
shape item-indented-code '- a\n\n      ```sh\n      ls\n      ```\n- b\n\n  ```py\n  x\n  ```\n' fence:py
shape quote-indented-code '> a\n>\n>     ```sh\n>     ls\n>     ```\n\n> ```js\n> x\n> ```\n' fence:js
shape lazy-item '- a long item\nwrapped without indent\n\n    ```sh\n    ls\n    ```\n' fence:sh
shape item-ends-fence '- a\n\n  ```sh\n  ls\nafter\n\n```toml\nk = 1\n```\n' fence:sh,fence:toml

# The README has no pinned row, so its reader is held to the parser's row.
readme="$scratch/listing/fence-readme.md"
declare -A built=()
# Sample input: "qml: FENCES /tmp/flea-capfences.x/shapes/quote.md fence:js", the tagged fences ui/js/Markdown.js builds for one file.
fences_line_re='FENCES ([^ ]+) (.*)$'
while IFS= read -r line; do
    [[ "$line" =~ $fences_line_re ]] && built[${BASH_REMATCH[1]}]="${BASH_REMATCH[2]}"
done < <(QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 timeout 120 qml6 "$repo/tests/ui-captures-fences.qml" -- "${files[@]}" "$readme" 2>&1)
for file in "${files[@]}"; do
    name="${file#"$scratch"/}"
    check "$name read" "$(capmdfence14_fences "$file")" "${rows[$file]}"
    check "$name parsed" "${built[$file]-no row from ui/js/Markdown.js}" "${rows[$file]}"
done
check "README read" "$(capmdfence14_fences "$readme")" "${built[$readme]-no row from ui/js/Markdown.js}"
printf 'ui-captures-fences: %s checks, %s failed\n' "$checks" "$failed"
(( failed == 0 ))
