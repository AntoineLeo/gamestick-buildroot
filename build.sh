#!/bin/bash
# =============================================================================
# GameStick Lite 4K (M8 / RK3032) — Build RetroArch via Buildroot
# =============================================================================
#
# Ce script automatise la compilation complète d'un rootfs Linux embarqué
# contenant RetroArch et les cores libretro, ciblant le SoC Rockchip RK3032
# (Cortex-A7, ARMv7-A, VFPv4, NEON, 256 Mo RAM).
#
# Prérequis :
#   - Ubuntu 22.04+ ou WSL2
#   - ~15 Go d'espace disque
#   - Connexion internet
#
# Usage :
#   chmod +x build.sh
#   ./build.sh setup      # Installe les dépendances + clone Buildroot
#   ./build.sh configure   # Applique la defconfig GameStick
#   ./build.sh build       # Compile tout (1-3h selon la machine)
#   ./build.sh cores       # Compile les cores libretro supplémentaires
#   ./build.sh image       # Assemble l'image SD finale
#   ./build.sh all         # Fait tout d'un coup
#
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------

BUILDROOT_VERSION="2025.02"  # Version LTS récente
BUILDROOT_URL="https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.xz"
WORKDIR="$(cd "$(dirname "$0")" && pwd)"
BUILDROOT_DIR="${WORKDIR}/buildroot-${BUILDROOT_VERSION}"
OUTPUT_DIR="${WORKDIR}/output"
CORES_DIR="${WORKDIR}/cores"
OVERLAY_DIR="${WORKDIR}/overlay"
DEFCONFIG="${WORKDIR}/configs/gamestick_rk3032_defconfig"
GAMESTICK_BACKUP_IMG="${WORKDIR}/gamestick_custom.img"  # Chemin vers l'image backup de ta SD originale

# Cores à compiler (adaptés aux 256 Mo de RAM du RK3032)
# Légers = OK, Lourds = à éviter (PPSSPP, Dolphin, etc.)
LIBRETRO_CORES=(
    # --- Consoles 8-bit ---
    "fceumm"              # NES/Famicom (précis, léger)
    "gambatte"            # Game Boy / Game Boy Color
    "mgba"                # Game Boy Advance
    "snes9x2005"          # SNES (version allégée pour low-end)
    "genesis_plus_gx"     # Mega Drive / Master System / Game Gear
    "nestopia"            # NES (alternatif, plus précis)

    # --- Consoles 16-bit ---
    "picodrive"           # Mega Drive / 32X / Mega CD
    "mednafen_pce_fast"   # PC Engine / TurboGrafx-16
    "mednafen_supergrafx" # SuperGrafx
    "mednafen_ngp"        # Neo Geo Pocket / Color
    "mednafen_wswan"      # WonderSwan / Color

    # --- Arcade ---
    "fbneo"               # FinalBurn Neo (arcade)
    "mame2003_plus"       # MAME 2003+ (léger, bon compromis)

    # --- Ordinateurs ---
    "cap32"               # Amstrad CPC !!!
    "fuse"                # ZX Spectrum
    "vice_x64"            # Commodore 64
    "theodore"            # Thomson TO8/TO7

    # --- PS1 (limite avec 256 Mo) ---
    "pcsx_rearmed"        # PS1 (optimisé ARM, dynarec)

    # --- Atari ---
    "stella"              # Atari 2600
    "prosystem"           # Atari 7800
    "handy"               # Atari Lynx
)

# --- Couleurs ----------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[GameStick]${NC} $*"; }
warn() { echo -e "${YELLOW}[ATTENTION]${NC} $*"; }
err()  { echo -e "${RED}[ERREUR]${NC} $*" >&2; }

# =============================================================================
# ÉTAPE 1 : Installation des dépendances
# =============================================================================

cmd_setup() {
    log "Installation des dépendances système..."

    sudo apt-get update
    sudo apt-get install -y \
        build-essential \
        gcc g++ \
        git \
        wget curl \
        unzip \
        bc \
        cpio \
        rsync \
        python3 python3-pip \
        libncurses-dev \
        flex bison \
        texinfo \
        libssl-dev \
        file \
        patch \
        gzip bzip2 xz-utils \
        perl \
        cmake \
        device-tree-compiler \
        u-boot-tools \
        dosfstools \
        mtools \
        parted \
        e2fsprogs

    # Télécharger Buildroot
    if [ ! -d "${BUILDROOT_DIR}" ]; then
        log "Téléchargement de Buildroot ${BUILDROOT_VERSION}..."
        cd "${WORKDIR}"
        wget -q --show-progress "${BUILDROOT_URL}"
        tar xf "buildroot-${BUILDROOT_VERSION}.tar.xz"
        rm -f "buildroot-${BUILDROOT_VERSION}.tar.xz"
    else
        log "Buildroot ${BUILDROOT_VERSION} déjà présent."
    fi

    # Créer la structure du projet
    mkdir -p "${WORKDIR}/configs"
    mkdir -p "${OVERLAY_DIR}/etc/init.d"
    mkdir -p "${OVERLAY_DIR}/usr/share/retroarch"
    mkdir -p "${OVERLAY_DIR}/usr/lib/libretro"
    mkdir -p "${CORES_DIR}"

    # Copier les packages custom dans Buildroot
    setup_retroarch_package
    setup_libretro_cores_package

    log "Setup terminé !"
    log "Prochaine étape : ./build.sh configure"
}

