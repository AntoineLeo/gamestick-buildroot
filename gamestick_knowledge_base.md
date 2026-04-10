# Game Stick Lite 4K — Base de connaissances

> Document de référence pour la manipulation, la modification et le développement de firmware custom pour le Game Stick Lite 4K (modèle M8, carte 066-V02).

---

## 1. Caractéristiques matérielles

### SoC — Rockchip RK3032

| Paramètre | Valeur |
|---|---|
| Architecture | ARMv7-A (32-bit) |
| CPU | Dual-core Cortex-A7 @ 1.0 GHz |
| GPU | Mali-400MP (intégré) |
| Extensions | VFPv4, NEON, Thumb-2, TrustZone |
| Gravure | 28 nm |

### Mémoire

| Paramètre | Valeur |
|---|---|
| Type | DDR3 SDRAM |
| Puces | 2 × Samsung K4B1G0846F (1 Gbit chacune) |
| Total | 256 Mo |

### Connectique

| Connecteur | Rôle |
|---|---|
| HDMI mâle (Type A) | Sortie vidéo/audio vers TV |
| USB-A femelle | Périphériques (manettes, clavier, clé USB, dongle Wi-Fi) |
| Micro-USB | Alimentation 5V |
| Slot micro-SD | Stockage système + jeux (boot possible) |

### Carte PCB

| Paramètre | Valeur |
|---|---|
| Référence PCB | 066-V02 |
| Révision | A-2 |
| Date PCB recto | 2021-06-15 |
| Date PCB verso | GMS 2022/11/16 |
| Modèle communautaire | M8 |
| Inscription chinoise | T卡启动 (= démarrage par carte TF/micro-SD) |

---

## 2. Architecture logicielle

### Système d'exploitation

Le Game Stick tourne sous **Linux embarqué**, basé sur **BusyBox**, avec un frontend graphique custom basé sur **MiniGUI**.

### Chaîne de démarrage

```
Power ON
  → U-Boot (partition 1 : uboot)
    → ARM Trusted Firmware (partition 2 : trust)
      → Noyau Linux + DTB (partition 3 : boot)
        → rootfs squashfs (partition 4 : rootfs)
          → /etc/init.d/rcS → S50ui
            → /usr/bin/game (frontend MiniGUI)
              → start_game.sh → RetroArch + core libretro
```

### Frontend MiniGUI

Le binaire `/usr/bin/game` est le frontend graphique. Il :

1. Lit la base de données **`/sdcard/game/games.db`** (SQLite 3) pour lister les systèmes et jeux
2. Appelle **`/usr/local/share/minigui/start_game.sh`** avec 3 arguments :
   - `$1` : numéro du système (0-26, voir mapping ci-dessous)
   - `$2` : chemin du fichier de configuration RetroArch
   - `$3` : chemin de la ROM
3. Le script lance RetroArch avec le core correspondant

### Mapping des systèmes (start_game.sh)

| ID | Core | Système |
|---|---|---|
| 0 | fbalpha2012_libretro.so | Arcade (FBA 2012) |
| 1 | nestopia_libretro.so | Nintendo NES / Famicom |
| 2 | daphne_libretro.so | Daphne (Laserdisc) |
| 3 | fbalpha2012_libretro1.so | Arcade (FBA variante) |
| 4 | mame2003_libretro.so | Arcade (MAME 2003) |
| 5 | genesisplusgx_libretro.so | Sega Mega Drive |
| 6 | snes9x_libretro.so | Super Nintendo |
| 7 | mgba_libretro.so | Game Boy / GBA / GBC |
| 8 | mupen64plus_libretro.so | Nintendo 64 |
| 9 | pcsx_rearmed_libretro.so | PlayStation 1 |
| 10 | mednafen_pce_fast_libretro.so | PC Engine |
| 11 | mednafen_wswan_libretro.so | WonderSwan |
| 12 | desmume2015_libretro.so | Nintendo DS |
| 13 | genesis_plus_gx_libretro.so | Sega Game Gear / SMS |
| 14 | fbalpha_libretro.so | Arcade (FBA) |
| 15 | stella_libretro.so | Atari 2600 |
| 16 | atari800_libretro.so | Atari 5200 |
| 17 | prosystem_libretro.so | Atari 7800 |
| 18 | mame2016_libretro.so | Arcade (MAME 2016) |
| 19-26 | *_other.so | Variantes secondaires |
| **27** | **cap32_libretro.so** | **Amstrad CPC (ajouté)** |

---

## 3. Structure de la carte SD

### Table de partitions

La carte SD utilise un partitionnement **propriétaire Rockchip** (pas GPT/MBR standard).

