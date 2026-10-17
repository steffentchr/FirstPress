#!/bin/sh
# Renders First Press Menu's artwork from the SVG sources in Design/ into
# Menu/Resources/Assets.xcassets: the Mac app icon at every size macOS asks
# for, and the two menu-bar icons at 1x and 2x. Mac icons keep their
# transparent corners; the menu-bar icons are template images.
#
# Needs rsvg-convert: brew install librsvg
set -eu
cd "$(dirname "$0")/.."
assets=Menu/Resources/Assets.xcassets

for px in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$px" -h "$px" Design/MenuAppIcon.svg -o "$assets/AppIcon.appiconset/AppIcon-$px.png"
done

for icon in MenuBarIcon MenuBarIconPlaying; do
  rsvg-convert -w 18 -h 18 "Design/$icon.svg" -o "$assets/$icon.imageset/$icon.png"
  rsvg-convert -w 36 -h 36 "Design/$icon.svg" -o "$assets/$icon.imageset/$icon@2x.png"
done
