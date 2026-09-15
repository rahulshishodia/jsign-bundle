#!/bin/bash

set -u

APP_DIR="$1"
APP_PID="$2"
CURRENT_VERSION="$(cat "$APP_DIR/AllInOne/version")"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/jsignpdf-allinone"
API_URL='https://api.github.com/repos/rahulshishodia/jsign-bundle/releases/latest'
mkdir -p "$CACHE_DIR"
METADATA="$CACHE_DIR/latest.json"
curl -fsSL --connect-timeout 3 --max-time 10 -o "$METADATA.tmp" "$API_URL" || exit 0
mv -f "$METADATA.tmp" "$METADATA"

readarray -t RELEASE < <(python3 - "$METADATA" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
version = data.get("tag_name", "").removeprefix("v")
asset = next((a for a in data.get("assets", []) if a["name"].startswith("JSignPDF-AllInOne-") and a["name"].endswith("-linux-x64.zip")), {})
print(version)
print(asset.get("browser_download_url", ""))
print(asset.get("digest", ""))
PY
)
LATEST_VERSION="${RELEASE[0]:-}"
ASSET_URL="${RELEASE[1]:-}"
ASSET_DIGEST="${RELEASE[2]:-}"
[[ -n "$LATEST_VERSION" && "$LATEST_VERSION" != "$CURRENT_VERSION" && "$ASSET_DIGEST" == sha256:* ]] || exit 0

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jsignpdf-update.XXXXXX")" || exit 0
trap 'rm -rf "$WORK_DIR"' EXIT
curl -fL --retry 3 -o "$WORK_DIR/update.zip" "$ASSET_URL" || exit 0
echo "${ASSET_DIGEST#sha256:}  $WORK_DIR/update.zip" | sha256sum -c - || exit 0
unzip -q "$WORK_DIR/update.zip" -d "$WORK_DIR/stage" || exit 0
NEW_APP="$WORK_DIR/stage/JSignPDF-AllInOne-linux-x64"
[[ -x "$NEW_APP/JSignPDF-AllInOne" ]] || exit 0

command -v notify-send >/dev/null && notify-send 'JSignPDF Update' 'Update downloaded; quit JSignPDF to install it.' || true
while kill -0 "$APP_PID" 2>/dev/null; do sleep 2; done
[[ -w "$(dirname "$APP_DIR")" ]] || exit 0
BACKUP="$APP_DIR.previous-$CURRENT_VERSION-$(date +%s)"
mv "$APP_DIR" "$BACKUP" || exit 0
mv "$NEW_APP" "$APP_DIR" || { mv "$BACKUP" "$APP_DIR"; exit 0; }
"$APP_DIR/JSignPDF-AllInOne" >/dev/null 2>&1 &

