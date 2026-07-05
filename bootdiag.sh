#!/bin/bash
# Collect boot-failure evidence from the Jetson SSD on the host PC.
# Usage: sudo bash ~/jetson_rescue/bootdiag.sh [ssd-partition, default /dev/nvme1n1p1]
# Writes a frank-readable report to ~/jetson_rescue/bootdiag.log
set -u
PART="${1:-/dev/nvme1n1p1}"
MNT=/mnt/jetson-ssd
OUT=/home/frank/jetson_rescue/bootdiag.log
exec > >(tee "$OUT") 2>&1

echo "=== bootdiag $(date -Is) — partition $PART ==="
mkdir -p "$MNT"
mountpoint -q "$MNT" || mount "$PART" "$MNT" || { echo "MOUNT FAILED"; exit 1; }

echo; echo "=== extlinux.conf (as booted) ==="
cat "$MNT/boot/extlinux/extlinux.conf"

echo; echo "=== journal: list of boots recorded ==="
journalctl -D "$MNT/var/log/journal" --list-boots 2>&1 | tail -20

echo; echo "=== journal: LAST boot, last 150 lines ==="
journalctl -D "$MNT/var/log/journal" -b -0 --no-pager 2>&1 | tail -150

echo; echo "=== journal: LAST boot, errors/warnings (priority<=3) ==="
journalctl -D "$MNT/var/log/journal" -b -0 -p 3 --no-pager 2>&1 | tail -80

echo; echo "=== journal: LAST boot, gdm/nvgpu/drm/nvidia lines ==="
journalctl -D "$MNT/var/log/journal" -b -0 --no-pager 2>&1 \
  | grep -iE 'gdm|nvgpu|drm|nvidia|panic|oops|segfault|Failed to start' | tail -80

echo; echo "=== syslog tail (fallback if journal not persistent) ==="
tail -100 "$MNT/var/log/syslog" 2>/dev/null || echo "(no syslog)"

echo; echo "=== nvidia update-engine / bootloader update logs, if any ==="
ls -la "$MNT/var/log/" | head -40
tail -30 "$MNT/var/log/nv_update_engine.log" 2>/dev/null || true

chown frank:frank "$OUT" 2>/dev/null || chown "$(stat -c %U:%G /home/frank)" "$OUT"
echo; echo "=== done — report in $OUT (SSD left mounted at $MNT) ==="
