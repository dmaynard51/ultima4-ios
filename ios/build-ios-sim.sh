#!/bin/bash
# Build Ultima IV (zu4) as a native iOS app for the iOS Simulator.
#
# Ultima IV is free (Origin released it), so this script downloads the game
# data automatically if you don't provide it.
#
# Prereqs: Xcode + command-line tools, cmake (brew install cmake).
# Usage:
#   ios/build-ios-sim.sh                    # auto-downloads the U4 data
#   ios/build-ios-sim.sh /path/to/ultima4   # or use your own copy
set -euo pipefail

ZU4_SRC="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${HOME}/Library/Caches/zu4-ios-build"
SDL_VER="2.30.10"
ARCH="arm64"   # arm64 simulator (Apple Silicon); use x86_64 on Intel Macs.
BUNDLE_ID="${ZU4_IOS_BUNDLE_ID:-info.zu4.ultima4}"
U4_DATA="${1:-}"

mkdir -p "$WORK"; cd "$WORK"

# 0. Ultima IV game data (free download if not supplied).
if [ -z "$U4_DATA" ]; then
  U4_DATA="$WORK/ultima4"
  if [ ! -f "$U4_DATA/AVATAR.EXE" ] && [ ! -f "$U4_DATA/avatar.exe" ]; then
    echo "Downloading the free Ultima IV game data..."
    curl -L -o u4.zip "http://ultima.thatfleminggent.com/ultima4.zip"
    mkdir -p "$U4_DATA" && (cd "$U4_DATA" && unzip -oq ../u4.zip)
  fi
fi

# 1. SDL2 static for the iOS Simulator (built once).
if [ ! -f "$WORK/sdl2-sim/Release-iphonesimulator/libSDL2.a" ]; then
  [ -d "SDL2-${SDL_VER}" ] || {
    curl -L -o SDL2.tar.gz \
      "https://github.com/libsdl-org/SDL/releases/download/release-${SDL_VER}/SDL2-${SDL_VER}.tar.gz"
    tar xzf SDL2.tar.gz
  }
  rm -rf sdl2-sim && mkdir sdl2-sim && cd sdl2-sim
  cmake "../SDL2-${SDL_VER}" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES="${ARCH}" -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DSDL_STATIC=ON -DSDL_SHARED=OFF -DSDL_TEST=OFF
  xcodebuild -project SDL2.xcodeproj -target SDL2-static -configuration Release \
    -sdk iphonesimulator -arch "${ARCH}"
  xcodebuild -project SDL2.xcodeproj -target SDL2main -configuration Release \
    -sdk iphonesimulator -arch "${ARCH}"
  cd "$WORK"
fi
SDL_SRC="$WORK/SDL2-${SDL_VER}"
SDL_LIBDIR="$WORK/sdl2-sim/Release-iphonesimulator"

# 2. Configure + build the app.
rm -rf zu4-sim && mkdir zu4-sim && cd zu4-sim
cmake "$ZU4_SRC" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES="${ARCH}" -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DSDL2_INCLUDE_DIR="$SDL_SRC/include" \
  -DSDL2_LIBRARY="$SDL_LIBDIR/libSDL2.a" \
  -DSDL2MAIN_LIBRARY="$SDL_LIBDIR/libSDL2main.a" \
  -DZU4_U4_GAMEDIR="$U4_DATA" -DZU4_IOS_BUNDLE_ID="$BUNDLE_ID"
xcodebuild -project zu4.xcodeproj -target zu4 -configuration Release \
  -sdk iphonesimulator -arch "${ARCH}" CODE_SIGNING_ALLOWED=NO

APP="$WORK/zu4-sim/Release-iphonesimulator/zu4.app"
echo; echo "Built: $APP"; echo "Run with:"
echo "  xcrun simctl boot 'iPhone 15' 2>/dev/null; open -a Simulator"
echo "  xcrun simctl install booted '$APP'"
echo "  xcrun simctl launch booted $BUNDLE_ID"
echo "  (rotate the Simulator to landscape: Device > Rotate, or Cmd+Left)"
