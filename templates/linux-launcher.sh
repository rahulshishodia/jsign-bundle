#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${JSIGNPDF_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/jsignpdf-allinone}"
mkdir -p "$CONFIG_DIR"
printf '# Managed by JSignPDF All-in-One.\nname=HYP2003\nlibrary="%s"\n' \
  "$ROOT_DIR/AllInOne/libcastle.so.1.0.0" > "$CONFIG_DIR/pkcs11.cfg"

"$ROOT_DIR/AllInOne/update-linux.sh" "$ROOT_DIR" "$$" >/dev/null 2>&1 &

export JSIGNPDF_CONFIG_DIR="$CONFIG_DIR"
ORIGINAL_EXECUTABLE="$(cat "$ROOT_DIR/AllInOne/original-executable")"
exec "$ROOT_DIR/$ORIGINAL_EXECUTABLE" "$@"

