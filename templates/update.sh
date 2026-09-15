#!/bin/zsh

set -u

APP_BUNDLE="$1"
APP_PID="$2"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
VERSION_FILE="$APP_BUNDLE/Contents/Resources/AllInOne/version"
CACHE_DIR="${JSIGNPDF_UPDATE_CACHE_DIR:-$HOME/Library/Caches/com.rahuls.jsignpdf.allinone}"
METADATA_FILE="$CACHE_DIR/latest-release.json"
SKIPPED_FILE="$CACHE_DIR/skipped-version"
API_URL='https://api.github.com/repos/rahulshishodia/jsign-bundle/releases/latest'

mkdir -p "$CACHE_DIR"

# Stay silent offline and keep launch independent of GitHub availability.
/usr/bin/curl -fsSL --connect-timeout 3 --max-time 10 \
  -o "$METADATA_FILE.tmp" "$API_URL" || exit 0
mv -f "$METADATA_FILE.tmp" "$METADATA_FILE"

LATEST_TAG="$(/usr/bin/plutil -extract tag_name raw "$METADATA_FILE" 2>/dev/null)" || exit 0
LATEST_VERSION="${LATEST_TAG#v}"
if [[ -f "$VERSION_FILE" ]]; then
  CURRENT_VERSION="$(<"$VERSION_FILE")"
else
  CURRENT_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$INFO_PLIST" 2>/dev/null)" || exit 0
fi

[[ -n "$LATEST_VERSION" && "$LATEST_VERSION" != "$CURRENT_VERSION" ]] || exit 0
if [[ -f "$SKIPPED_FILE" && "$(<"$SKIPPED_FILE")" == "$LATEST_VERSION" ]]; then
  exit 0
fi

ASSET_URL=''
ASSET_DIGEST=''
for INDEX in {0..50}; do
  ASSET_NAME="$(/usr/bin/plutil -extract "assets.$INDEX.name" raw "$METADATA_FILE" 2>/dev/null)" || break
  if [[ "$ASSET_NAME" == JSignPDF-AllInOne-*-macos-aarch64.zip ]]; then
    ASSET_URL="$(/usr/bin/plutil -extract "assets.$INDEX.browser_download_url" raw "$METADATA_FILE" 2>/dev/null)"
    ASSET_DIGEST="$(/usr/bin/plutil -extract "assets.$INDEX.digest" raw "$METADATA_FILE" 2>/dev/null)"
    break
  fi
done

[[ -n "$ASSET_URL" && "$ASSET_DIGEST" == sha256:* ]] || exit 0

DIALOG_RESULT="$(/usr/bin/osascript -e \
  "button returned of (display dialog \"JSignPDF $LATEST_VERSION is available. Download and install it after JSignPDF closes?\" with title \"JSignPDF Update\" buttons {\"Later\", \"Update\"} default button \"Update\" cancel button \"Later\")" 2>/dev/null)" || {
    print -r -- "$LATEST_VERSION" > "$SKIPPED_FILE"
    exit 0
  }
[[ "$DIALOG_RESULT" == 'Update' ]] || exit 0

WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR%/}/jsignpdf-update.XXXXXX")" || exit 0
cleanup() {
  /bin/rm -rf "$WORK_DIR"
}
trap cleanup EXIT

ARCHIVE="$WORK_DIR/update.zip"
/usr/bin/curl -fL --retry 3 -o "$ARCHIVE" "$ASSET_URL" || exit 0
EXPECTED_SHA="${ASSET_DIGEST#sha256:}"
ACTUAL_SHA="$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  /usr/bin/osascript -e 'display alert "JSignPDF update rejected" message "The downloaded SHA-256 checksum did not match the GitHub release metadata." as critical' >/dev/null 2>&1
  exit 0
fi

STAGE_DIR="$WORK_DIR/stage"
mkdir -p "$STAGE_DIR"
/usr/bin/ditto -x -k "$ARCHIVE" "$STAGE_DIR" || exit 0
NEW_APP="$STAGE_DIR/JSignPDF-AllInOne.app"
[[ -d "$NEW_APP/Contents" ]] || exit 0
/usr/bin/codesign --verify --deep --strict "$NEW_APP" >/dev/null 2>&1 || exit 0

/usr/bin/osascript -e 'display notification "Update downloaded. Quit JSignPDF to finish and reopen automatically." with title "JSignPDF Update"' >/dev/null 2>&1
while /bin/kill -0 "$APP_PID" 2>/dev/null; do
  /bin/sleep 2
done

PARENT_DIR="${APP_BUNDLE:h}"
if [[ ! -w "$PARENT_DIR" ]]; then
  DOWNLOAD_TARGET="$HOME/Downloads/JSignPDF-AllInOne-$LATEST_VERSION.app"
  /usr/bin/ditto "$NEW_APP" "$DOWNLOAD_TARGET"
  /usr/bin/open -R "$DOWNLOAD_TARGET"
  exit 0
fi

BACKUP_APP="$PARENT_DIR/JSignPDF-AllInOne-previous-$CURRENT_VERSION.app"
if [[ -e "$BACKUP_APP" ]]; then
  BACKUP_APP="$PARENT_DIR/JSignPDF-AllInOne-previous-$CURRENT_VERSION-$(/bin/date +%s).app"
fi
/bin/mv "$APP_BUNDLE" "$BACKUP_APP" || exit 0
/bin/mv "$NEW_APP" "$APP_BUNDLE" || {
  /bin/mv "$BACKUP_APP" "$APP_BUNDLE"
  exit 0
}
/usr/bin/open "$APP_BUNDLE"
