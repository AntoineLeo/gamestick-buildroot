#!/bin/sh
# Diagnostic RetroArch — capture tous les indices sur la segfault et le driver vidéo
CFG=/mnt/sdcard/retroarch.cfg
LOG=/mnt/sdcard/logs/diag.log
mkdir -p /mnt/sdcard/logs
exec > "$LOG" 2>&1

echo "========================================"
echo "1. Noeuds /dev"
echo "========================================"
ls -la /dev/mali* 2>&1
ls -la /dev/dri/ 2>&1

echo ""
echo "========================================"
echo "2. Bibliotheques Mali dans /usr/lib"
echo "========================================"
ls -la /usr/lib/libmali* /usr/lib/libEGL* /usr/lib/libGLES* /usr/lib/libgbm* 2>&1

echo ""
echo "========================================"
echo "3. Chargement bibliotheques (LD_DEBUG=libs)"
echo "========================================"
LD_DEBUG=libs /usr/bin/retroarch --verbose --config "$CFG" 2>&1 | head -100

echo ""
echo "========================================"
echo "4. strace — acces fichiers (mali/EGL/dri)"
echo "========================================"
strace -e trace=openat,access,stat -s 256 \
    /usr/bin/retroarch --verbose --config "$CFG" 2>&1 | \
    grep -E "mali|EGL|gbm|dri|GLES|opengl|libGL" | head -50

echo ""
echo "========================================"
echo "5. strace — signal de crash"
echo "========================================"
strace -e trace=signal -s 512 \
    /usr/bin/retroarch --verbose --config "$CFG" 2>&1 | tail -30

echo ""
echo "========================================"
echo "6. Core dump"
echo "========================================"
ulimit -c unlimited
cd /mnt/sdcard/logs
/usr/bin/retroarch --verbose --config "$CFG" 2>&1 | head -50
if [ -f core ]; then
    echo "Core dump cree : $(ls -lh core)"
else
    echo "Pas de core dump genere"
fi

echo ""
echo "Diagnostic termine. Log : $LOG"
