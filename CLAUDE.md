# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

«Ретро КР580» — an emulator of Soviet 8-bit home computers (Радио-86РК, Микроша, Партнер 01.01, Апогей БК-01, Микро-80, ЮТ-88, Специалист/MX/MX2, Орион-128) built around the КР580ВМ80А (i8080) / Z80 CPU. Written entirely in Objective-C (ARC) as a document-based Cocoa app for macOS; also builds on Linux via GNUstep. Comments, commit messages, and UI strings are in Russian — keep that convention.

## Build

There are no tests or linters. Builds use `-Werror`, so any warning breaks the build.

Two build systems exist and **must be kept in sync when adding/removing source files**:
- `CMakeLists.txt` (source lists grouped as `RETRO80_*_SOURCES`; ROM images are picked up by glob from `Retro80/ROM/`, other resources listed in `RETRO80_GLOBAL_RESOURCES`)
- `Retro80.xcodeproj` (Xcode; also contains the `QLRetro80` QuickLook plugin target; ROMs are listed explicitly there)

```sh
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug     # Debug defines DEBUG
cmake --build build
./build/Retro80.app/Retro80                          # GNUstep; on macOS it is a regular .app bundle
sudo cmake --install build                           # GNUstep: installs Retro80.app into GNUSTEP_LOCAL_APPS
```

GNUstep itself (libobjc2 + libdispatch, gnustep-2.2 ABI, ARC; distro packages won't work) is built from source by `scripts/build-gnustep.sh` into `/usr/GNUstep` (Arch/Manjaro and Debian/Ubuntu; `--deps` installs build dependencies, component names rebuild selectively). On non-Apple platforms CMake locates GNUstep via `gnustep-config`, defaults the compiler to clang and the linker to lld, takes the runtime ABI from `gnustep-config --objc-flags`, defines `GNUSTEP`, uses `GNUstep-Prefix.pch` (which shims missing Cocoa APIs such as `NSMenuItemValidation`, `NSMenuItem.hidden`), and swaps `Sound.m` (AudioToolbox) for `GNUstep-Sound.m` (miniaudio, fetched by CMake `FetchContent` and built as a small C library; Objective-C flags are applied to OBJC sources only) plus `GNUstep-Stub.m`. In both implementations the audio callback drives emulation: each output buffer runs `-[Computer execute:]` for exactly its duration. Platform-specific code is guarded with `#ifdef GNUSTEP`. Keyboard `kbdmap` tables use macOS virtual key codes (kVK_*); on GNUstep/X11, `macKeyCode()` in `RKKeyboard.m` translates X11 (evdev) key codes to them, and by default GNUstep maps left Alt to Command (key events ignored by the emulator) and right Alt to Option (РУС/ЛАТ). 86RKSD resolves paths case-insensitively (`resolvePath()` in `RKSDCard.m`). GNUstep limitations: menu items that are hidden on macOS show up disabled. Work plan for the GNUstep/Windows port: `GNUstep-plan.md`.

## Architecture

All sources are flat in `Retro80/`; ROM images are in `Retro80/ROM/` and loaded as bundle resources (`[ROM initWithContentsOfResource:mask:]`).

**App shell (Cocoa document model):** `Document` holds one `Computer`; the whole machine state is saved/loaded with `NSKeyedArchiver` as the native `.retro80` document type, while tape/program files (`.rk`, `.gam`, `.rkm`, …) are routed through `ComputerFactory computerFromData:URL:` by file extension and the document is then converted to the default type. `WindowController` starts/stops the computer; `Display` (OpenGL, with `tvnoise.vs/.fs` shaders), `Sound`, and `Debug` (debugger console, ⌘D) are attached to the computer as properties.

**Computer hierarchy:**
- `Computer` (NSResponder) — base: quartz frequency, clock, emulation thread driven by `execute:`, tape in/out hooks (`inpHook`/`outHook`), menu validation. Subclasses must override the lifecycle hooks:
  - `createObjects` — build chips/memory for a fresh machine (called from `initWithQuartz:`)
  - `decodeWithCoder:` / `encodeWithCoder:` — restore/save state (called from `initWithCoder:`)
  - `mapObjects` — wire objects into the CPU address/port space; called after *both* create and decode paths, so all mapping must live here, not in the create/decode methods.
- `Retro80` — base for i8080/Z80 machines: owns `cpu` (`X8080`), `rom`, `ram`, `crt` (`CRT` protocol), `snd` (`SND` protocol).
- Concrete machines: `RK86Base` → `Radio86RK`, `Microsha`, `Apogeo`, `Partner`; `Micro80`, `UT88`; `Specialist`, `SpecialistSP580`, `SpecialistMX`; `Orion128`. Each machine typically has its own `*Keyboard`, `*Screen`, `*Recorder`, `*Floppy`/`*SDCard` classes.

**Bus model (`x8080.h`):** devices implement small protocols — `RD`, `WR`, `BYTE`, `RESET`, `HLDA` (DMA), `IRQ`, `INTE` — and are attached with `X8080 mapObject:from:to:` (memory, optionally per `PAGE` for banked machines) or `mapObject:atPort:` (I/O). All device calls carry the CPU clock (`CLK:`/`clock:`) so peripherals emulate timing lazily. `MEM`/`RAM`/`ROM` in `mem.h` support windowed views via `memoryAtOffest:mask:`.

**Chip emulations:** `x8080` (CPU, also Z80 mode), `Dbg80` (disassembler/debugger), `x8253` (ВИ53 timer/sound), `x8255` (ВВ55 PPI), `x8257` (ВТ57 DMA), `x8275` (ВГ75 CRT controller), `vg93` (ВГ93 floppy controller).

**Factories / menu tags:** `ComputerFactory` holds an ordered list of per-family factories (`Radio86RKFactory`, `Micro80Factory`, `SpecialistFactory`, `Orion128Factory`). A "New" menu item tag encodes `(factoryIndex+1)*100 + machineTag`, dispatched to the family factory's `computerByTag:`. Adding a new machine means: a factory case, a menu item in `ru.lproj/MainMenu.xib` with the matching tag, file extensions in the factory (and `Retro80-Info.plist` document types), plus entries in both build files. Machine option menus are handled via `validateMenuItem:` switching on `menuItem.tag`.
