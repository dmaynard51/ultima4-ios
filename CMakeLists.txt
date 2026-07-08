cmake_minimum_required(VERSION 3.13)
project(zu4 CXX C)

# ---------------------------------------------------------------------------
# iOS port of zu4 (Ultima IV). This CMake file targets iOS only; the desktop
# build still uses the Makefile. Configure with:
#   -DCMAKE_SYSTEM_NAME=iOS -DSDL2_INCLUDE_DIR=... -DSDL2_LIBRARY=... etc.
# ---------------------------------------------------------------------------

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Sources (mirrors CSRCS/CXXSRCS in the Makefile, plus the bundled miniz).
set(ZU4_C_SRCS
    deps/yxml/yxml.c
    deps/miniz/miniz.c
    src/lzw/hash.c src/lzw/lzw.c src/lzw/u4decode.c
    src/armor.c src/cmixer.c src/coords.c src/direction.c src/error.c
    src/image.c src/imageloader.c src/io.c src/moongate.c src/music.c
    src/names.c src/random.c src/rle.c src/savegame.c src/settings.c
    src/sound.c src/stb_vorbis.c src/xmlparse.c src/u4_sdl.c src/video.c
    src/weapon.c src/u4file.c)

set(ZU4_CXX_SRCS
    src/annotation.cpp src/aura.cpp src/camp.cpp src/cheat.cpp src/city.cpp
    src/codex.cpp src/combat.cpp src/config.cpp src/controller.cpp
    src/context.cpp src/conversation.cpp src/creature.cpp src/death.cpp
    src/dialogueloader.cpp src/dialogueloader_hw.cpp src/dialogueloader_lb.cpp
    src/dialogueloader_tlk.cpp src/dungeon.cpp src/dungeonview.cpp src/event.cpp
    src/event_sdl.cpp src/game.cpp src/imagemgr.cpp src/imageview.cpp
    src/intro.cpp src/item.cpp src/location.cpp src/map.cpp src/maploader.cpp
    src/mapmgr.cpp src/menu.cpp src/menuitem.cpp src/movement.cpp src/object.cpp
    src/person.cpp src/player.cpp src/portal.cpp src/progress_bar.cpp
    src/script.cpp src/screen.cpp src/shrine.cpp src/spell.cpp src/stats.cpp
    src/textview.cpp src/tile.cpp src/tileanim.cpp src/tilemap.cpp
    src/tileset.cpp src/tileview.cpp src/u4.cpp src/view.cpp src/xml.cpp)

# Touch-control overlay is added in a later step.
set(ZU4_IOS_SRCS "")

add_compile_definitions(ZU4_IOS)

include_directories(
    src src/lzw deps/yxml deps/miniz ios
    ${SDL2_INCLUDE_DIR}
    ${CMAKE_OSX_SYSROOT}/usr/include/libxml2)

add_executable(zu4 MACOSX_BUNDLE
    ${ZU4_C_SRCS} ${ZU4_CXX_SRCS} ${ZU4_IOS_SRCS})

# --- iOS frameworks + libs ---
find_library(FW_UIKIT UIKit)
find_library(FW_FOUNDATION Foundation)
find_library(FW_COREGRAPHICS CoreGraphics)
find_library(FW_QUARTZCORE QuartzCore)
find_library(FW_COREMOTION CoreMotion)
find_library(FW_METAL Metal)
find_library(FW_OPENGLES OpenGLES)
find_library(FW_AUDIOTOOLBOX AudioToolbox)
find_library(FW_AVFOUNDATION AVFoundation)
find_library(FW_COREAUDIO CoreAudio)
find_library(FW_COREVIDEO CoreVideo)
find_library(FW_GAMECONTROLLER GameController)
find_library(FW_COREHAPTICS CoreHaptics)
find_library(FW_IMAGEIO ImageIO)
find_library(FW_COREFOUNDATION CoreFoundation)
find_library(FW_COREBLUETOOTH CoreBluetooth)

target_link_libraries(zu4
    ${SDL2_LIBRARY} ${SDL2MAIN_LIBRARY}
    "-lxml2" "-lz"
    ${FW_UIKIT} ${FW_FOUNDATION} ${FW_COREGRAPHICS} ${FW_QUARTZCORE}
    ${FW_COREMOTION} ${FW_METAL} ${FW_OPENGLES} ${FW_AUDIOTOOLBOX}
    ${FW_AVFOUNDATION} ${FW_COREAUDIO} ${FW_COREVIDEO} ${FW_GAMECONTROLLER}
    ${FW_COREHAPTICS} ${FW_IMAGEIO} ${FW_COREFOUNDATION} ${FW_COREBLUETOOTH})

IF(NOT ZU4_IOS_BUNDLE_ID)
    set(ZU4_IOS_BUNDLE_ID "info.zu4.ultima4")
ENDIF()

set_target_properties(zu4 PROPERTIES
    MACOSX_BUNDLE_BUNDLE_NAME "Ultima IV"
    MACOSX_BUNDLE_GUI_IDENTIFIER "${ZU4_IOS_BUNDLE_ID}"
    MACOSX_BUNDLE_BUNDLE_VERSION "1.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/ios/Info.plist.in"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "13.0")

# App icon: compile ios/Assets.xcassets (holding the AppIcon set) into the bundle.
target_sources(zu4 PRIVATE "${CMAKE_SOURCE_DIR}/ios/Assets.xcassets")
set_source_files_properties("${CMAKE_SOURCE_DIR}/ios/Assets.xcassets"
    PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
set_target_properties(zu4 PROPERTIES
    XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME "AppIcon")

IF(ZU4_IOS_TEAM)
    set_target_properties(zu4 PROPERTIES
        XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
        XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${ZU4_IOS_TEAM}"
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${ZU4_IOS_BUNDLE_ID}")
ENDIF()

# --- Bundle zu4's own data (conf/graphics/music/sound) into the app ---
foreach(dir conf graphics music sound)
    add_custom_command(TARGET zu4 POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_SOURCE_DIR}/${dir}" "$<TARGET_BUNDLE_DIR:zu4>/${dir}")
endforeach()

# --- Bundle the original Ultima IV game files into ./ultima4/ ---
IF(ZU4_U4_GAMEDIR)
    add_custom_command(TARGET zu4 POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${ZU4_U4_GAMEDIR}" "$<TARGET_BUNDLE_DIR:zu4>/ultima4")
ELSE()
    message(WARNING "ZU4_U4_GAMEDIR not set - app will build without U4 game data.")
ENDIF()
