#!/bin/bash
# bootdiag2.sh — display-focused log dump from the mounted Jetson SSD.
# Assumes SSD rootfs is already mounted at /mnt/jetson-ssd (bootdiag.sh left it there).
# Usage: sudo bash ~/jetson_rescue/bootdiag2.sh
set -u
M=/mnt/jetson-ssd
OUT=/home/frank/jetson_rescue/bootdiag2.log

{
echo "=== bootdiag2 $(date -Is) ==="

echo; echo "=== dmesg of LAST boot (19:28): drm/nvidia/nvgpu/hdmi/dp/edid/tegra display lines ==="
grep -aiE 'drm|nvgpu|nvdisplay|nvidia|hdmi|\bdp\b|edid|dce|tegra-dc|display|fb0' "$M/var/log/dmesg" | head -n 200

echo; echo "=== dmesg of LAST boot: module load errors / taint / failures ==="
grep -aiE 'fail|error|taint|firmware|segfault' "$M/var/log/dmesg" | grep -aivE 'RAS.*error.*correct|no error' | head -n 80

echo; echo "=== syslog: boot window 19:27-19:34 — gdm/Xorg/nvidia/drm/session lines ==="
grep -aE '^Jul  5 19:(2[7-9]|3[0-4])' "$M/var/log/syslog" | grep -aiE 'gdm|xorg|nvidia|drm|nvgpu|display|session|seat|logind|multi-user|graphical' | head -n 150

echo; echo "=== syslog: boot window — all systemd Failed/Dependency lines ==="
grep -aE '^Jul  5 19:(2[7-9]|3[0-9])' "$M/var/log/syslog" | grep -aE 'Failed|failed|Dependency' | head -n 80

echo; echo "=== gdm3 greeter logs ==="
ls -la "$M/var/log/gdm3/" 2>&1
for f in "$M"/var/log/gdm3/*; do
  [ -f "$f" ] && { echo "--- $f (tail) ---"; tail -n 60 "$f"; }
done

echo; echo "=== Xorg log (gdm) ==="
for f in "$M"/var/log/Xorg.*.log; do
  [ -f "$f" ] && { echo "--- $f: (EE)/(WW)/NVIDIA lines ---"; grep -aE '\(EE\)|\(WW\)|NVIDIA' "$f" | head -n 80; }
done

echo; echo "=== Xorg log (user session, autologin user jetson) ==="
for f in "$M"/home/jetson/.local/share/xorg/Xorg.*.log; do
  [ -f "$f" ] && { echo "--- $f: (EE)/(WW)/NVIDIA/output lines ---"; grep -aE '\(EE\)|\(WW\)|NVIDIA|connected|EDID|modes' "$f" | head -n 120; }
done

echo; echo "=== auth.log tail (PAM health check) ==="
tail -n 40 "$M/var/log/auth.log"

echo; echo "=== display module files present? ==="
ls -la "$M/lib/modules/5.15.148-tegra/updates/drivers/gpu/" 2>/dev/null || \
  find "$M/lib/modules/5.15.148-tegra" -name 'nvidia-drm*' -o -name 'nvidia-modeset*' -o -name 'nv-drm*' 2>/dev/null | head
echo "--- modules.dep entries ---"
grep -aE 'nvidia-drm|nvidia-modeset|nvgpu' "$M/lib/modules/5.15.148-tegra/modules.dep" | head -n 10

echo; echo "=== done ==="
} > "$OUT" 2>&1
chown frank:frank "$OUT" 2>/dev/null
echo "Report written to $OUT"
