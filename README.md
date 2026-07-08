# Ultima IV on iOS (zu4)

**Play Ultima IV: Quest of the Avatar natively on your iPhone or iPad, with touch
controls.** This is an iOS port of the `zu4` engine (a clean SDL2 fork of xu4).

Ultima IV is **free** — Origin released it — so the build downloads the game data
for you. Getting it on your phone is basically two steps.

## 🚀 Install

Requires a **Mac** with **Xcode** and `cmake` (`brew install cmake`).

**iOS Simulator** (no Apple account needed):

```sh
git clone https://github.com/dmaynard51/ultima4-ios.git
cd ultima4-ios
ios/build-ios-sim.sh          # downloads U4 data, builds, prints run commands
```

**On your iPhone/iPad** (needs a free Apple ID; pass your 10-char Team ID):

```sh
ios/build-ios-device.sh ABCDE12345
```

That's it — it downloads the game data, builds, signs, installs, and launches.
First run on the phone: trust the app once under **Settings ▸ General ▸ VPN &
Device Management**, then hold it in **landscape**.

➡️ Touch controls: [ios/CONTROLS.md](ios/CONTROLS.md)
(Find your Team ID: `security find-identity -v -p codesigning` — the code in parentheses.)

## ☕ Support this port

This iOS port is a free, open-source labor of love — porting the engine, adding
touch controls, drawing the icon, and keeping it working takes real time. If it
let you play Ultima IV on your phone and you'd like to say thanks, a coffee is
hugely appreciated (and completely optional):

- ☕ **[Buy me a coffee (Ko-fi)](https://ko-fi.com/dmaynard)**
- 💜 **[GitHub Sponsors](https://github.com/sponsors/dmaynard51)**

You supply nothing but a Mac — the game data is downloaded from Ultima IV's free
release; none is included in this repo.

---

Everything below is the original upstream zu4 README (desktop builds).

# Zesty Ultima IV

This is a cleaned up, modernized fork of "xu4".

### WARNING
This codebase is probably broken in a lot of ways.
I am not looking for code contributions right now,
as I am trying to realize my vision for the project
before accepting outside assistance. However, any
suggestions or bug reports are welcome.

#### How to Compile
Currently, the following dependencies are required:
libsdl2, libxml2
```
make
```

#### Where to Get Game Files
```
http://ultima.thatfleminggent.com/u4download.html
http://www.moongates.com/u4/upgrade/Upgrade.htm
```
Direct Links:
```
http://ultima.thatfleminggent.com/ultima4.zip
http://prdownloads.sourceforge.net/xu4/u4upgrad.zip?download
http://www.moongates.com/u4/upgrade/files/u4upgrad.zip
```

#### Project Goals
* Greatly simplify the codebase
* Remove all external dependencies from the engine
* Make the engine simple to plug into any framework
* Convert from ugly C++ to beautiful C
* Make it "Just Work"
