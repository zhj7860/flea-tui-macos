#!/bin/sh
# lf calls a previewer with the file and the preview pane geometry: $1 file, $2 width, $3 height,
# $4 x, $5 y. Exiting 1 tells lf not to cache the output, which is what an image preview needs.
case "$1" in
  *.jpg|*.jpeg|*.png|*.webp|*.heic|*.gif)
    kitten icat --stdin no --transfer-mode file --place "${2}x${3}@${4}x${5}" "$1" </dev/null >/dev/tty
    exit 1
    ;;
esac
head -100 "$1"