# =============================================================================
# ÉTAPE 2 : Packages Buildroot custom pour RetroArch
# =============================================================================

setup_retroarch_package() {
    local PKG_DIR="${BUILDROOT_DIR}/package/retroarch"
    mkdir -p "${PKG_DIR}"

    log "Création du package Buildroot pour RetroArch..."

    # Config.in
    cat > "${PKG_DIR}/Config.in" << 'CONFIGIN'
config BR2_PACKAGE_RETROARCH
	bool "retroarch"
	depends on BR2_TOOLCHAIN_HAS_THREADS
	select BR2_PACKAGE_ZLIB
	help
	  RetroArch is the official reference frontend for the
	  libretro API. It provides a unified interface for running
	  libretro cores (emulators, game engines, etc.).

	  https://www.retroarch.com

if BR2_PACKAGE_RETROARCH

config BR2_PACKAGE_RETROARCH_SDL2
	bool "SDL2 video/audio driver"
	default y
	select BR2_PACKAGE_SDL2

config BR2_PACKAGE_RETROARCH_ALSA
	bool "ALSA audio driver"
	default y
	select BR2_PACKAGE_ALSA_LIB

config BR2_PACKAGE_RETROARCH_UDEV
	bool "udev input driver"
	default y
	select BR2_PACKAGE_EUDEV

config BR2_PACKAGE_RETROARCH_FREETYPE
	bool "FreeType font rendering"
	default y
	select BR2_PACKAGE_FREETYPE

config BR2_PACKAGE_RETROARCH_NETWORKING
	bool "Networking support"
	default y

endif
CONFIGIN

    # retroarch.mk (Makefile Buildroot)
    cat > "${PKG_DIR}/retroarch.mk" << 'RETROMK'
################################################################################
#
# retroarch
#
################################################################################

RETROARCH_VERSION = v1.21.0
RETROARCH_SITE = https://github.com/libretro/RetroArch.git
RETROARCH_SITE_METHOD = git
RETROARCH_GIT_SUBMODULES = YES
RETROARCH_LICENSE = GPL-3.0+
RETROARCH_LICENSE_FILES = COPYING

RETROARCH_DEPENDENCIES = host-pkgconf zlib

# --- Options de configuration ---

RETROARCH_CONF_OPTS = \
	--disable-oss \
	--disable-jack \
	--disable-pulse \
	--disable-x11 \
	--disable-wayland \
	--disable-vulkan \
	--disable-opengl \
	--disable-caca \
	--disable-qt \
	--disable-discord \
	--enable-zlib \
	--enable-threads \
	--enable-rgui \
	--enable-materialui

# Cortex-A7 spécifique : activer hard-float et NEON
ifeq ($(BR2_cortex_a7),y)
RETROARCH_CONF_OPTS += --enable-neon --enable-floathard
endif

# SDL2
ifeq ($(BR2_PACKAGE_RETROARCH_SDL2),y)
RETROARCH_CONF_OPTS += --enable-sdl2
RETROARCH_DEPENDENCIES += sdl2
else
RETROARCH_CONF_OPTS += --disable-sdl2
endif

# ALSA
ifeq ($(BR2_PACKAGE_RETROARCH_ALSA),y)
RETROARCH_CONF_OPTS += --enable-alsa
RETROARCH_DEPENDENCIES += alsa-lib
else
RETROARCH_CONF_OPTS += --disable-alsa
endif

# udev (manettes)
ifeq ($(BR2_PACKAGE_RETROARCH_UDEV),y)
RETROARCH_CONF_OPTS += --enable-udev
RETROARCH_DEPENDENCIES += eudev
else
RETROARCH_CONF_OPTS += --disable-udev
endif

# FreeType
ifeq ($(BR2_PACKAGE_RETROARCH_FREETYPE),y)
RETROARCH_CONF_OPTS += --enable-freetype
RETROARCH_DEPENDENCIES += freetype
else
RETROARCH_CONF_OPTS += --disable-freetype
endif

# Networking
ifeq ($(BR2_PACKAGE_RETROARCH_NETWORKING),y)
RETROARCH_CONF_OPTS += --enable-networking
else
RETROARCH_CONF_OPTS += --disable-networking
endif

# --- Configuration ---

define RETROARCH_CONFIGURE_CMDS
	cd $(@D) && \
	$(TARGET_CONFIGURE_OPTS) \
	CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include" \
	PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" \
	PKG_CONFIG_PATH="$(STAGING_DIR)/usr/lib/pkgconfig:$(STAGING_DIR)/usr/share/pkgconfig" \
	PKG_CONFIG_SYSROOT_DIR="$(STAGING_DIR)" \
	./configure \
		--host=$(GNU_TARGET_NAME) \
		--prefix=/usr \
		$(RETROARCH_CONF_OPTS)
endef

# --- Compilation ---

define RETROARCH_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) \
		-C $(@D)