| Partition | Offset (secteurs) | Taille | Filesystem | Contenu |
|---|---|---|---|---|
| uboot | variable | ~1 Mo | raw | Bootloader Rockchip |
| trust | variable | ~2 Mo | raw | ARM Trusted Firmware |
| boot | variable | ~9 Mo | raw | Noyau Linux + DTB + config manettes |
| rootfs | 32768 | ~65 Mo | **squashfs** (lecture seule, compressé gzip) | Système (BusyBox, RetroArch, scripts, configs) |
| userdata | après rootfs | reste de la carte | **vfat (FAT32)** | Cores, ROMs, configs, base de données jeux |

> **Important** : La partition boot contient le fichier `boot.pmf` qui configure les manettes. Cette partition doit être sauvegardée avant toute modification.

### Arborescence du rootfs (squashfs)

```
/
├── etc/
│   ├── init.d/
│   │   ├── rcS              ← script de boot principal
│   │   ├── S10udev
│   │   ├── S20urandom
│   │   ├── S21mountall.sh
│   │   ├── S40network
│   │   ├── S49usbdevice
│   │   ├── S50ui            ← lance le frontend (MiniGUI ou RetroArch)
│   │   ├── S50dropbear      ← serveur SSH
│   │   └── testui
│   └── retroarch.cfg        ← config RetroArch par défaut
├── usr/
│   ├── bin/
│   │   ├── retroarch        ← binaire RetroArch
│   │   ├── game             ← frontend MiniGUI
│   │   └── drm-hotplug.sh
│   └── local/share/minigui/
│       ├── start_game.sh    ← script de lancement des jeux
│       └── hdmicfg/         ← config MiniGUI
└── lib/
    └── ld-linux-armhf.so.3  ← dynamic linker ARM hard-float
```

### Arborescence du userdata (FAT32, monté en `/sdcard`)

```
/sdcard/
├── boot_retroarch          ← fichier flag : si présent, boot sur RetroArch natif
├── retroarch.cfg           ← config RetroArch (mode natif)
├── parameter               ← fichier binaire de paramètres
├── patlanguage             ← langue du système
├── retro_lib/              ← cores libretro (.so)
│   ├── cap32_libretro.so   ← Amstrad CPC (ajouté)
│   ├── nestopia_libretro.so
│   ├── snes9x_libretro.so
│   ├── pcsx_rearmed_libretro.so
│   └── ...
├── retroarch/              ← données RetroArch
│   ├── assets/
│   ├── autoconfig/
│   ├── cheats/
│   ├── config/
│   ├── cores/              ← fichiers .info des cores
│   ├── database/           ← bases pour le scanner de contenu
│   ├── playlists/          ← playlists auto-générées
│   └── system/             ← BIOS (scph1001.bin, etc.)
├── game/                   ← ROMs organisées par système
│   ├── fc/                 ← NES/Famicom
│   ├── sfc/                ← Super Nintendo
│   ├── md/                 ← Mega Drive
│   ├── gb/                 ← Game Boy
│   ├── gba/                ← Game Boy Advance
│   ├── gbc/                ← Game Boy Color
│   ├── ps1/                ← PlayStation 1
│   ├── atari/              ← Atari
│   ├── cps/                ← Arcade CPS (contient aussi des cores)
│   ├── cpc/                ← Amstrad CPC (ajouté)
│   ├── games.db            ← base SQLite des jeux (frontend MiniGUI)
│   └── database.sqlite3    ← base secondaire
├── minigui/res/            ← ressources graphiques du frontend
└── picture/                ← vignettes / screenshots
```

---

## 4. Compatibilité binaire ARM

### Règle fondamentale

Contrairement à x86, un binaire ARM n'est **pas universellement compatible**. Pour fonctionner sur le RK3032, un binaire doit correspondre sur **tous** ces critères :

| Critère | Valeur requise |
|---|---|
| Architecture | ARMv7-A (ELF 32-bit) |
| Profil | Application |
| ABI flottant | hard-float (VFP registers) |
| FPU | VFPv3-D16 minimum, VFPv4 optimal |
| SIMD | NEON supporté (optionnel mais recommandé) |
| Linker | /lib/ld-linux-armhf.so.3 |
| libc | Compatible avec la version du rootfs |


### Vérifier la compatibilité d'un binaire

```bash
file mon_core_libretro.so
# Attendu : ELF 32-bit LSB shared object, ARM, EABI5

readelf -A mon_core_libretro.so
# Vérifier : v7, Application, VFP registers
```

---

## 5. Cross-compilation

### Installation de la toolchain

