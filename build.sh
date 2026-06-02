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
        e2fsprogs \
        squashfs-tools
 
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
    setup_mali_headers
    setup_retroarch_package
    setup_libretro_cores_package

    log "Setup terminé !"
    log "Prochaine étape : ./build.sh configure"
}
 
# =============================================================================
# ÉTAPE 2a : Headers EGL/GLES2 (Khronos) pour Mali-400
# =============================================================================

setup_mali_headers() {
    local HEADERS_DIR="${WORKDIR}/mali-headers-src"
    log "Téléchargement des headers Khronos EGL/GLES2..."

    mkdir -p "${HEADERS_DIR}/EGL" "${HEADERS_DIR}/GLES2" "${HEADERS_DIR}/KHR"

    local EGL_BASE="https://raw.githubusercontent.com/KhronosGroup/EGL-Registry/main/api"
    local GL_BASE="https://raw.githubusercontent.com/KhronosGroup/OpenGL-Registry/main/api"

    for f in KHR/khrplatform.h EGL/egl.h EGL/eglext.h EGL/eglplatform.h; do
        [ -f "${HEADERS_DIR}/${f}" ] || wget -q -O "${HEADERS_DIR}/${f}" "${EGL_BASE}/${f}"
    done
    for f in GLES2/gl2.h GLES2/gl2ext.h GLES2/gl2platform.h; do
        [ -f "${HEADERS_DIR}/${f}" ] || wget -q -O "${HEADERS_DIR}/${f}" "${GL_BASE}/${f}"
    done
    [ -f "${HEADERS_DIR}/gbm.h" ] || \
        wget -q -O "${HEADERS_DIR}/gbm.h" \
        "https://gitlab.freedesktop.org/mesa/mesa/-/raw/mesa-23.0.0/src/gbm/main/gbm.h"

    # Générer le stub C GLES2 depuis le header téléchargé
    if [ ! -f "${HEADERS_DIR}/gles2_stub.c" ]; then
        python3 - "${HEADERS_DIR}/GLES2/gl2.h" << 'PYEOF' > "${HEADERS_DIR}/gles2_stub.c"
import re, sys
with open(sys.argv[1]) as f:
    content = f.read()
print("#include <GLES2/gl2.h>")
print()
for m in re.finditer(r'GL_APICALL\s+([\w\s\*]+?)\s*GL_APIENTRY\s+(\w+)\s*\(([^;]*)\)\s*;', content):
    ret, name, params = m.group(1).strip(), m.group(2), m.group(3).strip() or "void"
    if ret == "void":
        body = "{}"
    elif '*' in ret:
        body = "{ return (void*)0; }"
    else:
        body = "{ return (" + ret + ")0; }"
    print("GL_APICALL " + ret + " GL_APIENTRY " + name + "(" + params + ") " + body)
PYEOF
    fi

    log "Headers EGL/GLES2 prêts dans mali-headers-src/"
}

# =============================================================================
# ÉTAPE 2b : Packages Buildroot custom pour RetroArch
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
select BR2_PACKAGE_ALSA_LIB
select BR2_PACKAGE_EUDEV
select BR2_PACKAGE_FREETYPE
help
  RetroArch is the official reference frontend for the
  libretro API. It provides a unified interface for running
  libretro cores (emulators, game engines, etc.).

  https://www.retroarch.com
CONFIGIN
 
    # retroarch.mk (Makefile Buildroot)
    cat > "${PKG_DIR}/retroarch.mk" << 'RETROMK'
################################################################################
#
# retroarch
#
################################################################################
 
RETROARCH_VERSION = v1.21.0
RETROARCH_SITE = \$(call github,libretro,RetroArch,\$(RETROARCH_VERSION))
RETROARCH_LICENSE = GPL-3.0+
RETROARCH_LICENSE_FILES = COPYING
 
RETROARCH_DEPENDENCIES = host-pkgconf zlib alsa-lib eudev freetype libdrm

# --- Options de configuration ---

