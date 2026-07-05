#!/bin/bash
# Finish the interrupted 2026-07-05 10:04 PackageKit upgrade inside the
# Jetson SSD rootfs (mounted at /mnt/jetson-ssd), via qemu-user-static chroot.
# Run as: sudo bash repair_ssd_dpkg.sh
set -u
M=/mnt/jetson-ssd

findmnt "$M" >/dev/null || { echo "ERROR: $M is not mounted"; exit 1; }
[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || { echo "ERROR: aarch64 binfmt not registered"; exit 1; }

cleanup() {
  rm -f "$M/usr/sbin/policy-rc.d"
  rm -f "$M/opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall"
  rmdir "$M/opt/nvidia/l4t-packages" 2>/dev/null
  umount -R "$M/dev" 2>/dev/null
  umount -R "$M/sys" 2>/dev/null
  umount "$M/proc" 2>/dev/null
}
trap cleanup EXIT

# Never let maintainer scripts start services in the chroot
printf '#!/bin/sh\nexit 101\n' > "$M/usr/sbin/policy-rc.d"
chmod +x "$M/usr/sbin/policy-rc.d"

# NVIDIA's documented marker: tells l4t debs "not on target, do not touch boot firmware"
mkdir -p "$M/opt/nvidia/l4t-packages"
touch "$M/opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall"

mountpoint -q "$M/proc" || mount -t proc proc "$M/proc"
mountpoint -q "$M/sys"  || { mount --rbind /sys "$M/sys"; mount --make-rslave "$M/sys"; }
mountpoint -q "$M/dev"  || { mount --rbind /dev "$M/dev"; mount --make-rslave "$M/dev"; }

export DEBIAN_FRONTEND=noninteractive
CH="chroot $M /usr/bin/env PATH=/usr/sbin:/usr/bin:/sbin:/bin LANG=C DEBIAN_FRONTEND=noninteractive"

echo "=== Step 1: re-unpack half-installed samba-libs from apt cache ==="
$CH dpkg --unpack "/var/cache/apt/archives/samba-libs_2%3a4.15.13+dfsg-0ubuntu1.12_arm64.deb"

echo "=== Step 2: configure all unpacked packages (this takes a while under qemu) ==="
$CH dpkg --configure -a --force-confdef --force-confold
rc=$?
echo "=== dpkg --configure -a exit code: $rc ==="

echo "=== Step 3: remaining non-installed packages (should be empty) ==="
$CH dpkg --audit

exit $rc
