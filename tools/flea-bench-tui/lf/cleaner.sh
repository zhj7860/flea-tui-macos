#!/bin/sh
# Without this the previous image stays on screen over the next file's preview.
kitten icat --clear --stdin no --transfer-mode file </dev/null >/dev/tty