RETROARCH_CONF_OPTS = \
	--disable-x11 \
    --disable-wayland \
    --enable-opengles \
    --enable-egl \
    --disable-dynamic_egl \
    --disable-opengl \
    --disable-vulkan \
    --enable-kms \
    --enable-neon \
    --enable-floathard \
    --enable-threads \
    --enable-alsa \
    --disable-pulse \
    --disable-oss \
    --disable-jack \
    --disable-sdl2 \
    --disable-ffmpeg \
    --enable-zlib \
    --enable-freetype \
    --enable-rgui \
    --disable-xmb \
    --disable-ozone \
    --disable-materialui \
    --disable-qt \
    --disable-discord \
    --disable-caca \
    --enable-udev \
    --disable-networking
 
# --- Configuration ---
 
define RETROARCH_CONFIGURE_CMDS
	cd $(@D) && \
	$(TARGET_CONFIGURE_OPTS) \
	CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include" \
	PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" \
	PKG_CONF_PATH="$(PKG_CONFIG_HOST_BINARY)" \
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
 
define RETROARCH_INSTALL_MALI_HEADERS
	$(foreach d,EGL GLES2 KHR,\
		mkdir -p $(STAGING_DIR)/usr/include/$(d) && \
		cp -n $(TOPDIR)/../mali-headers-src/$(d)/* $(STAGING_DIR)/usr/include/$(d)/ 2>/dev/null || true ;)
	cp -n $(TOPDIR)/../mali-headers-src/gbm.h $(STAGING_DIR)/usr/include/ 2>/dev/null || true
	cp -f $(TOPDIR)/../overlay/usr/lib/libmali-utgard-400-r7p0-gbm.so $(STAGING_DIR)/usr/lib/
	ln -sf libmali-utgard-400-r7p0-gbm.so $(STAGING_DIR)/usr/lib/libgbm.so
	ln -sf libmali-utgard-400-r7p0-gbm.so $(STAGING_DIR)/usr/lib/libEGL.so
	ln -sf libmali-utgard-400-r7p0-gbm.so $(STAGING_DIR)/usr/lib/libGLESv2.so
	mkdir -p $(STAGING_DIR)/usr/lib/pkgconfig
	printf 'prefix=/usr\nincludedir=$${prefix}/include\nlibdir=$${prefix}/lib\nName: egl\nDescription: EGL library\nVersion: 1.5\nLibs: -L$${libdir} -lEGL\nCflags: -I$${includedir}\n' \
		> $(STAGING_DIR)/usr/lib/pkgconfig/egl.pc
	printf 'prefix=/usr\nincludedir=$${prefix}/include\nlibdir=$${prefix}/lib\nName: glesv2\nDescription: GLES2 library\nVersion: 2.0\nLibs: -L$${libdir} -lGLESv2\nCflags: -I$${includedir}\n' \
		> $(STAGING_DIR)/usr/lib/pkgconfig/glesv2.pc
	printf 'prefix=/usr\nincludedir=$${prefix}/include\nlibdir=$${prefix}/lib\nName: gbm\nDescription: Mesa GBM\nVersion: 23.0\nLibs: -L$${libdir} -lgbm\nCflags: -I$${includedir}\n' \
		> $(STAGING_DIR)/usr/lib/pkgconfig/gbm.pc
endef
RETROARCH_PRE_CONFIGURE_HOOKS += RETROARCH_INSTALL_MALI_HEADERS

define RETROARCH_FIX_CONFIG
	$(SED) 's%-I/usr/include%-I$(STAGING_DIR)/usr/include%g' $(@D)/config.mk
	$(SED) 's%^LDFLAGS = $$%LDFLAGS = -Wl,--allow-shlib-undefined%' $(@D)/config.mk
endef
RETROARCH_POST_CONFIGURE_HOOKS += RETROARCH_FIX_CONFIG

define RETROARCH_FIX_EGL_DLL
	# BUG RetroArch (double) dans gfx/common/egl_common.c :
	#
	# 1) egl_init_dll() utilise dylib_load("libEGL.dll") — nom DLL Windows
	#    hardcodé sans #ifdef _WIN32. Sur Linux ce dlopen() échoue silencieusement,
	#    laissant tous les pointeurs EGL (_egl_bind_api, etc.) à NULL.
	#
	# 2) egl_init_dll() n'est jamais appelée sur le chemin Linux/KMS :
	#    drm_ctx.c::bind_api() appelle egl_bind_api() directement, alors que
	#    egl_init_dll() n'est invoquée que depuis angle_common.c (chemin ANGLE/Windows).
	#    Résultat : _egl_bind_api reste NULL → SIGSEGV PC=0 au premier appel.
	#
	# Fix via Python (robuste, évite les problèmes de \n dans sed) :
	python3 -c '\
import sys; \
f = sys.argv[1]; \
s = open(f).read(); \
s = s.replace("dylib_load(\"libEGL.dll\")", "dylib_load(\"libEGL.so.1\")"); \
s = s.replace(\
    "   return _egl_bind_api(egl_api);",\
    "#ifdef HAVE_DYNAMIC_EGL\n   if (!_egl_bind_api) egl_init_dll();\n   if (!_egl_bind_api) return false;\n#endif\n   return _egl_bind_api(egl_api);"\
); \
open(f, "w").write(s)' \
		$(@D)/gfx/common/egl_common.c
endef
RETROARCH_POST_CONFIGURE_HOOKS += RETROARCH_FIX_EGL_DLL

define RETROARCH_INSTALL_MALI_TARGET
	mkdir -p $(TARGET_DIR)/usr/lib
	cp -f $(TOPDIR)/../overlay/usr/lib/libmali-utgard-400-r7p0-gbm.so $(TARGET_DIR)/usr/lib/
	ln -sf libmali-utgard-400-r7p0-gbm.so $(TARGET_DIR)/usr/lib/libgbm.so
	ln -sf libmali-utgard-400-r7p0-gbm.so $(TARGET_DIR)/usr/lib/libEGL.so
	ln -sf libmali-utgard-400-r7p0-gbm.so $(TARGET_DIR)/usr/lib/libGLESv2.so
endef
RETROARCH_POST_INSTALL_TARGET_HOOKS += RETROARCH_INSTALL_MALI_TARGET

$(eval $(generic-package))
RETROMK
 
    # Supprimer tout fichier .hash existant
    rm -f "${PKG_DIR}/retroarch.hash"
 
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
 
    # Pattern inspiré de Batocera/Recalbox :
    #   - $(call github,...) pour le téléchargement (tarball, pas git clone)
    #   - CFLAGS/CXXFLAGS en variables d'environnement avant $(MAKE)
    #   - CC/CXX en arguments make
    #   - Pas de fichier .hash (supprimé)
 
    for core in "${LIBRETRO_CORES[@]}"; do
        local PKG_NAME="libretro-${core}"
        local PKG_DIR="${BUILDROOT_DIR}/package/${PKG_NAME}"
        local PKG_VAR=$(echo "${PKG_NAME}" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
 
        mkdir -p "${PKG_DIR}"
 
        # Valeurs par défaut
        local GH_AUTHOR="libretro"
        local GH_REPO=""
        local SO_NAME="${core}_libretro.so"
        local MAKEFILE_OPTS=""
        local BUILD_SUBDIR=""
        local EXTRA_MAKE_OPTS=""
        local GIT_SUBMODULES="NO"
 
        case "${core}" in
            fceumm)              GH_REPO="libretro-fceumm" ;;
            gambatte)            GH_REPO="gambatte-libretro" ;;
            mgba)                GH_REPO="mgba"
                                 MAKEFILE_OPTS="-f Makefile.libretro" ;;
            snes9x2005)          GH_REPO="snes9x2005" ;;
            genesis_plus_gx)     GH_REPO="Genesis-Plus-GX"
                                 SO_NAME="genesis_plus_gx_libretro.so"
                                 MAKEFILE_OPTS="-f Makefile.libretro" ;;
            nestopia)            GH_REPO="nestopia"
                                 SO_NAME="nestopia_libretro.so"
                                 BUILD_SUBDIR="libretro" ;;
            picodrive)           GH_REPO="picodrive"
                                 MAKEFILE_OPTS="-f Makefile.libretro"
                                 GIT_SUBMODULES="YES" ;;
            mednafen_pce_fast)   GH_REPO="beetle-pce-fast-libretro"
                                 SO_NAME="mednafen_pce_fast_libretro.so" ;;
            mednafen_supergrafx) GH_REPO="beetle-supergrafx-libretro"
                                 SO_NAME="mednafen_supergrafx_libretro.so" ;;
            mednafen_ngp)        GH_REPO="beetle-ngp-libretro"
                                 SO_NAME="mednafen_ngp_libretro.so" ;;
            mednafen_wswan)      GH_REPO="beetle-wswan-libretro"
                                 SO_NAME="mednafen_wswan_libretro.so" ;;
            fbneo)               GH_REPO="FBNeo"
                                 SO_NAME="fbneo_libretro.so"
                                 BUILD_SUBDIR="src/burner/libretro"
                                 EXTRA_MAKE_OPTS="profile=performance" ;;
            mame2003_plus)       GH_REPO="mame2003-plus-libretro"
                                 SO_NAME="mame2003_plus_libretro.so" ;;
            cap32)               GH_REPO="libretro-cap32"
                                 SO_NAME="cap32_libretro.so" ;;
            fuse)                GH_REPO="fuse-libretro"
                                 SO_NAME="fuse_libretro.so" ;;
            vice_x64)            GH_REPO="vice-libretro"
                                 SO_NAME="vice_x64_libretro.so"
                                 EXTRA_MAKE_OPTS="EMUTYPE=x64" ;;
            theodore)            GH_AUTHOR="Zlika"
                                 GH_REPO="theodore"
                                 SO_NAME="theodore_libretro.so" ;;
            pcsx_rearmed)        GH_REPO="pcsx_rearmed"
                                 SO_NAME="pcsx_rearmed_libretro.so"
                                 MAKEFILE_OPTS="-f Makefile.libretro"
                                 EXTRA_MAKE_OPTS="DYNAREC=ari64 HAVE_NEON=1"
                                 GIT_SUBMODULES="YES" ;;
            stella)              GH_REPO="stella2014-libretro"
                                 SO_NAME="stella2014_libretro.so" ;;
            prosystem)           GH_REPO="prosystem-libretro"
                                 SO_NAME="prosystem_libretro.so" ;;
            handy)               GH_REPO="libretro-handy"
                                 SO_NAME="handy_libretro.so" ;;
            *)
                warn "Core inconnu : ${core}, ignoré."
                continue
                ;;
        esac
 
        # Récupérer le dernier commit hash
        local COMMIT_HASH
        COMMIT_HASH=$(git ls-remote "https://github.com/${GH_AUTHOR}/${GH_REPO}.git" HEAD 2>/dev/null | head -1 | cut -f1 || true)
        if [ -z "${COMMIT_HASH}" ]; then
            warn "Impossible de récupérer le hash pour ${core}, ignoré."
            continue
        fi
 
        log "  ${core} → ${COMMIT_HASH:0:12}"
 
        # Config.in
        cat > "${PKG_DIR}/Config.in" << EOF
config BR2_PACKAGE_${PKG_VAR}
bool "libretro-${core}"
depends on BR2_PACKAGE_RETROARCH
help
Libretro core: ${core}
EOF
 
        # Makefile Buildroot (.mk) — pattern Batocera
        # Les cores avec submodules (picodrive, pcsx_rearmed) utilisent git
        # Les autres utilisent $(call github,...) qui télécharge un tarball (plus rapide)
        local SITE_LINE
        if [ "${GIT_SUBMODULES}" = "YES" ]; then
            SITE_LINE="${PKG_VAR}_SITE = https://github.com/${GH_AUTHOR}/${GH_REPO}.git
        ${PKG_VAR}_SITE_METHOD = git
        ${PKG_VAR}_GIT_SUBMODULES = YES"
        else
            SITE_LINE="${PKG_VAR}_SITE = \$(call github,${GH_AUTHOR},${GH_REPO},\$(${PKG_VAR}_VERSION))"
        fi
 
        cat > "${PKG_DIR}/${PKG_NAME}.mk" << EOF

################################################################################
# ${PKG_NAME} — pattern Batocera
################################################################################
 
${PKG_VAR}_VERSION = ${COMMIT_HASH}
${SITE_LINE}
${PKG_VAR}_LICENSE = GPL-2.0+
 
define ${PKG_VAR}_BUILD_CMDS
	CFLAGS="\$(TARGET_CFLAGS)" CXXFLAGS="\$(TARGET_CXXFLAGS)" \\
	QEMU_LD_PREFIX=/usr/arm-linux-gnueabihf \\
	\$(MAKE) CC="\$(TARGET_CC)" CXX="\$(TARGET_CXX)" AR="\$(TARGET_AR)" \\
		platform=unix ${EXTRA_MAKE_OPTS} ${MAKEFILE_OPTS} \\
		-C \$(@D)/${BUILD_SUBDIR}
endef
 
define ${PKG_VAR}_INSTALL_TARGET_CMDS
	mkdir -p \$(TARGET_DIR)/usr/lib/libretro
	\$(INSTALL) -m 0644 \$(@D)/${BUILD_SUBDIR}/${SO_NAME} \\
		\$(TARGET_DIR)/usr/lib/libretro/${SO_NAME}
endef
 
\$(eval \$(generic-package))
EOF
 
        # Supprimer tout fichier .hash existant
        rm -f "${PKG_DIR}/${PKG_NAME}.hash"
 
        # Enregistrer dans Config.in
        if ! grep -q "${PKG_NAME}" "${BUILDROOT_DIR}/package/Config.in"; then
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
BR2_TARGET_OPTIMIZATION="-U_TIME_BITS -D_TIME_BITS=32"
# --- Toolchain ---
BR2_KERNEL_HEADERS_VERSION=y
BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_4_4=y
BR2_DEFAULT_KERNEL_HEADERS="4.4.302"
BR2_DEFAULT_KERNEL_VERSION="4.4.302"
BR2_PACKAGE_GLIBC_KERNEL_COMPAT=y
BR2_TOOLCHAIN_BUILDROOT_CXX=y
BR2_TOOLCHAIN_BUILDROOT_WCHAR=y
BR2_TOOLCHAIN_HAS_SSP=n
BR2_SSP_NONE=y
BR2_RELRO_NONE=y
BR2_FORTIFY_SOURCE_NONE=y

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
BR2_TARGET_ROOTFS_EXT2_SIZE="256M"
BR2_TARGET_ROOTFS_TAR=y

# --- Paquets système de base ---
BR2_PACKAGE_BUSYBOX=y
BR2_PACKAGE_BUSYBOX_SHOW_OTHERS=y
BR2_PACKAGE_BASH=y
BR2_PACKAGE_DOSFSTOOLS=y
BR2_PACKAGE_SEEDRNG=n

# --- Ajout dépendance RetroArch
BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y

# --- Graphique / Vidéo ---
BR2_PACKAGE_LIBDRM=y

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

# --- Outils debug ---
BR2_PACKAGE_STRACE=y
BR2_PACKAGE_GDB=y
BR2_PACKAGE_GDB_DEBUGGER=y
BR2_STRIP_NONE=y
BR2_ENABLE_DEBUG=y

# --- RetroArch ---
BR2_PACKAGE_RETROARCH=y

# --- Cores libretro ---
BR2_PACKAGE_LIBRETRO_FCEUMM=n
BR2_PACKAGE_LIBRETRO_GAMBATTE=n
BR2_PACKAGE_LIBRETRO_MGBA=n
BR2_PACKAGE_LIBRETRO_SNES9X2005=y
BR2_PACKAGE_LIBRETRO_GENESIS_PLUS_GX=n
BR2_PACKAGE_LIBRETRO_NESTOPIA=n
BR2_PACKAGE_LIBRETRO_PICODRIVE=n
BR2_PACKAGE_LIBRETRO_MEDNAFEN_PCE_FAST=n
BR2_PACKAGE_LIBRETRO_MEDNAFEN_SUPERGRAFX=n
BR2_PACKAGE_LIBRETRO_MEDNAFEN_NGP=n
BR2_PACKAGE_LIBRETRO_MEDNAFEN_WSWAN=n
BR2_PACKAGE_LIBRETRO_FBNEO=n
BR2_PACKAGE_LIBRETRO_MAME2003_PLUS=n
BR2_PACKAGE_LIBRETRO_CAP32=n
BR2_PACKAGE_LIBRETRO_FUSE=n
BR2_PACKAGE_LIBRETRO_VICE_X64=n
BR2_PACKAGE_LIBRETRO_THEODORE=n
BR2_PACKAGE_LIBRETRO_PCSX_REARMED=n
BR2_PACKAGE_LIBRETRO_STELLA=n
BR2_PACKAGE_LIBRETRO_PROSYSTEM=n
BR2_PACKAGE_LIBRETRO_HANDY=n
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
# ÉTAPE 4 : Compilation
# =============================================================================
 
cmd_build() {
    log "Lancement de la compilation Buildroot..."
    log "Cible : ARMv7-A Cortex-A7 VFPv4 NEON hard-float"
    log "Ceci peut prendre 1-3 heures selon votre machine."
    log ""
 
    # Vérifier que l'overlay existe
    if [ ! -d "${OVERLAY_DIR}/etc/init.d" ]; then
        err "Overlay manquant ! Le dossier ${OVERLAY_DIR} doit contenir les fichiers du rootfs."
        exit 1
    fi
 
    cd "${BUILDROOT_DIR}"
 
    # Nombre de cœurs CPU pour la compilation parallèle
    JOBS=$(nproc)
    log "Compilation avec ${JOBS} threads..."
 
    make -j${JOBS} 2>&1 | tee "${WORKDIR}/build.log" || {
        err "Compilation échouée ! Voir build.log"
        exit 1
    }

    log "=========================================="
    log "  COMPILATION RÉUSSIE !"
    log "=========================================="
    log ""
    log "Rootfs : ${BUILDROOT_DIR}/output/images/rootfs.ext4"
    log "Tarball : ${BUILDROOT_DIR}/output/images/rootfs.tar"
    log "Toolchain : ${BUILDROOT_DIR}/output/host/bin/arm-*"
    log ""
    log "Prochaine étape : ./build.sh image"
}
 
# =============================================================================
# ÉTAPE 5 : Compilation de cores supplémentaires (hors Buildroot)
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
# ÉTAPE 6 : Assemblage de l'image SD
# =============================================================================
 
cmd_image() {
    log "Génération de l'image rootfs (partition 4)..."

    local ROOTFS_TAR="${BUILDROOT_DIR}/output/images/rootfs.tar"
    local ROOTFS_EXT4="${BUILDROOT_DIR}/output/images/rootfs.ext4"
    local ROOTFS_SQUASHFS="${OUTPUT_DIR}/rootfs_p4.squashfs"
    # Taille de la partition 4 sur le GameStick Lite 4K : 65 Mo
    local PART4_MAX_SIZE=$(( 65 * 1024 * 1024 ))

    if [ ! -f "${ROOTFS_TAR}" ] && [ ! -f "${ROOTFS_EXT4}" ]; then
        err "Aucun rootfs trouvé. Lancez d'abord ./build.sh build"
        exit 1
    fi

    mkdir -p "${OUTPUT_DIR}"

    # =========================================================================
    # Étape 1 : Convertir le rootfs en squashfs (format du GameStick)
    # =========================================================================
    log "Conversion du rootfs en squashfs (gzip)..."

    local ROOTFS_EXTRACT="${OUTPUT_DIR}/rootfs_extracted"
    rm -rf "${ROOTFS_EXTRACT}"
    mkdir -p "${ROOTFS_EXTRACT}"

    if [ -f "${ROOTFS_TAR}" ]; then
        tar xf "${ROOTFS_TAR}" -C "${ROOTFS_EXTRACT}"
    else
        local TMP_MNT="${OUTPUT_DIR}/tmp_mnt"
        mkdir -p "${TMP_MNT}"
        sudo mount -o loop,ro "${ROOTFS_EXT4}" "${TMP_MNT}"
        sudo cp -a "${TMP_MNT}/." "${ROOTFS_EXTRACT}/"
        sudo umount "${TMP_MNT}"
        rmdir "${TMP_MNT}"
    fi

    # Appliquer l'overlay — intègre les dernières modifications sans rebuild complet
    sudo cp -a "${OVERLAY_DIR}/." "${ROOTFS_EXTRACT}/"

    rm -f "${ROOTFS_SQUASHFS}"
    sudo mksquashfs "${ROOTFS_EXTRACT}" "${ROOTFS_SQUASHFS}" \
        -comp gzip -noappend -quiet

    rm -rf "${ROOTFS_EXTRACT}"

    local NEW_SIZE=$(stat -c%s "${ROOTFS_SQUASHFS}")
    log "Rootfs squashfs : $(( NEW_SIZE / 1024 / 1024 )) Mo"

    if [ "${NEW_SIZE}" -gt "${PART4_MAX_SIZE}" ]; then
        err "Le rootfs ($(( NEW_SIZE / 1024 / 1024 )) Mo) dépasse la taille de la partition 4 (65 Mo) !"
        err "Réduis le contenu du rootfs."
        exit 1
    fi

    # =========================================================================
    # Étape 2 : Vérification du squashfs
    # =========================================================================
    log "Vérification du squashfs..."

    local VERIFY_MNT="${OUTPUT_DIR}/verify_mnt"
    mkdir -p "${VERIFY_MNT}"

    if sudo mount -t squashfs -o ro "${ROOTFS_SQUASHFS}" "${VERIFY_MNT}" 2>/dev/null; then
        local CHECK_OK=true

        if [ -f "${VERIFY_MNT}/usr/bin/retroarch" ]; then
            if file "${VERIFY_MNT}/usr/bin/retroarch" 2>/dev/null | grep -q "ARM"; then
                log "  ✅ RetroArch présent (ARM)"
            else
                err "  ❌ RetroArch n'est pas un binaire ARM !"
                CHECK_OK=false
            fi
        else
            err "  ❌ RetroArch absent du rootfs !"
            CHECK_OK=false
        fi

        local CORE_COUNT=$(find "${VERIFY_MNT}/usr/lib/libretro/" -name "*.so" 2>/dev/null | wc -l)
        if [ "${CORE_COUNT}" -gt 0 ]; then
            log "  ✅ ${CORE_COUNT} cores libretro installés"
        else
            warn "  ⚠ Aucun core libretro dans le rootfs"
        fi

        if [ -f "${VERIFY_MNT}/etc/init.d/S99retroarch" ]; then
            log "  ✅ Script de démarrage S99retroarch présent"
        else
            warn "  ⚠ Script S99retroarch absent"
        fi

        if [ -f "${VERIFY_MNT}/etc/retroarch/retroarch.cfg" ]; then
            log "  ✅ Configuration RetroArch présente"
        else
            warn "  ⚠ retroarch.cfg absent"
        fi

        sudo umount "${VERIFY_MNT}"

        if [ "${CHECK_OK}" = false ]; then
            rmdir "${VERIFY_MNT}" 2>/dev/null
            err "Certaines vérifications ont échoué !"
            exit 1
        fi
    else
        rmdir "${VERIFY_MNT}" 2>/dev/null
        err "Impossible de monter le squashfs généré !"
        exit 1
    fi

    rmdir "${VERIFY_MNT}" 2>/dev/null

    log ""
    log "=========================================="
    log "  IMAGE PARTITION 4 PRÊTE !"
    log "=========================================="
    log ""
    log "Fichier : ${ROOTFS_SQUASHFS}"
    log "Taille  : $(( NEW_SIZE / 1024 / 1024 )) Mo / 65 Mo max"
    log ""
    log "Pour flasher sur la carte SD (carte insérée, GameStick éteint) :"
    log "  sudo dd if=${ROOTFS_SQUASHFS} of=/dev/sdc4 bs=4M status=progress conv=fsync"
    log ""
    log "  Remplace sdc4 par le device de ta carte SD, ex :"
    log "  /dev/sdb4  si la carte est vue comme /dev/sdb"
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
        echo "  image       Génère l'image squashfs de la partition 4 (rootfs)"
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