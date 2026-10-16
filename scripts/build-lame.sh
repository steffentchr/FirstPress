#!/bin/bash
# Builds LAME 3.100's libmp3lame as a static XCFramework (ADR-0002):
#   iOS device arm64, iOS simulator arm64 + x86_64, and macOS arm64.
# The result, Vendor/LAME.xcframework, is a build output and is not checked in.
#
# Usage: scripts/build-lame.sh [--if-missing]
#   --if-missing  do nothing if Vendor/LAME.xcframework already exists.
#                 `xcodegen generate` runs it this way (project.yml preGenCommand).
#
# Set LAME_TARBALL to a local lame-3.100.tar.gz to skip the download.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
OUTPUT="$VENDOR/LAME.xcframework"

if [[ "${1:-}" == "--if-missing" && -d "$OUTPUT" ]]; then
  exit 0
fi

URL=https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
EXPECTED_SHA=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
MIN_IOS=17.0
MIN_MACOS=14.0

WORK="$(mktemp -d "${TMPDIR:-/tmp}/lame-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
OUT="$WORK/out"
mkdir -p "$OUT"

TARBALL="${LAME_TARBALL:-$WORK/lame-3.100.tar.gz}"
if [[ ! -f "$TARBALL" ]]; then
  echo "Downloading LAME 3.100"
  curl --fail --location --silent --show-error --output "$TARBALL" "$URL"
fi
echo "$EXPECTED_SHA  $TARBALL" | shasum -a 256 -c -

build_slice() {
  local name="$1" sdk="$2" target="$3" host="$4"
  local src="$WORK/src-$name"
  mkdir -p "$src"
  tar -xzf "$TARBALL" -C "$src" --strip-components 1
  # 3.100 lists lame_init_old in its export list but never defines it. Only
  # the shared library link uses the list, but remove it anyway, as
  # Homebrew's 3.100 formula did.
  sed -i '' '/lame_init_old/d' "$src/include/libmp3lame.sym"

  local sysroot cc
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  cc="$(xcrun --sdk "$sdk" -f clang)"
  # Modern clang rejects LAME's implicit declarations, and it doesn't build as C23.
  local cflags="-target $target -isysroot $sysroot -O3 -std=gnu99 -Wno-implicit-function-declaration"

  echo "Building $name"
  ( cd "$src" && \
    ac_cv_prog_cc_c23=no \
    CC="$cc" CFLAGS="$cflags" LDFLAGS="-target $target -isysroot $sysroot" \
    ./configure --host="$host" --prefix="$OUT/$name" \
      --disable-shared --enable-static \
      --disable-frontend --disable-decoder --disable-debug \
      --disable-dependency-tracking && \
    make -j"$(sysctl -n hw.ncpu)" -C libmp3lame && \
    make -C libmp3lame install && make -C include install ) > "$WORK/$name.log" 2>&1 \
    || { tail -40 "$WORK/$name.log"; exit 1; }
}

build_slice ios-arm64     iphoneos        "arm64-apple-ios${MIN_IOS}"            aarch64-apple-darwin
build_slice iossim-arm64  iphonesimulator "arm64-apple-ios${MIN_IOS}-simulator"  aarch64-apple-darwin
build_slice iossim-x86_64 iphonesimulator "x86_64-apple-ios${MIN_IOS}-simulator" x86_64-apple-darwin
build_slice macos-arm64   macosx          "arm64-apple-macos${MIN_MACOS}"        aarch64-apple-darwin

# The simulator architectures must be one fat library inside the XCFramework.
mkdir -p "$OUT/iossim"
lipo -create "$OUT/iossim-arm64/lib/libmp3lame.a" "$OUT/iossim-x86_64/lib/libmp3lame.a" \
     -output "$OUT/iossim/libmp3lame.a"

# lame.h plus a module map, so Swift can `import LAME`.
HEADERS="$OUT/headers"
mkdir -p "$HEADERS"
cp "$OUT/ios-arm64/include/lame/lame.h" "$HEADERS/"
cat > "$HEADERS/module.modulemap" <<'EOF'
module LAME {
    header "lame.h"
    link "mp3lame"
    export *
}
EOF

mkdir -p "$VENDOR"
rm -rf "$OUTPUT"
xcodebuild -create-xcframework \
  -library "$OUT/ios-arm64/lib/libmp3lame.a"   -headers "$HEADERS" \
  -library "$OUT/iossim/libmp3lame.a"          -headers "$HEADERS" \
  -library "$OUT/macos-arm64/lib/libmp3lame.a" -headers "$HEADERS" \
  -output "$OUTPUT" > /dev/null

echo "Built $OUTPUT"
