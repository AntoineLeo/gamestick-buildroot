# GameStick Lite 4K — Build RetroArch via Buildroot

> Compilation automatisée d'un rootfs Linux embarqué contenant RetroArch et ~20 cores libretro pour le GameStick Lite 4K (modèle M8, Rockchip RK3032).

## Architecture cible

| Composant | Valeur |
|-----------|--------|
| SoC | Rockchip RK3032 |
| CPU | Dual-core ARM Cortex-A7 @ 1.0 GHz |
| GPU | Mali-400MP |
| RAM | 256 Mo DDR3 |
| ISA | ARMv7-A |
| FPU | VFPv4 |
| SIMD | NEON |
| ABI | hard-float (armhf) |
| Stockage | Carte micro-SD (EXT4) |

## Prérequis

- **OS** : Ubuntu 22.04+ (natif ou WSL2)
- **Espace disque** : ~15 Go
- **RAM hôte** : 4 Go minimum (8 Go recommandé)
- **Temps de build** : 1-3 heures (selon CPU)
- **Image backup** : dump de ta carte SD originale (`gamestick_backup.img`)

## Démarrage rapide

```bash
chmod +x build.sh

# 1. Installer les dépendances + télécharger Buildroot
./build.sh setup

# 2. Appliquer la configuration GameStick
./build.sh configure

# 3. (Optionnel) Ajuster la config dans le menu interactif
./build.sh menuconfig

# 4. Compiler tout
./build.sh build

# 5. Assembler l'image SD
./build.sh image
```

Ou tout d'un coup :

```bash
./build.sh all
```

## Stratégie d'assemblage

L'image SD du GameStick est découpée en 5 partitions :

```
┌──────────┬──────────┬──────────┬───────────────┬─────────────────┐
│  uboot   │  trust   │   boot   │    rootfs     │    userdata     │
│  1 Mo    │  2 Mo    │  9 Mo    │   ~88 Mo      │    le reste     │
│ (proprio)│ (ARM TF) │ (kernel) │ ← REMPLACÉ    │ (ROMs, saves)   │
└──────────┴──────────┴──────────┴───────────────┴─────────────────┘
```

**On ne touche pas** aux partitions `uboot`, `trust` et `boot` (kernel + DTB propriétaires Rockchip). Seul le **rootfs** est remplacé par notre build Buildroot. La partition `userdata` est conservée telle quelle (tes ROMs et saves restent).

## Cores inclus

### Consoles 8-bit
| Core | Système | Notes |
|------|---------|-------|
| fceumm | NES / Famicom | Précis et léger |
| gambatte | Game Boy / GBC | Référence GB |
| mgba | Game Boy Advance | Très bon sur ARM |
| nestopia | NES | Plus précis que fceumm |

### Consoles 16-bit
| Core | Système | Notes |
|------|---------|-------|
| snes9x2005 | SNES | Version allégée pour low-end |
| genesis_plus_gx | Mega Drive / SMS / GG | Polyvalent |
| picodrive | MD / 32X / Mega CD | Dynarec ARM |
| mednafen_pce_fast | PC Engine | Version rapide |
| mednafen_supergrafx | SuperGrafx | Niche mais fun |
| mednafen_ngp | Neo Geo Pocket | Léger |
| mednafen_wswan | WonderSwan | Léger |

### Arcade
| Core | Système | Notes |
|------|---------|-------|
| fbneo | FinalBurn Neo | Large catalogue arcade |
| mame2003_plus | MAME 2003+ | Bon compromis perf/compat |

### Ordinateurs
| Core | Système | Notes |
|------|---------|-------|
| cap32 | Amstrad CPC | Un test |
| fuse | ZX Spectrum | Sinclair |
| vice_x64 | Commodore 64 | Classique |
| theodore | Thomson TO8/TO7 | French touch |

### PS1
| Core | Système | Notes |
|------|---------|-------|
| pcsx_rearmed | PlayStation 1 | Dynarec ARM, limite en 256 Mo |