endef

# --- Installation ---

define RETROARCH_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/retroarch $(TARGET_DIR)/usr/bin/retroarch
	mkdir -p $(TARGET_DIR)/etc/retroarch
	$(INSTALL) -D -m 0644 $(@D)/retroarch.cfg $(TARGET_DIR)/etc/retroarch/retroarch.cfg
endef

define RETROARCH_FIX_CONFIG
	$(SED) 's%-I/usr/include%-I$(STAGING_DIR)/usr/include%g' $(@D)/config.mk
endef
RETROARCH_POST_CONFIGURE_HOOKS += RETROARCH_FIX_CONFIG

$(eval $(generic-package))
RETROMK

    # Ajouter le package au menu Buildroot
    if ! grep -q "retroarch" "${BUILDROOT_DIR}/package/Config.in"; then
        # Ajouter dans la section "Games" ou à la fin
        #sed -i '/^endmenu # "Games"/i\	source "package/retroarch/Config.in"' \
        sed -i '/^menu "Games"/a \  source "package/retroarch/Config.in"' \
            "${BUILDROOT_DIR}/package/Config.in" 2>/dev/null || \
        echo 'source "package/retroarch/Config.in"' >> "${BUILDROOT_DIR}/package/Config.in"
    fi

    log "Package RetroArch créé dans ${PKG_DIR}"
}

setup_libretro_cores_package() {
    log "Création des packages Buildroot pour les cores libretro..."

    # Template générique pour un core libretro
    # Chaque core suit le même pattern : clone git + make + install .so

    for core in "${LIBRETRO_CORES[@]}"; do
        local PKG_NAME="libretro-${core}"
        local PKG_DIR="${BUILDROOT_DIR}/package/${PKG_NAME}"
        local PKG_VAR=$(echo "${PKG_NAME}" | tr '-' '_' | tr '[:lower:]' '[:upper:]')

        mkdir -p "${PKG_DIR}"

        # Déterminer l'URL du repo et le nom du .so
        local REPO_URL=""
        local SO_NAME="${core}_libretro.so"
        local MAKEFILE_TARGET=""
        local EXTRA_MAKE_OPTS=""
        local BUILD_SUBDIR=""

        case "${core}" in
            fceumm)         REPO_URL="https://github.com/libretro/libretro-fceumm.git" ;;
            gambatte)       REPO_URL="https://github.com/libretro/gambatte-libretro.git" ;;
            mgba)           REPO_URL="https://github.com/libretro/mgba.git"
                            MAKEFILE_TARGET="-f Makefile.libretro" ;;
            snes9x2005)     REPO_URL="https://github.com/libretro/snes9x2005.git"
                            SO_NAME="snes9x_libretro.so"
                            BUILD_SUBDIR="libretro" ;;
            genesis_plus_gx) REPO_URL="https://github.com/libretro/Genesis-Plus-GX.git"
                            SO_NAME="genesis_plus_gx_libretro.so"
                            MAKEFILE_TARGET="-f Makefile.libretro" ;;
            nestopia)       REPO_URL="https://github.com/libretro/nestopia.git"
                            SO_NAME="nestopia_libretro.so"
                            BUILD_SUBDIR="libretro"
                            MAKEFILE_TARGET="-f Makefile" ;;
            picodrive)      REPO_URL="https://github.com/libretro/picodrive.git"
                            MAKEFILE_TARGET="-f Makefile.libretro" ;;
            mednafen_pce_fast) REPO_URL="https://github.com/libretro/beetle-pce-fast-libretro.git"
                            SO_NAME="mednafen_pce_fast_libretro.so" ;;
            mednafen_supergrafx) REPO_URL="https://github.com/libretro/beetle-supergrafx-libretro.git"
                            SO_NAME="mednafen_supergrafx_libretro.so" ;;
            mednafen_ngp)   REPO_URL="https://github.com/libretro/beetle-ngp-libretro.git"
                            SO_NAME="mednafen_ngp_libretro.so" ;;
            mednafen_wswan) REPO_URL="https://github.com/libretro/beetle-wswan-libretro.git"
                            SO_NAME="mednafen_wswan_libretro.so" ;;
            fbneo)          REPO_URL="https://github.com/libretro/FBNeo.git"
                            SO_NAME="fbneo_libretro.so"
                            MAKEFILE_TARGET=""
                            BUILD_SUBDIR="src/burner/libretro"
                            EXTRA_MAKE_OPTS="profile=performance" ;;
            mame2003_plus)  REPO_URL="https://github.com/libretro/mame2003-plus-libretro.git"
                            SO_NAME="mame2003_plus_libretro.so" ;;
            cap32)          REPO_URL="https://github.com/libretro/libretro-cap32.git"
                            SO_NAME="cap32_libretro.so"
                            EXTRA_MAKE_OPTS="LDLIBS=-lm" ;;
            fuse)           REPO_URL="https://github.com/libretro/fuse-libretro.git"
                            SO_NAME="fuse_libretro.so" ;;
            vice_x64)       REPO_URL="https://github.com/libretro/vice-libretro.git"
                            SO_NAME="vice_x64_libretro.so"
                            EXTRA_MAKE_OPTS="EMUTYPE=x64" ;;
            theodore)       REPO_URL="https://github.com/Zlika/theodore.git"
                            SO_NAME="theodore_libretro.so" ;;
            pcsx_rearmed)   REPO_URL="https://github.com/libretro/pcsx_rearmed.git"
                            SO_NAME="pcsx_rearmed_libretro.so"
                            MAKEFILE_TARGET="-f Makefile.libretro"
                            EXTRA_MAKE_OPTS="DYNAREC=ari64 HAVE_NEON=1" ;;
            stella)         REPO_URL="https://github.com/libretro/stella-libretro.git"
                            SO_NAME="stella_libretro.so" ;;
            prosystem)      REPO_URL="https://github.com/libretro/prosystem-libretro.git"
                            SO_NAME="prosystem_libretro.so" ;;
            handy)          REPO_URL="https://github.com/libretro/libretro-handy.git"
                            SO_NAME="handy_libretro.so" ;;
            *)
                warn "Core inconnu : ${core}, ignoré."
                continue
                ;;
        esac

        # Config.in
        cat > "${PKG_DIR}/Config.in" << EOF
    config BR2_PACKAGE_${PKG_VAR}
	bool "libretro-${core}"
	depends on BR2_PACKAGE_RETROARCH
	help
	  Libretro core: ${core}
