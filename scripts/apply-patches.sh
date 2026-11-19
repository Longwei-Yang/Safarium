#!/bin/zsh
# Apply the Safarium patches to a Chromium checkout at the base revision.
#
#   scripts/apply-patches.sh /path/to/chromium/src
#
# The checkout must be at BASE (see README) with dependencies synced
# (`gclient sync -D`). The patches are applied as commits on a new
# `safarium` branch.
set -euo pipefail

BASE=b9e18363aa69f9e9e836a67fcfbb334c3dcf4598
SRC=${1:?usage: apply-patches.sh /path/to/chromium/src}
PATCHES=${0:A:h:h}/patches

cd "$SRC"
if [[ $(git rev-parse HEAD) != $BASE ]]; then
  echo "Expected $SRC at $BASE; run: git checkout $BASE && gclient sync -D" >&2
  exit 1
fi
git checkout -b safarium
git am --3way "$PATCHES"/*.patch
echo "Applied $(ls "$PATCHES"/*.patch | wc -l | tr -d ' ') patches on branch safarium."
