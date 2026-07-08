#!/bin/bash
# Build + sign Ultima IV (zu4) for a physical iPhone/iPad and install it.
#
# Ultima IV is free, so the game data is downloaded automatically if not given.
#
# Prereqs:
#   - Xcode signed in with the Apple ID that owns the development team.
#   - iPhone connected by cable, unlocked, and "Trust This Computer" accepted.
#   - Developer Mode on (Settings > Privacy & Security > Developer Mode).
#   - cmake (brew install cmake).
#
# Usage: ios/build-ios-device.sh <AppleTeamID> [/path/to/ultima4]
#   e.g. ios/build-ios-device.sh ABCDE12345
#
# Your Team ID is a 10-character code (e.g. ABCDE12345), NOT your name. Find it
# at https://developer.apple.com/account -> Membership details -> Team ID, or run
#   security find-identity -v -p codesigning   (it's the code in parentheses).
set -euo pipefail

ZU4_SRC="$(cd "$(dirname "$0")/.." && pwd)"
TEAM="${1:?Usage: build-ios-device.sh <AppleTeamID> [ultima4-data-dir]}"
U4_DATA="${2:-}"
WORK="${HOME}/Library/Caches/zu4-ios-build"
SDL_VER="2.30.10"
BUNDLE_ID="${ZU4_IOS_BUNDLE_ID:-info.zu4.ultima4}"

if ! [[ "$TEAM" =~ ^[A-Za-z0-9]{10}$ ]]; then
  echo "ERROR: '$TEAM' is not a valid Apple Team ID (10 letters/digits)." >&2
  echo "  Pass ONLY the code, not your name. Find it at" >&2
  echo "  https://developer.apple.com/account -> Membership details -> Team ID" >&2
  exit 1
fi

mkdir -p "$WORK"; cd "$WORK"

# 0. Ultima IV game data (free download if not supplied).
# Require BOTH AVATAR.EXE and TITLE.EXE (the intro reads its signature data from
# title.exe); a partial extract otherwise crashes on the title screen.
data_ok() { [ -f "$1/AVATAR.EXE" ] || [ -f "$1/avatar.exe" ] && { [ -f "$1/TITLE.EXE" ] || [ -f "$1/title.exe" ]; }; }
if [ -z "$U4_DATA" ]; then
  U4_DATA="$WORK/ultima4"
  if ! data_ok "$U4_DATA"; then
    echo "Downloading the free Ultima IV game data..."
    curl -L -o u4.zip "http://ultima.thatfleminggent.com/ultima4.zip"
    rm -rf "$U4_DATA"; mkdir -p "$U4_DATA" && (cd "$U4_DATA" && unzip -oq ../u4.zip)
  fi
fi
if ! data_ok "$U4_DATA"; then
  echo "ERROR: Ultima IV data in '$U4_DATA' is missing/incomplete (need AVATAR.EXE + TITLE.EXE)." >&2
  exit 1
fi

# 1. SDL2 static for the device (built once).
if [ ! -f "$WORK/sdl2-device/Release-iphoneos/libSDL2.a" ]; then
  [ -d "SDL2-${SDL_VER}" ] || {
    curl -L -o SDL2.tar.gz \
      "https://github.com/libsdl-org/SDL/releases/download/release-${SDL_VER}/SDL2-${SDL_VER}.tar.gz"
    tar xzf SDL2.tar.gz
  }
  rm -rf sdl2-device && mkdir sdl2-device && cd sdl2-device
  cmake "../SDL2-${SDL_VER}" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DSDL_STATIC=ON -DSDL_SHARED=OFF -DSDL_TEST=OFF
  xcodebuild -project SDL2.xcodeproj -target SDL2-static -configuration Release \
    -sdk iphoneos -arch arm64 CODE_SIGNING_ALLOWED=NO
  xcodebuild -project SDL2.xcodeproj -target SDL2main -configuration Release \
    -sdk iphoneos -arch arm64 CODE_SIGNING_ALLOWED=NO
  cd "$WORK"
fi
SDL_SRC="$WORK/SDL2-${SDL_VER}"
SDL_LIBDIR="$WORK/sdl2-device/Release-iphoneos"

# 2. Configure + build the signed app.
rm -rf zu4-device && mkdir zu4-device && cd zu4-device
cmake "$ZU4_SRC" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DSDL2_INCLUDE_DIR="$SDL_SRC/include" \
  -DSDL2_LIBRARY="$SDL_LIBDIR/libSDL2.a" \
  -DSDL2MAIN_LIBRARY="$SDL_LIBDIR/libSDL2main.a" \
  -DZU4_U4_GAMEDIR="$U4_DATA" -DZU4_IOS_TEAM="$TEAM" -DZU4_IOS_BUNDLE_ID="$BUNDLE_ID"
xcodebuild -project zu4.xcodeproj -target zu4 -configuration Release \
  -sdk iphoneos -arch arm64 -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM"

APP="$WORK/zu4-device/Release-iphoneos/zu4.app"
echo; echo "Signed app: $APP"

# 3. Install + launch on the first connected device.
DEVICE_ID="$(xcrun devicectl list devices 2>/dev/null \
  | awk '/available/ && /iPhone|iPad/ {print $3; exit}')"
if [ -n "${DEVICE_ID:-}" ]; then
  echo "Installing to $DEVICE_ID ..."
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
  xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"
  echo "On the phone, trust the developer once: Settings > General >"
  echo "  VPN & Device Management > Developer App > Trust. Then hold it landscape."
else
  echo "No connected device found. Connect+unlock your iPhone and re-run."
fi