EOF

        # Récupérer le dernier commit hash
        COMMIT_HASH=$(git ls-remote "${REPO_URL}" HEAD 2>/dev/null | head -1 | cut -f1)

        # Makefile Buildroot (.mk)
        cat > "${PKG_DIR}/${PKG_NAME}.mk" << EOF
################################################################################
# ${PKG_NAME}
################################################################################

${PKG_VAR}_VERSION = ${COMMIT_HASH}
${PKG_VAR}_SITE = ${REPO_URL}
${PKG_VAR}_SITE_METHOD = git
${PKG_VAR}_GIT_SUBMODULES = YES
${PKG_VAR}_LICENSE = GPL-2.0+

${PKG_VAR}_DEPENDENCIES = retroarch

define ${PKG_VAR}_BUILD_CMDS
	export QEMU_LD_PREFIX=/usr/arm-linux-gnueabihf && \\
	\$(TARGET_MAKE_ENV) \$(MAKE) \\
		CC="\$(TARGET_CC) -marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -U_TIME_BITS -D_TIME_BITS=32" \\
		CXX="\$(TARGET_CXX) -marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -U_TIME_BITS -D_TIME_BITS=32" \\
		AR="\$(TARGET_AR)" \\
		platform=unix \\
		${EXTRA_MAKE_OPTS} \\
		${MAKEFILE_TARGET} \\
		-C \$(@D)/${BUILD_SUBDIR}
endef

define ${PKG_VAR}_INSTALL_TARGET_CMDS
	mkdir -p \$(TARGET_DIR)/usr/lib/libretro
	\$(INSTALL) -m 0644 \$(@D)/${BUILD_SUBDIR}/${SO_NAME} \\
		\$(TARGET_DIR)/usr/lib/libretro/${SO_NAME}
endef

\$(eval \$(generic-package))
EOF

        # Enregistrer dans Config.in
        if ! grep -q "${PKG_NAME}" "${BUILDROOT_DIR}/package/Config.in"; then
            #sed -i '/^endmenu # "Games"/i\	source "package/'"${PKG_NAME}"'/Config.in"' \
            sed -i '/menu "Games"/a \  source "package/'"${PKG_NAME}"'/Config.in"' \
                "${BUILDROOT_DIR}/package/Config.in" 2>/dev/null || \
            echo "source \"package/${PKG_NAME}/Config.in\"" >> "${BUILDROOT_DIR}/package/Config.in"
        fi
    done

    log "${#LIBRETRO_CORES[@]} packages cores créés."
}

# =============================================================================
# ÉTAPE 3 : Defconfig Buildroot
# =============================================================================

