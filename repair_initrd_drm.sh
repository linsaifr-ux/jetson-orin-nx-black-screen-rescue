#!/bin/bash
# repair_initrd_drm.sh — fix the black-screen root cause:
# the initramfs-tools initrd (MODULES=most) contains the Tegra display/DRM
# stack; udev inside the initrd loads it at ~2s, the VIC/NVDEC/NVENC/NVJPG/OFA
# engines probe-fail (devfreq -22) in the barren initrd environment and never
# retry, so tegra-drm never creates /dev/dri/card0, X finds no device, and
# nvidia-modeset/nvidia-drm are never loaded -> black screen.
# Fix: initramfs-tools hook that prunes display modules from the initrd, then
# rebuild the initrd in the aarch64 chroot. Modules then load post-boot from
# the real rootfs via udev, exactly like every pre-crash working boot.
# Usage: sudo bash ~/jetson_rescue/repair_initrd_drm.sh
set -eu
M=/mnt/jetson-ssd
KVER=5.15.148-tegra

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
mountpoint -q "$M" || { echo "$M not mounted"; exit 1; }
[ -f "$M/boot/initrd.img-$KVER" ] || { echo "initrd.img-$KVER not found"; exit 1; }

echo "== 1. Install initramfs hook to exclude display modules =="
cat > "$M/etc/initramfs-tools/hooks/exclude-display-modules" <<'EOF'
#!/bin/sh
# Keep Tegra display/DRM/host1x modules OUT of the initrd.
# Loaded from the initrd (MODULES=most), the host1x engine drivers
# (tegra-vic/nvdec/nvenc/nvjpg/ofa in tegra-drm.ko) probe-fail with
# "failed to init devfreq: -22" and never retry, so /dev/dri/card0 never
# appears and the desktop stays black. Post-boot loading from the real
# rootfs works fine (this is what every working boot did).
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "${1:-}" in
  prereqs) prereqs; exit 0;;
esac
for d in "$DESTDIR"/usr/lib/modules/*; do
  rm -rf "$d/kernel/drivers/gpu" \
         "$d/updates/drivers/gpu" \
         "$d/updates/drivers/devfreq" \
         "$d/updates/nvhwpm.ko" 2>/dev/null || true
done
exit 0
EOF
chmod 755 "$M/etc/initramfs-tools/hooks/exclude-display-modules"

echo "== 2. Backup current initrd =="
cp -a "$M/boot/initrd.img-$KVER" "$M/boot/initrd.img-$KVER.pre-drm-fix"

echo "== 3. Rebuild initrd in aarch64 chroot (slow under qemu, be patient) =="
for fs in proc sys dev dev/pts; do
  mountpoint -q "$M/$fs" || mount --bind "/$fs" "$M/$fs"
done
cleanup() {
  for fs in dev/pts dev sys proc; do
    mountpoint -q "$M/$fs" && umount "$M/$fs" || true
  done
}
trap cleanup EXIT
chroot "$M" update-initramfs -u -k "$KVER"
cleanup
trap - EXIT

echo "== 4. Verify =="
BAD=$(lsinitramfs "$M/boot/initrd.img-$KVER" | grep -cE "drivers/gpu/|host1x|tegra-drm|nvhwpm" || true)
NVME=$(lsinitramfs "$M/boot/initrd.img-$KVER" | grep -cE "nvme.*\.ko" || true)
echo "display/gpu module files left in initrd: $BAD (want 0)"
echo "nvme module files in initrd:            $NVME (want >=2)"
echo "-- extlinux INITRD lines:"
grep -n "INITRD" "$M/boot/extlinux/extlinux.conf"
ls -la "$M/boot/initrd.img-$KVER"*

if [ "$BAD" = "0" ] && [ "$NVME" -ge 2 ]; then
  echo "== 5. All good — unmounting SSD =="
  sync
  umount "$M" && echo "SSD unmounted cleanly. Move it back to the Jetson and boot."
else
  echo "!! Verification FAILED — SSD left mounted at $M for inspection. Do not boot yet."
  exit 1
fi
