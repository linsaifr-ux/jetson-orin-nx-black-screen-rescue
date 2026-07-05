#!/bin/bash
# bootdiag3.sh — compare NVIDIA display-driver kernel messages:
# failing boot (19:27 today) vs a pre-crash working boot, from SSD logs.
# Usage: sudo bash ~/jetson_rescue/bootdiag3.sh
set -u
M=/mnt/jetson-ssd
OUT=/home/frank/jetson_rescue/bootdiag3.log
PAT='NVRM|nvidia|nvdisplay|nv_platform|modeset|drm|dce|tsec|host1x|hdmi|edid|dp83|sor|fb0|framebuffer'

{
echo "=== bootdiag3 $(date -Is) ==="

echo; echo "=== FAILING boot (Jul 5 19:27+): ALL kernel lines matching display pattern ==="
grep -a "^Jul  5 19:2[7-9].*kernel:" "$M/var/log/syslog" | grep -aiE "$PAT"
echo "---(later, 19:3x-19:4x)---"
grep -a "^Jul  5 19:[34].*kernel:" "$M/var/log/syslog" | grep -aiE "$PAT" | head -40

echo; echo "=== FAILING boot: udev / systemd-modules-load / modprobe problems ==="
grep -a "^Jul  5 19:2[7-9]" "$M/var/log/syslog" | grep -aiE 'systemd-modules-load|systemd-udevd|modprobe|Failed to insert|could not insert|Direct firmware load' | head -60

echo; echo "=== FAILING boot: count of all kernel lines (sanity) ==="
grep -ac "^Jul  5 19:2[7-9].*kernel:" "$M/var/log/syslog"

echo; echo "=== available older logs ==="
ls -la "$M"/var/log/syslog* "$M"/var/log/kern.log* 2>/dev/null

echo; echo "=== WORKING boot reference: kern.log lines matching display pattern (last working boot before Jul 5 10:11) ==="
for f in "$M/var/log/kern.log.1" "$M/var/log/kern.log"; do
  [ -f "$f" ] || continue
  echo "--- $f ---"
  grep -aiE "$PAT" "$f" | grep -av "19:2[7-9]\|19:[34]" | tail -n 120
done
# fallback: compressed
if [ -f "$M/var/log/kern.log.2.gz" ]; then
  echo "--- kern.log.2.gz (tail) ---"
  zcat "$M/var/log/kern.log.2.gz" | grep -aiE "$PAT" | tail -n 60
fi

echo; echo "=== WORKING boot: what loaded nvidia-drm (look for '[drm] [nvidia-drm]' init lines + preceding context) ==="
for f in "$M/var/log/kern.log.1"; do
  [ -f "$f" ] || continue
  grep -an "nvidia-drm\|nvidia_drm" "$f" | tail -n 20
done

echo; echo "=== NETWORK: failing boot — NetworkManager/dhcp/link/IP lines ==="
grep -a "^Jul  5 19:" "$M/var/log/syslog" | grep -aiE 'NetworkManager|dhcp|eth0|enP8|wlan|wlP1|address .*192\.168|address .*10\.|carrier|link becomes|avahi.*(joining|Registering|withdraw)' | grep -aiv "docker\|veth" | head -100

echo; echo "=== NETWORK: interfaces persistent names / MACs seen by udev ==="
grep -a "^Jul  5 19:" "$M/var/log/syslog" | grep -aiE 'renamed from|r8168|r8126|rtl|realtek' | head -20

echo; echo "=== done ==="
} > "$OUT" 2>&1
chown frank:frank "$OUT" 2>/dev/null
echo "Report written to $OUT"