cmd_configure() {
    log "Génération de la defconfig GameStick RK3032..."

    mkdir -p "${WORKDIR}/configs"

    cat > "${DEFCONFIG}" << 'DEFCONFIG'
# =============================================================================
# GameStick Lite 4K (M8) — Buildroot defconfig
# Cible : Rockchip RK3032 (Cortex-A7, ARMv7-A, VFPv4, NEON, 256 Mo RAM)
# =============================================================================

# --- Architecture ARM ---
BR2_arm=y
BR2_DOWNLOAD_FORCE_CHECK_HASHES=n
BR2_cortex_a7=y
BR2_ARM_EABIHF=y
BR2_ARM_FPU_NEON_VFPV4=y
BR2_ARM_INSTRUCTIONS_THUMB2=y
BR2_OPTIMIZE_2=y
BR2_SHARED_LIBS=y

# --- Toolchain ---
BR2_TOOLCHAIN_BUILDROOT_GLIBC=y
BR2_TOOLCHAIN_BUILDROOT_CXX=y
BR2_GCC_VERSION_13_X=y
BR2_TOOLCHAIN_BUILDROOT_WCHAR=y
BR2_TOOLCHAIN_BUILDROOT_LOCALE=y
BR2_PTHREAD_LIB="glibc"

# --- Système ---
BR2_INIT_BUSYBOX=y
BR2_SYSTEM_BIN_SH_BUSYBOX=y
BR2_TARGET_GENERIC_HOSTNAME="gamestick"
BR2_TARGET_GENERIC_ISSUE="GameStick Lite 4K - Custom RetroArch Build"
BR2_TARGET_GENERIC_GETTY_PORT="console"
BR2_TARGET_GENERIC_GETTY_BAUDRATE_115200=y
BR2_ROOTFS_OVERLAY="$(TOPDIR)/../overlay"

# --- Pas de kernel/bootloader (on garde ceux d'origine) ---
BR2_LINUX_KERNEL=n

# --- Filesystem ---
BR2_TARGET_ROOTFS_EXT2=y
BR2_TARGET_ROOTFS_EXT2_4=y
BR2_TARGET_ROOTFS_EXT2_SIZE="128M"
BR2_TARGET_ROOTFS_TAR=y

# --- Paquets système de base ---
BR2_PACKAGE_BUSYBOX=y
BR2_PACKAGE_BUSYBOX_SHOW_OTHERS=y

# --- Ajout dépendance RetroArch
BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y

# --- Graphique / Vidéo ---
BR2_PACKAGE_SDL2=y
BR2_PACKAGE_SDL2_KMSDRM=n
BR2_PACKAGE_SDL2_DIRECTFB=n
BR2_PACKAGE_SDL2_OPENGLES=n
BR2_PACKAGE_SDL2_X11=n
BR2_PACKAGE_LIBDRM=n

# --- Audio ---
BR2_PACKAGE_ALSA_LIB=y
BR2_PACKAGE_ALSA_UTILS=y
BR2_PACKAGE_ALSA_UTILS_AMIXER=y
BR2_PACKAGE_ALSA_UTILS_APLAY=y

# --- Input (manettes) ---
BR2_PACKAGE_EUDEV=y
BR2_PACKAGE_EVTEST=y

# --- Libs graphiques ---
BR2_PACKAGE_ZLIB=y
BR2_PACKAGE_LIBPNG=y
BR2_PACKAGE_FREETYPE=y

# --- Réseau (optionnel mais utile pour debug SSH) ---
BR2_PACKAGE_DROPBEAR=y
BR2_PACKAGE_DHCPCD=y
BR2_PACKAGE_WIRELESS_TOOLS=y
BR2_PACKAGE_WPA_SUPPLICANT=y

# --- Outils debug ---
BR2_PACKAGE_STRACE=y
BR2_PACKAGE_GDB=n

# --- RetroArch ---
BR2_PACKAGE_RETROARCH=y
BR2_PACKAGE_RETROARCH_SDL2=y
BR2_PACKAGE_RETROARCH_ALSA=y
BR2_PACKAGE_RETROARCH_UDEV=y
BR2_PACKAGE_RETROARCH_FREETYPE=y
BR2_PACKAGE_RETROARCH_NETWORKING=y

# --- Cores libretro ---
BR2_PACKAGE_LIBRETRO_FCEUMM=y
BR2_PACKAGE_LIBRETRO_GAMBATTE=y
BR2_PACKAGE_LIBRETRO_MGBA=y
BR2_PACKAGE_LIBRETRO_SNES9X2005=y
BR2_PACKAGE_LIBRETRO_GENESIS_PLUS_GX=y
BR2_PACKAGE_LIBRETRO_NESTOPIA=y
BR2_PACKAGE_LIBRETRO_PICODRIVE=y
BR2_PACKAGE_LIBRETRO_MEDNAFEN_PCE_FAST=y
BR2_PACKAGE_LIBRETRO_MEDNAFEN_SUPERGRAFX=y
BR2_PACKAGE_LIBRETRO_MEDNAFEN_NGP=y
BR2_PACKAGE_LIBRETRO_MEDNAFEN_WSWAN=y
BR2_PACKAGE_LIBRETRO_FBNEO=y
BR2_PACKAGE_LIBRETRO_MAME2003_PLUS=y
BR2_PACKAGE_LIBRETRO_CAP32=y
BR2_PACKAGE_LIBRETRO_FUSE=y
BR2_PACKAGE_LIBRETRO_VICE_X64=y
BR2_PACKAGE_LIBRETRO_THEODORE=y
BR2_PACKAGE_LIBRETRO_PCSX_REARMED=y
BR2_PACKAGE_LIBRETRO_STELLA=y
BR2_PACKAGE_LIBRETRO_PROSYSTEM=y
BR2_PACKAGE_LIBRETRO_HANDY=y
DEFCONFIG

    # Copier la defconfig dans Buildroot
    cp "${DEFCONFIG}" "${BUILDROOT_DIR}/configs/gamestick_rk3032_defconfig"

    # Appliquer la defconfig
    cd "${BUILDROOT_DIR}"
    make gamestick_rk3032_defconfig

    log "Configuration appliquée !"
    log ""
    log "Pour personnaliser : cd ${BUILDROOT_DIR} && make menuconfig"
    log "Prochaine étape : ./build.sh build"
}

