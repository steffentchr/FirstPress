#!/bin/zsh
# Renders Pressing Menu's Mac App Store screenshots from the real panel and
# Settings window, frames them, and re-frames the iPhone set, whose last
# screenshot is built from these renders.
#
#   AppStore/PressingMenu/screenshots.sh               render, then frame both sets
#   AppStore/PressingMenu/screenshots.sh --frame-only  re-frame only (after editing captions)
#
# It applies Hook/hook.patch and copies Hook/ScreenshotDemo.swift into the
# Mac app for one build, and reverts both on exit, so the app source stays
# clean. The sample world is AppStore/Pressing/demo.json, the same as the
# iPhone set's. Needs Xcode, xcodegen, rsvg-convert and ImageMagick.
set -euo pipefail

HERE=${0:A:h}
ROOT=${HERE:h:h}
IPHONE=${HERE:h}/Pressing
RAW=$HERE/Screenshots/raw
TOUCHED=(Menu/Sources/PressingMenuApp.swift Menu/Sources/PanelView.swift project.yml)

shoot() {
  cd $ROOT
  git diff --quiet -- $TOUCHED || { echo "Commit or stash changes to ${TOUCHED[*]} first." >&2; exit 1; }

  cleanup() {
    cd $ROOT
    git checkout -- $TOUCHED
    rm -f Menu/Sources/ScreenshotDemo.swift
    xcodegen generate --quiet || true
  }
  trap cleanup EXIT

  git apply $HERE/Hook/hook.patch
  cp $HERE/Hook/ScreenshotDemo.swift Menu/Sources/
  xcodegen generate --quiet

  local derived=${TMPDIR:-/tmp}/pressing-menu-screenshots
  local covers=$derived/Covers
  mkdir -p $covers $RAW
  for svg in $IPHONE/Covers/*.svg; do
    rsvg-convert -w 1000 -h 1000 $svg | magick - -alpha remove -alpha off $covers/${svg:t:r}.png
  done
  xcodebuild -project Pressing.xcodeproj -scheme PressingMenu -destination 'platform=macOS' \
    -derivedDataPath $derived build CODE_SIGNING_ALLOWED=NO -quiet
  local app="$derived/Build/Products/Debug/Pressing Menu.app"
  # It renders, writes the PNGs and quits by itself.
  rm -f $RAW/panel-history.png $RAW/panel-rooms.png $RAW/settings.png
  "$app/Contents/MacOS/Pressing Menu" -PressingMenuScreenshot $RAW \
    -PressingMenuDemo $IPHONE/demo.json -PressingMenuCovers $covers \
    -AppleAccentColor 4  # macOS's default blue, whatever this Mac uses
  [[ -f $RAW/settings.png ]] || { echo "Pressing Menu rendered nothing." >&2; exit 1; }
}

frame() {
  python3 $HERE/frame.py $HERE
  $IPHONE/screenshots.sh --frame-only
}

[[ ${1:-} == --frame-only ]] || shoot
frame
