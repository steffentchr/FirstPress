#!/bin/sh
# Xcode Cloud runs this right after cloning, before it looks for the project.
# The .xcodeproj is generated (project.yml) and the signing and Last.fm
# xcconfigs are git-ignored, so this script recreates all three.
#
# Environment variables, set in the Xcode Cloud workflow (App Store Connect ›
# Xcode Cloud › Manage Workflows › Environment):
#   FIRSTPRESS_BUNDLE_ID            the app's bundle ID                  (required)
#   FIRSTPRESS_DEVELOPMENT_TEAM     the 10-character team ID             (required)
#   FIRSTPRESS_LASTFM_API_KEY       Last.fm API key, marked Secret       (optional)
#   FIRSTPRESS_LASTFM_API_SECRET    Last.fm shared secret, marked Secret (optional)
set -eu

cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"

if [ -z "${FIRSTPRESS_BUNDLE_ID:-}" ] || [ -z "${FIRSTPRESS_DEVELOPMENT_TEAM:-}" ]; then
  echo "error: set FIRSTPRESS_BUNDLE_ID and FIRSTPRESS_DEVELOPMENT_TEAM in the Xcode Cloud workflow's environment." >&2
  exit 1
fi

cat > Config/Signing.xcconfig <<XCCONFIG
FIRSTPRESS_BUNDLE_ID = ${FIRSTPRESS_BUNDLE_ID}
FIRSTPRESS_DEVELOPMENT_TEAM = ${FIRSTPRESS_DEVELOPMENT_TEAM}
XCCONFIG

if [ -n "${FIRSTPRESS_LASTFM_API_KEY:-}" ] && [ -n "${FIRSTPRESS_LASTFM_API_SECRET:-}" ]; then
  cat > Config/LastFm.xcconfig <<XCCONFIG
FIRSTPRESS_LASTFM_API_KEY = ${FIRSTPRESS_LASTFM_API_KEY}
FIRSTPRESS_LASTFM_API_SECRET = ${FIRSTPRESS_LASTFM_API_SECRET}
XCCONFIG
else
  echo "warning: no Last.fm keys in the environment; this build can't connect Last.fm."
fi

# XcodeGen generates FirstPress.xcodeproj; its preGenCommand builds
# Vendor/LAME.xcframework first (downloads LAME 3.100 once).
brew install xcodegen
xcodegen generate