# =============================================================================
# ÉTAPE 4 : Overlay (fichiers ajoutés au rootfs)
# =============================================================================

create_overlay() {
    log "Création de l'overlay filesystem..."

    # --- Script de démarrage S99retroarch ---
    cat > "${OVERLAY_DIR}/etc/init.d/S99retroarch" << 'INITSCRIPT'
#!/bin/sh
#
# Démarre RetroArch au boot
#

RETROARCH_BIN=/usr/bin/retroarch
RETROARCH_CFG=/etc/retroarch/retroarch.cfg
RETROARCH_LOG=/tmp/retroarch.log
CORES_DIR=/usr/lib/libretro
ROMS_DIR=/sdcard/roms
SAVES_DIR=/sdcard/saves

case "$1" in
    start)
        echo "Démarrage de RetroArch..."

        # Monter la partition userdata si pas déjà fait
        if [ ! -d /sdcard ]; then
            mkdir -p /sdcard
        fi

        # Chercher la partition userdata (la plus grande partition)
        USERDATA_DEV=""
        for dev in /dev/mmcblk0p5 /dev/mmcblk0p4 /dev/mmcblk0p3; do
            if [ -b "$dev" ]; then
                USERDATA_DEV="$dev"
                break
            fi
        done

        if [ -n "$USERDATA_DEV" ]; then
            mount -t ext4 "$USERDATA_DEV" /sdcard 2>/dev/null || true
        fi

        # Créer les dossiers nécessaires
        mkdir -p "$ROMS_DIR" "$SAVES_DIR"
        mkdir -p /sdcard/system    # BIOS
        mkdir -p /sdcard/config    # Override configs
        mkdir -p /sdcard/shaders
        mkdir -p /sdcard/thumbnails

        # Lancer RetroArch en plein écran
        export HOME=/root
        export XDG_CONFIG_HOME=/etc
        export SDL_VIDEODRIVER=fbdev
        export SDL_AUDIODRIVER=alsa

        # Attendre que le framebuffer soit prêt
        sleep 2

        "$RETROARCH_BIN" --config "$RETROARCH_CFG" \
            --verbose \
            > "$RETROARCH_LOG" 2>&1 &
        ;;

    stop)
        echo "Arrêt de RetroArch..."
        killall retroarch 2>/dev/null
        sync
        umount /sdcard 2>/dev/null
        ;;

    restart)
        $0 stop
        sleep 1
        $0 start
        ;;

    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
INITSCRIPT
    chmod +x "${OVERLAY_DIR}/etc/init.d/S99retroarch"

    # --- Configuration RetroArch optimisée pour RK3032 ---
    mkdir -p "${OVERLAY_DIR}/etc/retroarch"
    cat > "${OVERLAY_DIR}/etc/retroarch/retroarch.cfg" << 'RACFG'
# =============================================================================
# RetroArch — Configuration GameStick Lite 4K (RK3032, 256 Mo RAM)
# =============================================================================

# --- Chemins ---
libretro_directory = "/usr/lib/libretro"
libretro_info_path = "/usr/share/retroarch/info"
content_directory = "/sdcard/roms"
savefile_directory = "/sdcard/saves"
savestate_directory = "/sdcard/saves"
system_directory = "/sdcard/system"
assets_directory = "/usr/share/retroarch/assets"
rgui_browser_directory = "/sdcard/roms"
playlist_directory = "/sdcard/playlists"
core_options_path = "/sdcard/config/retroarch-core-options.cfg"

# --- Vidéo ---
video_driver = "sdl2"
video_fullscreen = "true"
video_vsync = "true"
video_max_swapchain_images = "2"
video_smooth = "false"
video_scale_integer = "true"
video_aspect_ratio_auto = "true"
video_font_size = "18"
video_msg_pos_x = "0.02"
video_msg_pos_y = "0.98"

# --- Audio ---
audio_driver = "alsa"
audio_device = "default"
audio_latency = "64"
audio_rate_control = "true"
audio_rate_control_delta = "0.005"

# --- Input (manettes 2.4 GHz du GameStick) ---
input_driver = "udev"
input_joypad_driver = "udev"
input_autodetect_enable = "true"
input_exit_emulator = "escape"
input_menu_toggle_gamepad_combo = "6"
# Combo = Start + Select pour ouvrir le menu

