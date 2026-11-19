#!/bin/zsh
# Package out/Release/Safarium.app into an ad-hoc signed DMG in ~/chromium/dist.
#
# Why not just Chromium's sign_chrome.py output:
#  - it enables hardened runtime + library validation; with an ad-hoc
#    signature (no Team ID) the app then refuses to load its own framework
#    ("Library not loaded ... libaperitif.dylib"), so we re-sign without them;
#  - its pkg-dmg step leaves com.apple.FinderInfo on every file, which fails
#    `codesign --verify --strict`, so we build the DMG with hdiutil instead.
# With a real Developer ID, use sign_chrome.py --identity <ID> --notarize instead.
set -euo pipefail

SRC=${SAFARIUM_SRC:-$HOME/chromium/src}
OUT=$SRC/out/Release
DIST=${SAFARIUM_DIST:-$HOME/chromium/dist}
# depot_tools must be on PATH.

VERSION=$(defaults read "$OUT/Safarium.app/Contents/Info.plist" CFBundleShortVersionString)
WORK=$(mktemp -d /tmp/safarium-pkg.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

echo "== packaging scripts"
autoninja -C "$OUT" chrome/installer/mac:mac >/dev/null

echo "== sign (Chromium signing pipeline, ad-hoc)"
(cd "$OUT/Safarium Packaging" && vpython3 sign_chrome.py --identity - --development \
  --no-embed-development-provisioning-profile --notarize none --disable-packaging \
  --input "$OUT" --output "$WORK/signed" > "$WORK/sign.log" 2>&1) || { tail -20 "$WORK/sign.log"; exit 1; }
APP=$(find "$WORK/signed" -maxdepth 3 -name Safarium.app -type d | head -1)

echo "== re-sign ad-hoc without hardened runtime"
mkdir -p "$WORK/stage"
ditto --noextattr --noqtn "$APP" "$WORK/stage/Safarium.app"
xattr -cr "$WORK/stage/Safarium.app"
codesign --force --deep --sign - --preserve-metadata=entitlements "$WORK/stage/Safarium.app"
codesign --verify --deep --strict "$WORK/stage/Safarium.app"
ln -s /Applications "$WORK/stage/Applications"

echo "== dmg"
mkdir -p "$DIST"
DMG="$DIST/Safarium-$VERSION-arm64.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname Safarium -srcfolder "$WORK/stage" -fs HFS+ -format ULMO "$DMG"
shasum -a 256 "$DMG"
