#!/bin/zsh
# Shoots First Press's App Store screenshots in the simulator and frames them.
#
#   AppStore/FirstPress/screenshots.sh               shoot every scene in demo.json, then frame
#   AppStore/FirstPress/screenshots.sh --frame-only  re-frame the raw shots (after editing captions)
#
# It applies Hook/hook.patch and copies Hook/ScreenshotDemo.swift into the app
# for one build, and reverts both on exit, so the app source stays clean.
# Needs Xcode, xcodegen, rsvg-convert and ImageMagick (see the root README.md › Artwork).
set -euo pipefail

HERE=${0:A:h}
ROOT=${HERE:h:h}
SIM=${SIM:-"iPhone 17 Pro"}   # 6.3" display: 1206 x 2622, a size App Store Connect's iPhone slot takes
RAW=$HERE/Screenshots/raw
OUT=$HERE/Screenshots/6.3-inch
TOUCHED=(App/Sources/FirstPressApp.swift App/Sources/RootView.swift App/Sources/FirstPressSheet.swift App/Sources/NowPlayingView.swift project.yml)

# The scenes shot in the simulator. A scene "from" another app is drawn
# into raw/ by that app's screenshots.sh instead, and only framed here; it
# must come after the shot ones, which are numbered as they're shot.
scenes() { python3 -c 'import json,sys; [print(s["scene"]) for s in json.load(open(sys.argv[1]))["screenshots"] if "from" not in s]' $HERE/demo.json }

