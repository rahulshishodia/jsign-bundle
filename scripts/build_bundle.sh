#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
UPSTREAM_REPO='intoolswetrust/jsignpdf'
REQUESTED_TAG="${1:-}"
EPASS_MAC_URL='https://www.e-mudhra.com/Repository/downloads/ePass2003_MAC_iOS.zip'
EPASS_MAC_SHA256='3708c8629765c6db22ae05cad891016e1e17c98bde04988e2cbfae9651b7749e'

command -v curl >/dev/null
command -v plutil >/dev/null
command -v codesign >/dev/null
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jsignpdf-build.XXXXXX")"
MOUNT_POINT=''
cleanup() {
  if [[ -n "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ -n "${EPASS_DRIVER_PATH:-}" ]]; then
  VENDOR_DRIVER="$EPASS_DRIVER_PATH"
else
  EPASS_ARCHIVE="$WORK_DIR/epass-macos.zip"
  curl -fL --retry 3 -o "$EPASS_ARCHIVE" "$EPASS_MAC_URL"
  echo "$EPASS_MAC_SHA256  $EPASS_ARCHIVE" | shasum -a 256 -c -
  EPASS_UNPACKED="$WORK_DIR/epass"
  mkdir -p "$EPASS_UNPACKED"
  unzip -q "$EPASS_ARCHIVE" -d "$EPASS_UNPACKED"
  EPASS_DMG="$(find "$EPASS_UNPACKED" -type f -name '*.dmg' -print -quit)"
  MOUNT_POINT="$WORK_DIR/epass-mount"
  mkdir -p "$MOUNT_POINT"
  hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$EPASS_DMG" >/dev/null
  EPASS_PKG="$(find "$MOUNT_POINT" -maxdepth 2 -type f -name '*.pkg' -print -quit)"
  EPASS_EXPANDED="$WORK_DIR/epass-pkg"
  pkgutil --expand-full "$EPASS_PKG" "$EPASS_EXPANDED"
  VENDOR_DRIVER="$(find "$EPASS_EXPANDED" -type f -name 'libcastle_v2.1.0.0.dylib' -print -quit)"
fi

[[ -f "$VENDOR_DRIVER" ]] || {
  echo "Unable to locate the macOS ePass PKCS#11 library" >&2
  exit 1
}

if [[ -n "$REQUESTED_TAG" ]]; then
  RELEASE_API="https://api.github.com/repos/$UPSTREAM_REPO/releases/tags/$REQUESTED_TAG"
else
  RELEASE_API="https://api.github.com/repos/$UPSTREAM_REPO/releases/latest"
fi

METADATA="$WORK_DIR/release.json"
curl -fsSL -o "$METADATA" "$RELEASE_API"
UPSTREAM_TAG="$(plutil -extract tag_name raw "$METADATA")"
VERSION="${UPSTREAM_TAG#JSignPdf_}"
VERSION="${VERSION//_/.}"

ASSET_URL=''
ASSET_DIGEST=''
ASSET_NAME=''
for INDEX in $(seq 0 50); do
  NAME="$(plutil -extract "assets.$INDEX.name" raw "$METADATA" 2>/dev/null)" || break
  if [[ "$NAME" == jsignpdf-*-macos-aarch64.zip ]]; then
    ASSET_NAME="$NAME"
    ASSET_URL="$(plutil -extract "assets.$INDEX.browser_download_url" raw "$METADATA")"
    ASSET_DIGEST="$(plutil -extract "assets.$INDEX.digest" raw "$METADATA")"
    break
  fi
done

[[ -n "$ASSET_URL" && "$ASSET_DIGEST" == sha256:* ]] || {
  echo "No checksum-bearing macOS aarch64 ZIP found in $UPSTREAM_TAG" >&2
  exit 1
}

ARCHIVE="$WORK_DIR/$ASSET_NAME"
if [[ -n "${UPSTREAM_ARCHIVE:-}" ]]; then
  ditto "$UPSTREAM_ARCHIVE" "$ARCHIVE"
else
  curl -fL --retry 3 -o "$ARCHIVE" "$ASSET_URL"
fi

EXPECTED_SHA="${ASSET_DIGEST#sha256:}"
ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
[[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] || {
  echo "Upstream checksum mismatch: expected $EXPECTED_SHA, got $ACTUAL_SHA" >&2
  exit 1
}

EXTRACT_DIR="$WORK_DIR/extracted"
mkdir -p "$EXTRACT_DIR"
ditto -x -k "$ARCHIVE" "$EXTRACT_DIR"
UPSTREAM_APP="$EXTRACT_DIR/JSignPdf.app"
[[ -d "$UPSTREAM_APP/Contents" ]] || {
  echo "The upstream archive does not contain JSignPdf.app" >&2
  exit 1
}

mkdir -p "$DIST_DIR"
OUTPUT_APP="$DIST_DIR/JSignPDF-AllInOne.app"
rm -rf "$OUTPUT_APP"
ditto "$UPSTREAM_APP" "$OUTPUT_APP"

INFO_PLIST="$OUTPUT_APP/Contents/Info.plist"
ORIGINAL_EXECUTABLE="$(plutil -extract CFBundleExecutable raw "$INFO_PLIST")"
INTEGRATION_DIR="$OUTPUT_APP/Contents/Resources/AllInOne"
mkdir -p "$INTEGRATION_DIR"
ditto "$VENDOR_DRIVER" "$INTEGRATION_DIR/libcastle_v2.1.0.0.dylib"
ditto "$ROOT_DIR/templates/update.sh" "$INTEGRATION_DIR/update.sh"
ditto "$ROOT_DIR/templates/JSignPdfLauncher" "$OUTPUT_APP/Contents/MacOS/JSignPdfLauncher"
printf '%s\n' "$ORIGINAL_EXECUTABLE" > "$INTEGRATION_DIR/original-executable"
chmod 755 "$OUTPUT_APP/Contents/MacOS/JSignPdfLauncher" "$INTEGRATION_DIR/update.sh"

/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable JSignPdfLauncher' "$INFO_PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName JSignPDF All-in-One' "$INFO_PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string JSignPDF All-in-One' "$INFO_PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName JSignPDF All-in-One' "$INFO_PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.rahuls.jsignpdf.allinone' "$INFO_PLIST"

xattr -cr "$OUTPUT_APP"
if codesign --force --deep --sign - "$OUTPUT_APP" && \
   codesign --verify --deep --strict "$OUTPUT_APP"; then
  :
elif [[ "${ALLOW_UNSIGNED_BUILD:-0}" == '1' ]]; then
  echo "Warning: producing an unsigned local artifact because ALLOW_UNSIGNED_BUILD=1." >&2
  codesign --remove-signature "$OUTPUT_APP" 2>/dev/null || true
else
  exit 1
fi

OUTPUT_ZIP="$DIST_DIR/JSignPDF-AllInOne-$VERSION-macos-aarch64.zip"
rm -f "$OUTPUT_ZIP" "$OUTPUT_ZIP.sha256"
ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_APP" "$OUTPUT_ZIP"
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$OUTPUT_ZIP")" > "$(basename "$OUTPUT_ZIP").sha256")
printf '%s\n' "$VERSION" > "$DIST_DIR/VERSION"

echo "Built $OUTPUT_ZIP"
