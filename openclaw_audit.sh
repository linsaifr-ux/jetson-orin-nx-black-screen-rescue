#!/bin/bash
# openclaw_audit.sh — read-only investigation of the unexpected OpenClaw
# install on the Jetson SSD. Mounts RO, writes report, leaves SSD mounted RO.
# Usage: sudo bash ~/jetson_rescue/openclaw_audit.sh [/dev/nvme1n1p1]
set -u
DEV="${1:-/dev/nvme1n1p1}"
M=/mnt/jetson-ssd
OUT=/home/frank/jetson_rescue/openclaw_audit.log
H="$M/home/jetson"

mkdir -p "$M"
mountpoint -q "$M" || mount -o ro "$DEV" "$M" || { echo "mount failed"; exit 1; }

{
echo "=== openclaw audit $(date -Is) (SSD mounted read-only) ==="

echo; echo "=== 1. WHEN was it installed (timestamps) ==="
stat -c '%w  birth | %y  mtime | %n' \
  "$H/.npm-global/lib/node_modules/openclaw" \
  "$H/.npm-global/bin/openclaw" \
  "$H/.openclaw" \
  "$H/.openclaw/openclaw.json" \
  "$H/.openclaw/identity" \
  "$H/.config/systemd/user/openclaw-gateway.service" \
  "$H/.config/systemd/user/default.target.wants/openclaw-gateway.service" 2>/dev/null

echo; echo "=== 2. npm activity logs (dates + openclaw mentions) ==="
ls -la --time-style=full-iso "$H/.npm/_logs/" 2>/dev/null | tail -15
grep -l "openclaw" "$H"/.npm/_logs/*.log 2>/dev/null | head -5

echo; echo "=== 3. OpenClaw's own metadata ==="
echo "-- identity:"
ls -la "$H/.openclaw/identity/" 2>/dev/null
for f in "$H"/.openclaw/identity/*.json; do [ -f "$f" ] && { echo "-- $f:"; cat "$f"; echo; }; done
echo "-- devices:"
ls -la "$H/.openclaw/devices/" 2>/dev/null
echo "-- openclaw.json (secrets redacted):"
sed -E 's/("(token|apiKey|api_key|secret|password|key|credential)[^"]*"\s*:\s*")[^"]+/\1REDACTED/gi' \
  "$H/.openclaw/openclaw.json" 2>/dev/null
echo "-- credentials dir (names only):"
ls -laR "$H/.openclaw/credentials/" 2>/dev/null | head -30
echo "-- cron jobs:"
ls -la "$H/.openclaw/cron/" 2>/dev/null
for f in "$H"/.openclaw/cron/*.json; do [ -f "$f" ] && { echo "-- $f:"; head -c 2000 "$f"; echo; }; done
echo "-- oldest and newest logs:"
ls -la --time-style=full-iso "$H/.openclaw/logs/" 2>/dev/null | head -8
ls -la --time-style=full-iso "$H/.openclaw/logs/" 2>/dev/null | tail -8
echo "-- setup.sh / reset-memory.sh:"
head -c 1500 "$H/.openclaw/setup.sh" 2>/dev/null

echo; echo "=== 4. SSH login history (who got in, from where) ==="
for f in "$M"/var/log/auth.log "$M"/var/log/auth.log.1; do
  [ -f "$f" ] && { echo "-- $f:"; grep -aE "Accepted (password|publickey)|session opened for user (jetson|root) by .*uid=0.*sshd|sshd.*Failed password" "$f" | tail -30; }
done
for f in "$M"/var/log/auth.log.*.gz; do
  [ -f "$f" ] && { echo "-- $f:"; zcat "$f" | grep -aE "Accepted (password|publickey)" | tail -20; }
done
echo "-- wtmp (last logins):"
last -f "$M/var/log/wtmp" 2>/dev/null | head -20

echo; echo "=== 5. authorized_keys (unexpected SSH keys?) ==="
for f in "$H/.ssh/authorized_keys" "$M/root/.ssh/authorized_keys"; do
  [ -f "$f" ] && { echo "-- $f:"; cat "$f"; }
done

echo; echo "=== 6. system crontabs ==="
ls -la "$M/var/spool/cron/crontabs/" 2>/dev/null
for f in "$M"/var/spool/cron/crontabs/*; do [ -f "$f" ] && { echo "-- $f:"; cat "$f"; }; done

echo; echo "=== 7. bash history tail (any hint who worked here) ==="
tail -40 "$H/.bash_history" 2>/dev/null

echo; echo "=== done — SSD left mounted READ-ONLY at $M ==="
} > "$OUT" 2>&1
chown frank:frank "$OUT" 2>/dev/null
echo "Report written to $OUT (SSD mounted read-only)"