shoot() {
  cd $ROOT
  git diff --quiet -- $TOUCHED || { echo "Commit or stash changes to ${TOUCHED[*]} first." >&2; exit 1; }

  cleanup() {
    cd $ROOT
    git checkout -- $TOUCHED
    rm -rf App/ScreenshotDemo App/Sources/ScreenshotDemo.swift
    xcodegen generate --quiet || true
  }
  trap cleanup EXIT

  git apply $HERE/Hook/hook.patch
  cp $HERE/Hook/ScreenshotDemo.swift App/Sources/
  mkdir -p App/ScreenshotDemo
  cp $HERE/demo.json App/ScreenshotDemo/
  for svg in $HERE/Covers/*.svg; do
    rsvg-convert -w 1000 -h 1000 $svg | magick - -alpha remove -alpha off App/ScreenshotDemo/${svg:t:r}.png
  done
  xcodegen generate --quiet

  local udid=$(xcrun simctl list devices available | grep -F "$SIM (" | head -1 | grep -oE '[0-9A-F-]{36}')
  [[ -n $udid ]] || { echo "No simulator named $SIM." >&2; exit 1; }
  local derived=${TMPDIR:-/tmp}/firstpress-screenshots
  xcodebuild -project FirstPress.xcodeproj -scheme FirstPress -destination "id=$udid" \
    -derivedDataPath $derived build CODE_SIGNING_ALLOWED=NO -quiet
  local app=$derived/Build/Products/Debug-iphonesimulator/FirstPress.app
  local bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' $app/Info.plist)

  # English, US clock ("9:41", not "09.41"), dark mode, a full status bar.
  xcrun simctl shutdown $udid 2>/dev/null || true
  xcrun simctl boot $udid
  xcrun simctl bootstatus $udid -b >/dev/null
  xcrun simctl spawn $udid defaults write -g AppleLocale en_US
  xcrun simctl spawn $udid defaults write -g AppleLanguages -array en
  xcrun simctl shutdown $udid
  xcrun simctl boot $udid
  xcrun simctl bootstatus $udid -b >/dev/null
  xcrun simctl ui $udid appearance dark
  xcrun simctl status_bar $udid override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  xcrun simctl install $udid $app
  xcrun simctl privacy $udid grant microphone $bundle

  mkdir -p $RAW
  local n=0
  for scene in $(scenes); do
    n=$((n + 1))
    xcrun simctl terminate $udid $bundle 2>/dev/null || true
    xcrun simctl launch $udid $bundle -FirstPressScreenshot $scene >/dev/null
    # A Record needs a moment to start and its Track to be identified.
    case $scene in nowPlaying|rooms|history) sleep 25 ;; *) sleep 8 ;; esac
    xcrun simctl io $udid screenshot $RAW/$(printf %02d $n)-$scene.png >/dev/null 2>&1
    echo "shot $scene"
  done
}

frame() {
  mkdir -p $OUT
  python3 - $HERE/demo.json $RAW $OUT <<'PY'
import json, subprocess, sys, html, os
demo, raw, out = sys.argv[1:]
# 1206 x 2622, the 6.3" size, the simulator's own. The layout below was
# drawn at 1320 pixels wide; k scales it. ../FirstPressMenu/frame.py draws
# the Mac layer at this size too.
W, H = 1206, 2622
k = W / 1320
shot_w = round(1040 * k); shot_h = round(shot_w * H / W); x = (W - shot_w) // 2; y = round(560 * k)
r_bezel, r_screen, bezel = 150 * k, 128 * k, 22 * k
for n, s in enumerate(json.load(open(demo))["screenshots"], 1):
    name = f"{n:02d}-{s['scene']}"
    src = os.path.join(raw, name + ".png")
    lines = s["caption"].split("\n")
    # A scene "from" another app is a finished layer, the size of the
    # screenshot, laid over the background as it is, without a phone.
    layer = "from" in s
    # Store sizes are exact: a shot from a simulator of another size would
    # be stretched into the frame, so refuse it.
    size = subprocess.run(["magick", "identify", "-format", "%w %h", src], check=True, capture_output=True, text=True).stdout.split()
    if list(map(int, size)) != [W, H]:
        sys.exit(f"{src} is {size[0]} x {size[1]}, not {W} x {H}: shoot on a 6.3-inch simulator.")
    tspans = "".join(f'<tspan x="{W//2}" dy="{0 if i == 0 else 108 * k}">{html.escape(l)}</tspan>' for i, l in enumerate(lines))
    phone = f'''<rect x="{x-bezel}" y="{y-bezel+30*k}" width="{shot_w+2*bezel}" height="{shot_h+2*bezel}" rx="{r_bezel}" fill="#000" opacity=".45" filter="url(#shadow)"/>
  <rect x="{x-bezel}" y="{y-bezel}" width="{shot_w+2*bezel}" height="{shot_h+2*bezel}" rx="{r_bezel}" fill="#0d0c0b"/>
  <image x="{x}" y="{y}" width="{shot_w}" height="{shot_h}" xlink:href="{os.path.basename(src)}" clip-path="url(#screen)"/>'''
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{W}" height="{H}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f08a52"/><stop offset=".55" stop-color="#d4551f"/><stop offset="1" stop-color="#9a3410"/></linearGradient>
    <clipPath id="screen"><rect x="{x}" y="{y}" width="{shot_w}" height="{shot_h}" rx="{r_screen}"/></clipPath>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="{30*k}"/></filter>
  </defs>
  <rect width="{W}" height="{H}" fill="url(#bg)"/>
  <text y="{(300 if len(lines) > 1 else 400) * k}" text-anchor="middle" font-family="Helvetica Neue" font-weight="700" font-size="{88 * k}" fill="#fff">{tspans}</text>
  {phone if not layer else f'<image x="0" y="0" width="{W}" height="{H}" xlink:href="{os.path.basename(src)}"/>'}
</svg>'''
    svg_path = os.path.join(raw, name + ".frame.svg")
    open(svg_path, "w").write(svg)
    png = subprocess.run(["rsvg-convert", svg_path], check=True, capture_output=True).stdout
    subprocess.run(["magick", "-", "-alpha", "remove", "-alpha", "off", "-define", "png:exclude-chunks=date,time", os.path.join(out, name + ".png")], input=png, check=True)
    os.remove(svg_path)
    print("framed", name)
PY
}

[[ ${1:-} == --frame-only ]] || shoot
frame
