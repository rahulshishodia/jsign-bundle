#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
REQUESTED_TAG="${1:-}"
UPSTREAM_REPO='intoolswetrust/jsignpdf'
LINUX_DRIVER_URL='https://raw.githubusercontent.com/marcotuliomatos/ePass2003-SDK-Linux/c223d5380ab4c791c06951e08dd83587efc043e5/x86_64/redist/libcastle.so.1.0.0'
LINUX_DRIVER_SHA256='59c8c77f6248ba1acae89f61d3ee44abc298c8efd2cf9e16aba892c909d68ed4'

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jsignpdf-linux-build.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
if [[ -n "$REQUESTED_TAG" ]]; then
  RELEASE_API="https://api.github.com/repos/$UPSTREAM_REPO/releases/tags/$REQUESTED_TAG"
else
  RELEASE_API="https://api.github.com/repos/$UPSTREAM_REPO/releases/latest"
fi
curl -fsSL -o "$WORK_DIR/release.json" "$RELEASE_API"
readarray -t RELEASE < <(python3 - "$WORK_DIR/release.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
tag = data["tag_name"]
asset = next(a for a in data["assets"] if a["name"].startswith("jsignpdf-") and a["name"].endswith("-linux-x64.zip"))
print(tag)
print(asset["name"])
print(asset["browser_download_url"])
print(asset["digest"])
PY
)
TAG="${RELEASE[0]}"
VERSION="${TAG#JSignPdf_}"
VERSION="${VERSION//_/.}"
ARCHIVE="$WORK_DIR/${RELEASE[1]}"
curl -fL --retry 3 -o "$ARCHIVE" "${RELEASE[2]}"
echo "${RELEASE[3]#sha256:}  $ARCHIVE" | sha256sum -c -
mkdir -p "$WORK_DIR/upstream"
unzip -q "$ARCHIVE" -d "$WORK_DIR/upstream"

ORIGINAL_PATH="$(find "$WORK_DIR/upstream" -type f \( -name JSignPdf -o -name jsignpdf \) -perm -111 -print -quit)"
[[ -n "$ORIGINAL_PATH" ]] || { echo 'Unable to locate upstream Linux launcher' >&2; exit 1; }
APP_ROOT="$(dirname "$ORIGINAL_PATH")"
if [[ "$(basename "$APP_ROOT")" == bin ]]; then APP_ROOT="$(dirname "$APP_ROOT")"; fi
ORIGINAL_RELATIVE="${ORIGINAL_PATH#"$APP_ROOT"/}"

OUTPUT="$DIST_DIR/JSignPDF-AllInOne-linux-x64"
rm -rf "$OUTPUT"
mkdir -p "$DIST_DIR"
cp -a "$APP_ROOT" "$OUTPUT"
mkdir -p "$OUTPUT/AllInOne"
curl -fL --retry 3 -o "$OUTPUT/AllInOne/libcastle.so.1.0.0" "$LINUX_DRIVER_URL"
echo "$LINUX_DRIVER_SHA256  $OUTPUT/AllInOne/libcastle.so.1.0.0" | sha256sum -c -
cp "$ROOT_DIR/templates/linux-launcher.sh" "$OUTPUT/JSignPDF-AllInOne"
cp "$ROOT_DIR/templates/update-linux.sh" "$OUTPUT/AllInOne/update-linux.sh"
printf '%s\n' "$ORIGINAL_RELATIVE" > "$OUTPUT/AllInOne/original-executable"
printf '%s\n' "$VERSION" > "$OUTPUT/AllInOne/version"
chmod 755 "$OUTPUT/JSignPDF-AllInOne" "$OUTPUT/AllInOne/update-linux.sh" "$OUTPUT/AllInOne/libcastle.so.1.0.0"

(cd "$DIST_DIR" && zip -qr "JSignPDF-AllInOne-$VERSION-linux-x64.zip" "$(basename "$OUTPUT")")
(cd "$DIST_DIR" && sha256sum "JSignPDF-AllInOne-$VERSION-linux-x64.zip" > "JSignPDF-AllInOne-$VERSION-linux-x64.zip.sha256")
printf '%s\n' "$VERSION" > "$DIST_DIR/VERSION"
