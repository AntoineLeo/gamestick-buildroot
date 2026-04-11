# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an automated build system for a custom Linux rootfs targeting the **GameStick Lite 4K** (model M8, Rockchip RK3032 SoC). It produces a micro-SD image containing RetroArch + 23 libretro emulator cores, replacing only the rootfs partition of the original GameStick firmware while preserving the bootloader, kernel, and userdata partitions.

**Target hardware**: ARMv7-A, dual-core Cortex-A7 @ 1GHz, 256 MB RAM, Mali-400MP GPU, hard-float EABI5 (armhf).

## Build Commands

All operations go through `build.sh`:

```bash
./build.sh setup        # Install host deps, download Buildroot 2025.02, create dirs
./build.sh configure    # Generate defconfig + dynamic Buildroot package definitions
./build.sh menuconfig   # Launch interactive Buildroot config menu
./build.sh build        # Full cross-compile (1–3 hours); produces rootfs.ext4
./build.sh cores <name> # Post-build: compile an individual additional core
./build.sh image        # Assemble final SD image (requires original gamestick.img backup)
./build.sh all          # Run all steps sequentially
./build.sh clean        # Remove build artifacts
```

The `image` step requires an original GameStick backup image (`gamestick.img`) in the working directory. The output is `output/gamestick_custom.img`, ready to flash with `dd` or balenaEtcher.

## Architecture

### Build Pipeline

`build.sh` orchestrates everything. It does **not** modify existing Buildroot packages — instead, it **dynamically generates** `package/retroarch/` and `package/libretro-{core}/` directories inside `buildroot-2025.02/`, each containing a `Config.in` and `.mk` file templated in the script. Sources are pulled fresh from GitHub at build time.

### Key Files

| File | Role |
|------|------|
| `build.sh` | Main orchestration script (1008 lines); all build logic lives here |
| `configs/gamestick_rk3032_defconfig` | Buildroot board config: arch, ABI, enabled packages |
| `overlay/etc/init.d/S99retroarch` | Init.d script that mounts userdata and launches RetroArch |
| `overlay/etc/retroarch/retroarch.cfg` | Tuned RetroArch config (SDL2/fbdev video, ALSA audio, RGUI menu) |
| `gamestick_knowledge_base.md` | Hardware reference: RK3032 specs, partition table, boot chain, core-to-system map |

### Image Partition Strategy

The final image preserves three partitions from the original firmware and only replaces `rootfs`:

```
uboot (1 MB)    ← original, preserved
trust (2 MB)    ← original, preserved
boot (9 MB)     ← original, preserved (contains kernel + DTB)
rootfs (128 MB) ← REPLACED with new EXT4 rootfs
userdata (rest) ← original, preserved (ROMs, saves go here at /sdcard)
```

### Runtime Flow

1. U-Boot → ARM Trusted Firmware → original Linux kernel (from boot partition)
2. BusyBox init runs `/etc/init.d/rcS`
3. `S99retroarch` auto-detects and mounts userdata partition to `/sdcard`
4. RetroArch launches with config from `/etc/retroarch/retroarch.cfg`
5. Cores in `/usr/lib/libretro/*.so`, ROMs from `/sdcard/roms`, saves to `/sdcard/saves`

### Cross-Compilation

Buildroot creates the toolchain at `buildroot-2025.02/output/host/bin/arm-buildroot-linux-gnueabihf-*`. This same toolchain is used by `./build.sh cores <name>` for post-build core additions.

Compilation flags used throughout:
```
-marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -O2 -U_TIME_BITS -D_TIME_BITS=32
```

### Design Constraints (256 MB RAM)

RetroArch is configured to minimize memory use:
- **Video**: SDL2 driver, framebuffer (`fbdev`) — no OpenGL/Vulkan/X11
- **Menu**: RGUI (lightweight text-based), not XMB/Ozone
- **Disabled**: rewind, auto-save, online updaters, shaders
- **Audio**: ALSA with rate control

## Included Cores (23 total)

`fceumm` (NES), `gambatte`/`nestopia` (GB/GBC), `mgba` (GBA), `snes9x2005` (SNES), `genesis_plus_gx`/`picodrive` (MD/32X), `pcsx_rearmed` (PS1, NEON dynarec), `fbneo`/`mame2003_plus` (arcade), `cap32` (Amstrad CPC), `fuse` (ZX Spectrum), `vice_x64` (C64), `theodore` (Thomson MO/TO), `mednafen_pce_fast`/`mednafen_supergrafx` (PC Engine), `mednafen_ngp` (Neo Geo Pocket), `mednafen_wswan` (WonderSwan), `stella` (Atari 2600), `prosystem` (Atari 7800), `handy` (Atari Lynx).

## Prerequisites

- Ubuntu 22.04+ (or WSL2) with ~15 GB free disk, 4–8 GB RAM
- Host packages installed by `setup` step: `gcc`, `g++`, `make`, `python3`, `libncurses-dev`, `flex`, `bison`, `device-tree-compiler`, `u-boot-tools`, `dosfstools`, `e2fsprogs`
- Original GameStick backup image required for `image` step