```bash
# Sur Ubuntu/Debian/WSL
sudo apt install gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf
```

### Compiler un core libretro (exemple : cap32 — Amstrad CPC)

```bash
git clone https://github.com/libretro/libretro-cap32
cd libretro-cap32

make -f Makefile clean

make -f Makefile platform=unix \
  CC=arm-linux-gnueabihf-gcc \
  CXX=arm-linux-gnueabihf-g++ \
  CFLAGS="-marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard" \
  CXXFLAGS="-marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"
```

### Vérification post-compilation

```bash
file cap32_libretro.so
# Doit afficher : ELF 32-bit LSB shared object, ARM, EABI5

readelf -A cap32_libretro.so | grep -E "CPU_arch|FP_arch|SIMD|VFP_args"
# Doit afficher : v7, VFPv4, NEONv1, VFP registers
```

### Flags de compilation recommandés

| Flag | Rôle |
|---|---|
| `-marm` | Forcer le mode ARM (pas Thumb) |
| `-mcpu=cortex-a7` | Cibler le CPU exact |
| `-mfpu=neon-vfpv4` | Activer VFPv4 + NEON |
| `-mfloat-abi=hard` | Hard-float ABI |

> **Piège** : Si le flag `platform=unix-armv7-neonhf` n'est pas reconnu par le Makefile d'un core, il faut forcer `CC`, `CXX`, `CFLAGS` et `CXXFLAGS` manuellement comme ci-dessus, sinon c'est le compilateur natif x86_64 qui sera utilisé.

---

## 6. Manipulation de l'image SD

### Prérequis

```bash
sudo apt install squashfs-tools sqlite3
```

### Créer un backup de la carte SD

#### Sous Linux/WSL

```bash
# Identifier le device
lsblk
# ou
sudo fdisk -l

# Dump complet
sudo dd if=/dev/sdb of=gamestick_backup_orig.img bs=4M conv=fdatasync,notrunc iflag=fullblock status=progress
```

### Monter l'image pour modification

```bash
# Attacher l'image avec détection auto des partitions
sudo losetup -fP gamestick_backup.img

# Vérifier le loop device assigné
losetup -l

# Voir les partitions
sudo fdisk -l /dev/loop0

# Monter rootfs (squashfs, lecture seule)
sudo mkdir -p /mnt/rootfs /mnt/userdata
sudo mount /dev/loop0p4 /mnt/rootfs
sudo mount /dev/loop0p5 /mnt/userdata
```

### Modifier le rootfs (squashfs)

Le squashfs est en lecture seule par design. Il faut le décompresser, modifier, et recompresser :

```bash
# Extraire
sudo unsquashfs -d /home/user/rootfs_extracted /dev/loop0p4

# Modifier les fichiers souhaités
sudo nano /home/user/rootfs_extracted/etc/init.d/S50ui

# Recompresser
sudo mksquashfs /home/user/rootfs_extracted /home/user/rootfs_new.img \
  -comp gzip -noappend

# Vérifier que la nouvelle image rentre dans la partition
sudo fdisk -l /dev/loop0 | grep loop0p4
ls -la /home/user/rootfs_new.img

# Écrire la nouvelle image
sudo umount /mnt/rootfs
sudo dd if=/home/user/rootfs_new.img of=/dev/loop0p4 bs=4M status=progress conv=notrunc

# Vérifier
$ sudo mount /dev/loop0p4 /mnt/rootfs
$ cat /mnt/rootfs/etc/init.d/S50ui
```

### Modifier le userdata (FAT32)

La partition userdata est en FAT32, modifiable directement :

```bash
# Depuis Linux/WSL (déjà monté)
$ sudo cp core.so /mnt/userdata/retro_lib/
$ sudo mkdir -p /mnt/userdata/game/nouveau_systeme/

# Depuis Windows : utiliser DiskGenius ou directement
# l'Explorateur si la partition est montée
```

### Démonter et finaliser

```bash
$ sudo umount /mnt/rootfs /mnt/userdata
$ sudo losetup -d /dev/loop0
```



### Réduire la taille de l'image disque (optionnel)
En cas de besoin il est possible de réduire la taille de l'image si on veut la copier sur une carte SD de taille légèrement moindre.

1. Réduire la taille de la dernière partition avec gparted
Gparted permet de modifier les partitions graphiquement, sans perte de donnée ni corruption de la table de partition

```bash
# Depuis Linux/WSL (déjà monté)
sudo gparted /dev/loop0
```

