#!/bin/bash
# bootdiag4.sh — identify what triggers nvidia-modeset load at ~13s in a
# working boot, and why nvpower failed in the failing boot.
# Usage: sudo bash ~/jetson_rescue/bootdiag4.sh
set -u
M=/mnt/jetson-ssd
OUT=/home/frank/jetson_rescue/bootdiag4.log

{
echo "=== bootdiag4 $(date -Is) ==="

echo; echo "=== WORKING boot (Jul 4 19:51): 80 lines BEFORE + 20 AFTER 'nvidia-modeset: Loading' ==="
LN=$(grep -an "Jul  4 19:51:2[0-9].*nvidia-modeset: Loading" "$M/var/log/syslog.1" | head -1 | cut -d: -f1)
if [ -n "$LN" ]; then
  START=$((LN>80 ? LN-80 : 1))
  sed -n "${START},$((LN+20))p" "$M/var/log/syslog.1"
else
  echo "marker not found in syslog.1"
fi

echo; echo "=== FAILING boot: systemd unit activity 19:27:57-19:28:30 ==="
grep -aE "^Jul  5 19:2(7:5[7-9]|8:[0-3])" "$M/var/log/syslog" | grep -aE "systemd\[1\]: (Starting|Started|Finished|Failed|Dependency)" | head -120

echo; echo "=== FAILING boot: nvpower / nvpmodel / nvphs details ==="
grep -a "^Jul  5 19:" "$M/var/log/syslog" | grep -aiE "nvpower|nvpmodel|nvphs" | head -60

echo; echo "=== FAILING boot: any modprobe/insmod/udevd errors whole window ==="
grep -aE "^Jul  5 19:(2[7-9]|3[0-5])" "$M/var/log/syslog" | grep -aiE "modprobe|insmod|Invalid module|version magic|Unknown symbol|disagrees" | head -40

echo; echo "=== done ==="
} > "$OUT" 2>&1
chown frank:frank "$OUT" 2>/dev/null
echo "Report written to $OUT"
