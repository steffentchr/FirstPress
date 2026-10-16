#!/bin/sh
# Xcode Cloud runs this right after cloning, before it looks for the project.
# The .xcodeproj is generated (project.yml) and the signing and Last.fm
# xcconfigs are git-ignored, so this script recreates all three.
#
# Environment variables, set in the Xcode Cloud workflow (App Store Connect ›
# Xcode Cloud › Manage Workflows › Environment):
#   PRESSING_BUNDLE_ID          the app's bundle ID                  (required)
#   PRESSING_DEVELOPMENT_TEAM   the 10-character team ID             (required)
#   PRESSING_LASTFM_API_KEY     Last.fm API key, marked Secret       (optional)
#   PRESSING_LASTFM_API_SECRET  Last.fm shared secret, marked Secret (optional)
set -eu

cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"

if [ -z "${PRESSING_BUNDLE_ID:-}" ] || [ -z "${PRESSING_DEVELOPMENT_TEAM:-}" ]; then
  echo "error: set PRESSING_BUNDLE_ID and PRESSING_DEVELOPMENT_TEAM in the Xcode Cloud workflow's environment." >&2
  exit 1
fi

cat > Config/Signing.xcconfig <<XCCONFIG
PRESSING_BUNDLE_ID = ${PRESSING_BUNDLE_ID}
PRESSING_DEVELOPMENT_TEAM = ${PRESSING_DEVELOPMENT_TEAM}
XCCONFIG

if [ -n "${PRESSING_LASTFM_API_KEY:-}" ] && [ -n "${PRESSING_LASTFM_API_SECRET:-}" ]; then
  cat > Config/LastFm.xcconfig <<XCCONFIG
PRESSING_LASTFM_API_KEY = ${PRESSING_LASTFM_API_KEY}
PRESSING_LASTFM_API_SECRET = ${PRESSING_LASTFM_API_SECRET}
XCCONFIG
else
  echo "warning: no Last.fm keys in the environment; this build can't connect Last.fm."
fi

# XcodeGen generates Pressing.xcodeproj; its preGenCommand builds
# Vendor/LAME.xcframework first (downloads LAME 3.100 once).
brew install xcodegen
xcodegen generate