2. calculer la taille de à tronquer
```bash
$ sudo fdisk /dev/loop0

Welcome to fdisk (util-linux 2.38.1).
Changes will remain in memory only, until you decide to write them.
Be careful before using the write command.


Command (m for help): p
Disk /dev/loop0: 29,3 GiB, 31457280000 bytes, 61440000 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: gpt
Disk identifier: 23000000-0000-4C4A-8000-699000005ABB

Device        Start      End  Sectors Size Type
/dev/loop0p1   8192    10239     2048   1M unknown
/dev/loop0p2  10240    14335     4096   2M unknown
/dev/loop0p3  14336    32767    18432   9M unknown
/dev/loop0p4  32768   165887   133120  65M unknown
/dev/loop0p5 165888 61069278 60903391  29G unknown

Command (m for help): q
```

La valeur importantes est **61069278** qui est le numéro du dernier secteur de la partition. Pour calculer la taille cible il faut appliquer la formule suivante:
```math
taille=(numéro secteur+1+33)*512=(61069278+1+33)=31267487744
```

* 1 pour compter la taille du dernier secteur
* 33 correspond à la taille nécessaire pour enregistrer la table gpt de backup

```bash
sudo losetup -d /dev/loop0
truncate -s 31267487744 gamestick_backup_truncated.img
```

3. Réparer la table de partition
```bash
$ sudo losetup -fP  gamestick_backup_truncated.img
$ sudo gdisk /dev/loop0
GPT fdisk (gdisk) version 1.0.9

Warning! Disk size is smaller than the main header indicates! Loading
secondary header from the last sector of the disk! You should use 'v' to
verify disk integrity, and perhaps options on the experts' menu to repair
the disk.
Caution: invalid backup GPT header, but valid main header; regenerating
backup header from main header.

Warning! One or more CRCs don't match. You should repair the disk!
Main header: OK
Backup header: ERROR
Main partition table: OK
Backup partition table: ERROR

Partition table scan:
  MBR: protective
  BSD: not present
  APM: not present
  GPT: damaged

****************************************************************************
Caution: Found protective or hybrid MBR and corrupt GPT. Using GPT, but disk
verification and recovery are STRONGLY recommended.
****************************************************************************

Command (? for help): p
Disk /dev/loop0: 61069312 sectors, 29.1 GiB
Sector size (logical/physical): 512/512 bytes
Disk identifier (GUID): 23000000-0000-4C4A-8000-699000005ABB
Partition table holds up to 128 entries
Main partition table begins at sector 2 and ends at sector 33
First usable sector is 34, last usable sector is 61439966
Partitions will be aligned on 2048-sector boundaries
Total free space is 1056701 sectors (516.0 MiB)

Number  Start (sector)    End (sector)  Size       Code  Name
   1            8192           10239   1024.0 KiB  FFFF  uboot
   2           10240           14335   2.0 MiB     FFFF  trust
   3           14336           32767   9.0 MiB     FFFF  boot
   4           32768          165887   65.0 MiB    FFFF  rootfs
   5          165888        60391423   28.7 GiB    FFFF  userdata

Command (? for help): w
Caution! Secondary header was placed beyond the disk's limits! Moving the
header, but other problems may occur!

Final checks complete. About to write GPT data. THIS WILL OVERWRITE EXISTING
PARTITIONS!!

Do you want to proceed? (Y/N): y
OK; writing new GUID partition table (GPT) to /dev/loop0.
The operation has completed successfully.
```


### Flasher l'image modifiée sur une nouvelle carte SD

#### Sous Linux/WSL

```bash
sudo dd if=gamestick_backup.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Vérifier si la table de partition est bien recréée
```bash
$ lsblk
NAME      MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda         8:0    0 465,8G  0 disk
└─sda1      8:1    0 465,8G  0 part /
sdb         8:16   1    29G  0 disk
├─sdb1      8:17   1     1M  0 part
├─sdb2      8:18   1     2M  0 part
├─sdb3      8:19   1     9M  0 part
├─sdb4      8:20   1    65M  0 part /media/antoine/sdb4-usb-Generic-_Multi-C
└─sdb5      8:21   1  28,7G  0 part /media/antoine/sdb5-usb-Generic-_Multi-C
```

Il faut voir cinq partitions, si ce n'est pas le cas, tenter de réparer la table de partition sur la carte SD (cf. 3. Réparer la table de partition)

---

## 7. Modification du boot (dual-boot MiniGUI / RetroArch)

### Script S50ui modifié

Le script `/etc/init.d/S50ui` a été modifié pour un boot conditionnel :

```bash
case "$1" in
  start)
    printf "Starting ui: "
    export XDG_CONFIG_HOME=/sdcard/

    if [ -f /sdcard/boot_retroarch ]; then
        # Mode RetroArch natif
        /usr/bin/retroarch -c /sdcard/retroarch.cfg &
    else
        # Mode MiniGUI original
        export MG_CFG_PATH=/usr/local/share/minigui/hdmicfg
        /usr/bin/game &
    fi
    ;;
  stop)
    killall -9 game &
    killall -9 retroarch &
    printf "ui stop finished"
    ;;
  *)
    echo "Usage: $0 {start|stop}"
    exit 1
    ;;