### Atari
| Core | Système | Notes |
|------|---------|-------|
| stella | Atari 2600 | Ultra léger |
| prosystem | Atari 7800 | Léger |
| handy | Atari Lynx | Portable |

## Ajouter un core supplémentaire

Après le build initial, tu peux compiler des cores additionnels avec la toolchain Buildroot :

```bash
# La toolchain est dans buildroot-XXXX/output/host/bin/
TC=buildroot-2025.02/output/host/bin/arm-buildroot-linux-gnueabihf

# Cloner et compiler
git clone https://github.com/libretro/libretro-mon-core.git
cd libretro-mon-core

make CC="${TC}-gcc" CXX="${TC}-g++" AR="${TC}-ar" \
     CFLAGS="-marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -O2" \
     platform=unix -j$(nproc)

# Vérifier le binaire
file *_libretro.so
readelf -A *_libretro.so | grep -E "CPU_arch|FP_arch|SIMD|VFP_args"

# Copier sur la SD (partition rootfs montée)
cp *_libretro.so /mnt/rootfs/usr/lib/libretro/
```

## Vérification post-compilation

Tout binaire ARM destiné au RK3032 doit afficher :

```
$ file retroarch
ELF 32-bit LSB executable, ARM, EABI5, ...

$ readelf -A retroarch
  Tag_CPU_name: "Cortex-A7"    (ou "7-A")
  Tag_CPU_arch: v7
  Tag_CPU_arch_profile: Application
  Tag_FP_arch: VFPv4
  Tag_Advanced_SIMD_arch: NEONv1
  Tag_ABI_VFP_args: VFP registers
```

## Structure du projet

```
gamestick-buildroot/
├── build.sh                    # Script principal
├── README.md                   # Ce fichier
├── configs/
│   └── gamestick_rk3032_defconfig  # Config Buildroot
├── overlay/                    # Fichiers injectés dans le rootfs
│   └── etc/
│       ├── init.d/
│       │   └── S99retroarch    # Script de démarrage
│       └── retroarch/
│           └── retroarch.cfg   # Config RetroArch optimisée
├── cores/                      # Cores compilés hors Buildroot
│   ├── build/
│   └── output/
├── output/                     # Image SD finale
│   └── gamestick_custom.img
└── buildroot-2025.02/          # Buildroot (créé par setup)
    └── package/
        ├── retroarch/          # Package custom
        ├── libretro-fceumm/
        ├── libretro-cap32/
        └── ...
```

## Dépannage

### Le build échoue sur un core
Certains cores ont des Makefiles non standards. Essaie :
```bash
# Forcer le target manuellement
make -f Makefile.libretro platform=unix CC=... CXX=...
```

### RetroArch ne démarre pas (écran noir)
- Vérifier le driver vidéo : `SDL_VIDEODRIVER=kmsdrm` ou essayer `fbdev`
- Vérifier que `/dev/dri/card0` existe
- Tester en console : `retroarch --verbose 2>&1 | head -50`

### Les manettes ne sont pas détectées
- Le GameStick utilise un dongle 2.4 GHz USB
- Vérifier avec `evtest` que les événements arrivent
- La config d'autodetect de RetroArch doit être adaptée

### Pas assez de RAM
- Désactiver le rewind (`rewind_enable = false`)
- Utiliser RGUI (pas XMB/Ozone)
- Éviter les cores lourds (PPSSPP, Dolphin, MAME récent)
- Réduire la taille des thumbnails ou les désactiver

## Références

- [Buildroot User Manual](https://buildroot.org/downloads/manual/manual.html)
- [libretro-super](https://github.com/libretro/libretro-super) — Outil officiel de build des cores
- [RetroArch compilation docs](https://docs.libretro.com/development/retroarch/compilation/ubuntu/)
- [Thread XDA SpectralElec 3.0](https://xdaforums.com/t/4680877/) — Firmware custom RK3032
- [GStickOS](https://lucamot.github.io/GStickOS/) — Autre firmware custom (Hi3798mv100)
- [Recalbox Buildroot](https://github.com/recalbox/recalbox-buildroot) — Référence pour les packages RetroArch/libretro
