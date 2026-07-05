#!/bin/bash
# Follow-up to repair_ssd_dpkg.sh: unpack the matching openssh 0.15 debs
# so openssh-sftp-server's dependency is satisfied, then finish configure.
# Run as: sudo bash repair_ssd_dpkg2.sh
set -u
M=/mnt/jetson-ssd

findmnt "$M" >/dev/null || { echo "ERROR: $M is not mounted"; exit 1; }

cleanup() {
  rm -f "$M/usr/sbin/policy-rc.d"
  rm -f "$M/opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall"
  rmdir "$M/opt/nvidia/l4t-packages" 2>/dev/null
  umount -R "$M/dev" 2>/dev/null
  umount -R "$M/sys" 2>/dev/null
  umount "$M/proc" 2>/dev/null
}
trap cleanup EXIT

printf '#!/bin/sh\nexit 101\n' > "$M/usr/sbin/policy-rc.d"
chmod +x "$M/usr/sbin/policy-rc.d"
mkdir -p "$M/opt/nvidia/l4t-packages"
touch "$M/opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall"

mountpoint -q "$M/proc" || mount -t proc proc "$M/proc"
mountpoint -q "$M/sys"  || { mount --rbind /sys "$M/sys"; mount --make-rslave "$M/sys"; }
mountpoint -q "$M/dev"  || { mount --rbind /dev "$M/dev"; mount --make-rslave "$M/dev"; }

CH="chroot $M /usr/bin/env PATH=/usr/sbin:/usr/bin:/sbin:/bin LANG=C DEBIAN_FRONTEND=noninteractive"

echo "=== Unpack openssh-client + openssh-server 0.15 from apt cache ==="
$CH dpkg --unpack \
  "/var/cache/apt/archives/openssh-client_1%3a8.9p1-3ubuntu0.15_arm64.deb" \
  "/var/cache/apt/archives/openssh-server_1%3a8.9p1-3ubuntu0.15_arm64.deb"

echo "=== Configure everything remaining ==="
$CH dpkg --configure -a --force-confdef --force-confold
rc=$?
echo "=== dpkg --configure -a exit code: $rc ==="

echo "=== Audit (should print nothing) ==="
$CH dpkg --audit

exit $rc
