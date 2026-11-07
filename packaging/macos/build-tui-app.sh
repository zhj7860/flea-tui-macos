#!/bin/sh
# Builds a macOS .app for one terminal program. A TUI needs a terminal and Finder gives none, so
# the bundle has two entrances: with a tty the launcher execs the TUI in place and keeps the
# caller's directory; without one it hands Contents/Resources/tui.command to Terminal, and that
# file runs the TUI from $HOME (Finder's own directory is /).
#
#   packaging/macos/build-tui-app.sh --name NAME --binary PATH [options] [OUTPUT_DIR]
#
#   --name NAME      bundle and display name, NAME.app, required
#   --binary PATH    the executable to run inside the bundle, required
#   --id ID          CFBundleIdentifier (default com.jason.<name>)
#   --args "A B"     arguments the TUI starts with, space separated ("--tui")
#   --icon PATH      an .svg or .png rendered into the app icon
#   --version V      CFBundleShortVersionString and CFBundleVersion (default 1.0)
#   --link           store a symlink to --binary instead of a copy
#   --external       copy nothing and run --binary where it already is, for a program that writes
#                    its own updates beside its executable (a bundle would then be rewritten under
#                    its own seal: measured with agy, which stages .new.tar.gz in Resources)
#   --keywords "A,B" Finder and Spotlight keywords (kMDItemKeywords)
#
# OUTPUT_DIR defaults to ./dist. FLEA_OPEN names a stub `open` for tests, the way the launchers
# write it. The payload lives in Resources on purpose: a Mach-O beside the script launcher in
# Contents/MacOS is nested code an ad hoc signature refuses (see MACOS.md).
set -eu
name= binary= id= args= icon= version=1.0 link=0 external=0 keywords=
while [ $# -gt 0 ]; do
    case $1 in
        --name) name=$2; shift 2 ;;
        --binary) binary=$2; shift 2 ;;
        --id) id=$2; shift 2 ;;
        --args) args=$2; shift 2 ;;
        --icon) icon=$2; shift 2 ;;
        --version) version=$2; shift 2 ;;
        --link) link=1; shift ;;
        --external) external=1; shift ;;
        --keywords) keywords=$2; shift 2 ;;
        --) shift; break ;;
        -*) echo "build-tui-app: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
out=${1:-./dist}
[ -n "$name" ] && [ -n "$binary" ] || { echo "build-tui-app: --name and --binary are required" >&2; exit 2; }
[ -x "$binary" ] || { echo "build-tui-app: $binary is not an executable" >&2; exit 1; }
if [ -z "$id" ]; then
    id=com.jason.$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9.')
fi
bin_name=$(basename "$binary")
app=$out/$name.app

tmp=$(mktemp -d "${TMPDIR:-/tmp}/flea-app.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# The icon: an SVG is rendered once by Quick Look, a PNG is used as is, then both are cut into
# every iconset size.
icns=
if [ -n "$icon" ] && [ -f "$icon" ] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
    png=
    case $icon in
        *.svg)
            if command -v qlmanage >/dev/null 2>&1 && qlmanage -t -s 1024 -o "$tmp" "$icon" >/dev/null 2>&1; then
                [ -f "$tmp/$(basename "$icon").png" ] && png=$tmp/$(basename "$icon").png
            fi
            ;;
        *) png=$icon ;;
    esac
    if [ -n "$png" ]; then
        mkdir "$tmp/App.iconset"
        for size in 16 32 128 256 512; do
            sips -z "$size" "$size" "$png" --out "$tmp/App.iconset/icon_${size}x${size}.png" >/dev/null
            doubled=$((size * 2))
            sips -z "$doubled" "$doubled" "$png" --out "$tmp/App.iconset/icon_${size}x${size}@2x.png" >/dev/null
        done
        iconutil -c icns "$tmp/App.iconset" -o "$tmp/App.icns"
        icns=$tmp/App.icns
    fi
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
abs_binary=$(cd "$(dirname "$binary")" && pwd)/$bin_name
if [ "$external" = 1 ]; then
    # Nothing is copied: the program runs where its own updater expects to find it.
    run_launcher="\"$abs_binary\""
    run_command="\"$abs_binary\""
    where="the program at $abs_binary, which keeps its own updates and resources"
else
    if [ "$link" = 1 ]; then
        ln -s "$abs_binary" "$app/Contents/Resources/$bin_name"
    else
        cp "$binary" "$app/Contents/Resources/$bin_name"
        chmod 755 "$app/Contents/Resources/$bin_name"
    fi
    run_launcher="\"\$(dirname \"\$here\")/Resources/$bin_name\""
    run_command="\"\$(cd \"\$(dirname \"\$0\")\" && pwd)/$bin_name\""
    where="the binary inside this bundle, which is the one whose child processes and resources live here too"
fi
printf 'APPL????' > "$app/Contents/PkgInfo"
# The args are the build's own literal, never the user's input at launch.
argtail=${args:+ $args}
escaped_name=$(printf '%s' "$name" | sed 's/[&/\\]/\\&/g')

cat > "$app/Contents/MacOS/$name" <<LAUNCHER
#!/bin/sh
# $escaped_name's entry. Finder launches this with no terminal, so a launch without one opens
# Terminal on the bundle's own command file; run from a terminal, the TUI is exec'd in this process.
here=\$(cd "\$(dirname "\$0")" && pwd)
if [ -t 0 ] && [ -t 1 ]; then
    exec $run_launcher$argtail "\$@"
fi
exec "\${FLEA_OPEN:-/usr/bin/open}" -a Terminal "\$(dirname "\$here")/Resources/tui.command"
LAUNCHER
chmod 755 "$app/Contents/MacOS/$name"

cat > "$app/Contents/Resources/tui.command" <<COMMAND
#!/bin/sh
# The line Terminal runs for a Finder launch: the user's home, and $where.
cd "\$HOME" || exit 1
exec $run_command$argtail
COMMAND
chmod 755 "$app/Contents/Resources/tui.command"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$name</string>
    <key>CFBundleDisplayName</key><string>$name</string>
    <key>CFBundleIdentifier</key><string>$id</string>
    <key>CFBundleExecutable</key><string>$name</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
PLIST
if [ -n "$icns" ]; then
    cp "$icns" "$app/Contents/Resources/App.icns"
    printf '    <key>CFBundleIconFile</key><string>App</string>\n' >> "$app/Contents/Info.plist"
fi
printf '</dict>\n</plist>\n' >> "$app/Contents/Info.plist"

# Ad hoc: the bundle is built here, not downloaded, and the signature only proves the parts are
# the ones the build wrote. A script main executable makes the payload a resource, so this passes.
codesign --force --deep --sign - "$app" >/dev/null 2>&1 && codesign --verify --deep "$app" >/dev/null 2>&1 || {
    echo "build-tui-app: the bundle could not be signed" >&2
    exit 1
}
# Not sealed: the keywords ride the bundle's own extended attributes, which codesign leaves out.
[ -n "$keywords" ] && xattr -w com.apple.metadata:kMDItemKeywords "($keywords)" "$app"
echo "$app"
