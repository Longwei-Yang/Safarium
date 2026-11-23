#!/bin/zsh
# Package out/Release/Safarium.app into a signed DMG in ~/chromium/dist.
#
# Why not just Chromium's sign_chrome.py output:
#  - it enables hardened runtime + library validation; without a Team ID
#    (ad hoc or self-signed) the app then refuses to load its own framework
#    ("Library not loaded ... libaperitif.dylib"), so we re-sign without them;
#  - its pkg-dmg step leaves com.apple.FinderInfo on every file, which fails
#    `codesign --verify --strict`, so we build the DMG with hdiutil instead.
# With a real Developer ID, use sign_chrome.py --identity <ID> --notarize instead.
#
# The app is signed with a fixed self-signed certificate (see
# make-signing-identity.sh), so its designated requirement is the same in
# every build and macOS keeps Safarium's permission for its "Safarium Safe
# Storage" keychain item across updates. An ad hoc signature changes with
# every build, so macOS asks again after each update; if the app can't read
# that key at startup, Chromium drops the cookies and settings it encrypted.
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

echo "== re-sign without hardened runtime"
mkdir -p "$WORK/stage"
ditto --noextattr --noqtn "$APP" "$WORK/stage/Safarium.app"
xattr -cr "$WORK/stage/Safarium.app"
# Identity for Safarium's updater (safarium_updater.h): a release passes
# SAFARIUM_TAG=v<version>-fix<N>; anything else is a local build, based on
# the newest released fix and named *-local-<commit>.dmg.
COMMIT=$(git -C "$SRC" rev-parse --short=10 HEAD)
if [[ -n ${SAFARIUM_TAG:-} ]]; then
  [[ $SAFARIUM_TAG =~ '-fix([0-9]+)$' ]] || { echo "SAFARIUM_TAG must end in -fix<N>"; exit 1; }
  FIX=${match[1]}; TAG=$SAFARIUM_TAG; SUFFIX=""
else
  FIX=${SAFARIUM_BASE_FIX:-$(git -C "${SAFARIUM_REPO:-${0:A:h:h}}" tag -l 'v*-fix*' 2>/dev/null | sed -E 's/.*-fix//' | sort -n | tail -1)}
  FIX=${FIX:-0}; TAG=local; SUFFIX="-local-$COMMIT"
fi
PLIST="$WORK/stage/Safarium.app/Contents/Info.plist"
plutil -replace SafariumBuild -integer "$FIX" "$PLIST"
plutil -replace SafariumTag -string "$TAG" "$PLIST"
plutil -replace SafariumCommit -string "$COMMIT" "$PLIST"
echo "   $TAG (fix$FIX, $COMMIT)"
SIGN_DIR=${SAFARIUM_SIGNING_DIR:-$HOME/chromium/signing}
KEYCHAIN=$SIGN_DIR/safarium-signing.keychain-db
if [[ -f $KEYCHAIN && -f $SIGN_DIR/keychain-password ]]; then
  security unlock-keychain -p "$(<$SIGN_DIR/keychain-password)" "$KEYCHAIN"
  IDENTITY=$(security find-identity -p codesigning "$KEYCHAIN" | awk '/"Safarium Code Signing"/ {print $2; exit}')
fi
if [[ -n ${IDENTITY:-} ]]; then
  echo "   signing as Safarium Code Signing ($IDENTITY)"
  SIGN=(--sign "$IDENTITY" --keychain "$KEYCHAIN" --timestamp=none)
elif [[ -n ${SAFARIUM_TAG:-} ]]; then
  echo "No signing identity in $SIGN_DIR (run make-signing-identity.sh); a release must keep its certificate."; exit 1
else
  echo "   WARNING: no signing identity in $SIGN_DIR, signing ad hoc (macOS will ask for keychain access again)"
  SIGN=(--sign -)
fi
codesign --force --deep "${SIGN[@]}" --preserve-metadata=entitlements "$WORK/stage/Safarium.app"
codesign --verify --deep --strict "$WORK/stage/Safarium.app"
ln -s /Applications "$WORK/stage/Applications"

echo "== dmg"
mkdir -p "$DIST"
DMG="$DIST/Safarium-$VERSION-arm64$SUFFIX.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname Safarium -srcfolder "$WORK/stage" -fs HFS+ -format ULMO "$DMG"
shasum -a 256 "$DMG"