esac
```

### Basculer entre les modes

- **Mode RetroArch** : créer le fichier `/sdcard/boot_retroarch` (vide, juste son existence compte)
- **Mode MiniGUI (original)** : supprimer le fichier `/sdcard/boot_retroarch`

> Le fichier étant sur la partition FAT32, il est modifiable depuis Windows sans outils spéciaux.

### Configuration RetroArch (mode natif)

Fichier `/sdcard/retroarch.cfg` — lignes essentielles à ajouter :

```ini
libretro_directory = "/sdcard/retro_lib"
rgui_browser_directory = "/sdcard/game"
playlist_directory = "/sdcard/retroarch/playlists"
content_database_path = "/sdcard/retroarch/database"
libretro_info_path = "/sdcard/retroarch/cores"
system_directory = "/sdcard/retroarch/system"
menu_driver = "rgui"
```

---

## 9. Outils recommandés

### Windows

| Outil | Usage |
|---|---|
| **DiskGenius** | Explorer les partitions Linux/Rockchip, copier des fichiers depuis/vers EXT4 |
| **Win32 Disk Imager** | Dump/flash d'images SD (nécessite lettre de lecteur) |
| **HDD Raw Copy Tool** | Dump/flash sans lettre de lecteur |
| **balenaEtcher** | Flash d'images (détection auto des disques physiques) |
| **7-Zip** | Décompression des images firmware (.7z) |

### Linux / WSL

| Outil | Usage |
|---|---|
| `sudo losetup -fP <filename>` | Monter une image avec détection auto des partitions |
| `losetup -l` | Lister les images *"montés"* |
| `sudo losetup -d /dev/loop0` | Démonter une image |
| `sudo fdisk -l /dev/loop0` | Lire la table de partitions |
| `sudo dd if=/dev/sdb of=gamestick_backup_orig.img bs=4M conv=fdatasync,notrunc iflag=fullblock status=progress` | Dump / flash d'images brutes |
| `dd` | Dump / flash d'images brutes |
| `squashfs-tools` | Décompresser/recompresser le rootfs |
| `sqlite3` | Explorer/modifier la base de données des jeux |
| `file` | Identifier le type et l'architecture d'un binaire |
| `readelf -A` | Vérifier les tags ARM d'un binaire (archi, FPU, NEON) |
| `arm-linux-gnueabihf-gcc` | Cross-compilateur ARM hard-float |

---

## 10. Communauté et ressources

| Ressource | URL |
|---|---|
| Thread XDA SpectralElec 3.0 | https://xdaforums.com/t/4680877/ |
| Forum russe stick-ow.pro | https://stick-ow.pro/forum (mot de passe : stick-ow.pro) |
| Telegram — Gamestick Help | https://t.me/+X0KTnClpuJVlZWJh |
| Telegram — Backups consoles chinoises | https://t.me/+9GSYr50aaOdiMGVh |
| Reddit r/SBCGaming | https://www.reddit.com/r/SBCGaming |
| GStickOS (firmware alternatif) | https://lucamot.github.io/GStickOS/ |
| Bootloader Rockchip RK3032 | Collection XDA (RK3032Bootloader_V2.54.bin) |
| Cores libretro (info files) | https://github.com/libretro/libretro-core-info |
| Backups images sur Internet Archive | Rechercher "gamestick RK3032" sur archive.org |

---

## 11. Firmwares alternatifs connus

| Firmware | Base | Notes |
|---|---|---|
| **SpectralElec 3.0** | EmuELEC + RetroArch | Le plus populaire pour M8/RK3032. Compatible V4, V5, V7, V20, M15 |
| **OpenWorld** | Custom | Disponible sur stick-ow.pro pour RK3032 |
| **GStickOS** | BusyBox + RetroArch | ~50 cores, SSH, Wi-Fi. Attention : conçu pour Hi3798mv100, pas RK3032 |
| **SEGAM vX.X** | Custom MiniGUI | Firmware d'usine, différentes versions (v3.0 à v9.0) |

---

*Document généré le 4 avril 2026 — Session de reverse-engineering et modification du Game Stick Lite 4K.*