# --- Interface ---
menu_driver = "rgui"
# RGUI = le plus léger, adapté aux 256 Mo de RAM
rgui_show_start_screen = "false"
menu_show_online_updater = "false"
menu_show_core_updater = "false"

# --- Performance (critique avec 256 Mo) ---
video_threaded = "true"
audio_enable = "true"
rewind_enable = "false"
# Désactiver le rewind : économise beaucoup de RAM
savestate_auto_save = "false"
savestate_auto_load = "false"

# --- Réseau ---
network_cmd_enable = "false"
stdin_cmd_enable = "false"

# --- Scanner de contenu ---
content_database_path = "/usr/share/retroarch/database/rdb"
cheat_database_path = "/usr/share/retroarch/database/cht"
cursor_directory = "/usr/share/retroarch/database/cursors"

# --- Logging ---
log_verbosity = "false"
RACFG

    log "Overlay créé dans ${OVERLAY_DIR}"
}

# =============================================================================
# ÉTAPE 5 : Compilation
# =============================================================================

cmd_build() {
    log "Lancement de la compilation Buildroot..."
    log "Cible : ARMv7-A Cortex-A7 VFPv4 NEON hard-float"
    log "Ceci peut prendre 1-3 heures selon votre machine."
    log ""

    # Créer l'overlay avant de compiler
    create_overlay

    cd "${BUILDROOT_DIR}"

    # Nombre de cœurs CPU pour la compilation parallèle
    JOBS=$(nproc)
    log "Compilation avec ${JOBS} threads..."

    make -j${JOBS} 2>&1 | tee "${WORKDIR}/build.log"

    if [ $? -eq 0 ]; then
        log "=========================================="
        log "  COMPILATION RÉUSSIE !"
        log "=========================================="
        log ""
        log "Rootfs : ${BUILDROOT_DIR}/output/images/rootfs.ext4"
        log "Tarball : ${BUILDROOT_DIR}/output/images/rootfs.tar"
        log "Toolchain : ${BUILDROOT_DIR}/output/host/bin/arm-*"
        log ""
        log "Prochaine étape : ./build.sh image"
    else
        err "Compilation échouée ! Voir build.log"
        exit 1
    fi
}

# =============================================================================
# ÉTAPE 6 : Compilation de cores supplémentaires (hors Buildroot)
# =============================================================================

cmd_cores() {
    log "Compilation de cores libretro supplémentaires..."

    # Utiliser la toolchain Buildroot
    local TC="${BUILDROOT_DIR}/output/host/bin/arm-buildroot-linux-gnueabihf"
    local SYSROOT="${BUILDROOT_DIR}/output/host/arm-buildroot-linux-gnueabihf/sysroot"

    if [ ! -f "${TC}-gcc" ]; then
        err "Toolchain introuvable. Lancez d'abord ./build.sh build"
        exit 1
    fi

    local CC="${TC}-gcc --sysroot=${SYSROOT}"
    local CXX="${TC}-g++ --sysroot=${SYSROOT}"
    local AR="${TC}-ar"
    local CFLAGS="-marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -O2"

    mkdir -p "${CORES_DIR}/build" "${CORES_DIR}/output"

    # Exemple : compiler un core manuellement
    local CORE_NAME="$2"
    if [ -z "${CORE_NAME:-}" ]; then
        log "Usage : ./build.sh cores <nom_du_core>"
        log "Exemple : ./build.sh cores libretro-cap32"
        log ""
        log "Ou clonez un repo dans ${CORES_DIR}/build/ et compilez :"
        log "  cd ${CORES_DIR}/build/<core>"
        log "  make CC=\"${CC}\" CXX=\"${CXX}\" CFLAGS=\"${CFLAGS}\" platform=unix"
        return
    fi

    cd "${CORES_DIR}/build"
    if [ ! -d "${CORE_NAME}" ]; then
        git clone "https://github.com/libretro/${CORE_NAME}.git"
    fi

    cd "${CORE_NAME}"
    make clean 2>/dev/null || true

    make \
        CC="${CC}" \
        CXX="${CXX}" \
        AR="${AR}" \
        CFLAGS="${CFLAGS}" \
        CXXFLAGS="${CFLAGS}" \
        platform=unix \
        -j$(nproc)

    # Copier le .so résultant
    find . -name "*_libretro.so" -exec cp {} "${CORES_DIR}/output/" \;

    log "Core compilé ! Vérification :"
    for so in "${CORES_DIR}/output/"*_libretro.so; do
        file "$so"
        readelf -A "$so" 2>/dev/null | grep -E "CPU_arch|FP_arch|SIMD|VFP_args" || true
    done
}

# =============================================================================
# ÉTAPE 7 : Assemblage de l'image SD
# =============================================================================

