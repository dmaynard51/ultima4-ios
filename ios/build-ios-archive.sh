#!/bin/bash
# Archive Ultima IV (zu4) for iOS and export a development-signed .ipa that can
# be installed on your own registered devices (Apple Configurator, the Xcode
# Devices window, or `xcrun devicectl device install app`).
#
# Ultima IV is free, so the game data is downloaded automatically if not given.
#
# Prereqs:
#   - Xcode signed in with the Apple ID that owns the development team.
#   - cmake (brew install cmake).
#
# Usage: ios/build-ios-archive.sh <AppleTeamID> [/path/to/ultima4]
#   e.g. ios/build-ios-archive.sh ABCDE12345
#
# Your Team ID is a 10-character code (e.g. ABCDE12345), NOT your name. Find it
# at https://developer.apple.com/account -> Membership details -> Team ID, or run
#   security find-identity -v -p codesigning   (it's the code in parentheses).
set -euo pipefail

ZU4_SRC="$(cd "$(dirname "$0")/.." && pwd)"
TEAM="${1:?Usage: build-ios-archive.sh <AppleTeamID> [ultima4-data-dir]}"
U4_DATA="${2:-}"
# Build under Caches, never in-source: codesign fails inside iCloud-synced dirs.
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

# 1. SDL2 static for the device (iphoneos arm64), built once and shared with
# build-ios-device.sh.
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

# 2. Configure the device build (with an Xcode scheme, needed for archiving).
rm -rf zu4-archive && mkdir zu4-archive && cd zu4-archive
cmake "$ZU4_SRC" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_XCODE_GENERATE_SCHEME=ON \
  -DSDL2_INCLUDE_DIR="$SDL_SRC/include" \
  -DSDL2_LIBRARY="$SDL_LIBDIR/libSDL2.a" \
  -DSDL2MAIN_LIBRARY="$SDL_LIBDIR/libSDL2main.a" \
  -DZU4_U4_GAMEDIR="$U4_DATA" -DZU4_IOS_TEAM="$TEAM" -DZU4_IOS_BUNDLE_ID="$BUNDLE_ID"

# 3. Archive. -allowProvisioningUpdates lets Xcode create/refresh the
# provisioning profile for the bundle id automatically.
ARCHIVE="$WORK/zu4.xcarchive"
rm -rf "$ARCHIVE"
xcodebuild archive -project zu4.xcodeproj -scheme zu4 \
  -configuration Release -sdk iphoneos -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM"

# 4. Export a development-signed .ipa.
EXPORT_DIR="$WORK/zu4-ipa"
rm -rf "$EXPORT_DIR"
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>debugging</string>
    <key>teamID</key><string>${TEAM}</string>
    <key>signingStyle</key><string>automatic</string>
    <key>compileBitcode</key><false/>
    <key>thinning</key><string>&lt;none&gt;</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -allowProvisioningUpdates

IPA="$(ls "$EXPORT_DIR"/*.ipa | head -1)"
echo
echo "Archive: $ARCHIVE"
echo "IPA:     $IPA"
echo
echo "Install on a connected device with:"
echo "  xcrun devicectl list devices"
echo "  xcrun devicectl device install app --device <id> \"$IPA\""
echo "Or drag the .ipa onto the device in Finder / Apple Configurator."