cmd_image() {
    log "Assemblage de l'image SD finale..."

    local ROOTFS="${BUILDROOT_DIR}/output/images/rootfs.ext4"
    local FINAL_IMG="${OUTPUT_DIR}/gamestick_custom.img"

    if [ ! -f "${ROOTFS}" ]; then
        err "rootfs.ext4 introuvable. Lancez d'abord ./build.sh build"
        exit 1
    fi

    mkdir -p "${OUTPUT_DIR}"

    cat << 'EOF'
# =============================================================================
# ASSEMBLAGE DE L'IMAGE SD
# =============================================================================
#
# L'image SD du GameStick a cette structure :
#
#   Offset     | Taille | Contenu
#   -----------|--------|----------------------------------
#   0x0000     | 1 Mo   | uboot (bootloader Rockchip)
#   0x100000   | 2 Mo   | trust (ARM Trusted Firmware)
#   0x300000   | 9 Mo   | boot (kernel + DTB + config)
#   0xC00000   | ~88 Mo | rootfs ← ON REMPLACE CELUI-CI
#   ~100 Mo    | reste  | userdata (ROMs, saves)
#
# IMPORTANT : On garde les 3 premières partitions de l'image originale !
# Seul le rootfs est remplacé par notre build Buildroot.
#
# =============================================================================
EOF

    if [ -z "${GAMESTICK_BACKUP_IMG}" ] || [ ! -f "${GAMESTICK_BACKUP_IMG}" ]; then
        warn ""
        warn "Image backup non configurée !"
        warn ""
        warn "Pour assembler l'image finale, tu dois :"
        warn "  1. Définir GAMESTICK_BACKUP_IMG dans build.sh"
        warn "     (chemin vers ton dump gamestick_backup.img)"
        warn "  2. Relancer ./build.sh image"
        warn ""
        warn "En attendant, le rootfs est disponible ici :"
        warn "  ${ROOTFS}"
        warn ""
        warn "Tu peux le flasher manuellement :"
        warn "  # Identifier l'offset de la partition rootfs"
        warn "  fdisk -l gamestick_backup.img"
        warn "  # Copier le nouveau rootfs par-dessus"
        warn "  dd if=${ROOTFS} of=gamestick_backup.img seek=<OFFSET> bs=512 conv=notrunc"
        warn ""
        return
    fi

    log "Copie de l'image originale..."
    cp "${GAMESTICK_BACKUP_IMG}" "${FINAL_IMG}"

    # Identifier les partitions
    log "Partitions de l'image :"
    fdisk -l "${FINAL_IMG}"

    # Trouver l'offset de la partition rootfs (partition 4 typiquement)
    local ROOTFS_START=$(fdisk -l "${FINAL_IMG}" 2>/dev/null | \
        awk '/^.*img4/{print $2}')

    if [ -z "${ROOTFS_START}" ]; then
        warn "Impossible de détecter automatiquement la partition rootfs."
        warn "Utilise fdisk -l pour identifier le bon offset et exécute :"
        warn "  dd if=${ROOTFS} of=${FINAL_IMG} seek=<START_SECTOR> bs=512 conv=notrunc"
        return
    fi

    log "Écriture du rootfs à l'offset ${ROOTFS_START} secteurs..."
    sudo dd if="${ROOTFS}" of="${FINAL_IMG}" \
        seek="${ROOTFS_START}" bs=512 conv=notrunc status=progress

    log ""
    log "=========================================="
    log "  IMAGE PRÊTE !"
    log "=========================================="
    log ""
    log "Fichier : ${FINAL_IMG}"
    log ""
    log "Pour flasher sur SD :"
    log "  sudo dd if=${FINAL_IMG} of=/dev/sdX bs=4M status=progress conv=fsync"
    log "  Ou utilise balenaEtcher sous Windows."
}

# =============================================================================
# COMMANDE : all
# =============================================================================

cmd_all() {
    cmd_setup
    cmd_configure
    cmd_build
    cmd_image
}

# =============================================================================
# Point d'entrée
# =============================================================================

case "${1:-help}" in
    setup)     cmd_setup ;;
    configure) cmd_configure ;;
    build)     cmd_build ;;
    cores)     cmd_cores "$@" ;;
    image)     cmd_image ;;
    all)       cmd_all ;;
    menuconfig)
        cd "${BUILDROOT_DIR}" && make menuconfig
        ;;
    clean)
        cd "${BUILDROOT_DIR}" && make clean
        ;;
    *)
        echo ""
        echo "Usage: $0 <commande>"
        echo ""
        echo "Commandes :"
        echo "  setup       Installe les dépendances, télécharge Buildroot"
        echo "  configure   Applique la defconfig GameStick RK3032"
        echo "  build       Compile tout (rootfs + RetroArch + cores)"
        echo "  cores       Compile des cores supplémentaires"
        echo "  image       Assemble l'image SD finale"
        echo "  all         Exécute toutes les étapes"
        echo "  menuconfig  Lance le configurateur interactif Buildroot"
        echo "  clean       Nettoie les fichiers de compilation"
        echo ""
        echo "Workflow typique :"
        echo "  ./build.sh setup"
        echo "  ./build.sh configure"
        echo "  ./build.sh menuconfig   # optionnel, pour ajuster"
        echo "  ./build.sh build"
        echo "  ./build.sh image"
        echo ""
        ;;
esac
