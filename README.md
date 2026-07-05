# Jetson Orin NX Black-Screen Rescue — Postmortem & Reference Guide

**Device:** NVIDIA Jetson Orin NX on a Yahboom carrier board (clone of the
official P3768 devkit; unfused board)
**OS:** L4T / JetPack, kernel 5.15.148-tegra, upgraded 36.4.3 → 36.4.7 mid-incident
**Date of incident & rescue:** 2026-07-05
**Outcome:** ✅ Fully recovered, no data loss, no reflash of the SSD

This document is the distilled reference for the whole rescue. The blow-by-blow
working log is in `RESCUE_NOTES.md`; diagnostic evidence is in
`bootdiag*.log`, `repair_run*.log`, and `openclaw_audit.log` in this directory.

---

## TL;DR

An **unattended PackageKit upgrade** of ~190 packages (including the entire
L4T stack) was **interrupted by a power-off mid-transaction**, leaving the
Jetson's userspace half-configured and the machine apparently dead (black
screen). The rescue never reflashed the SSD. Instead, the SSD was attached to
an x86 Ubuntu host PC and repaired **file-level** with three fixes:

1. **Finish the interrupted dpkg transaction** inside a `qemu-user-static`
   aarch64 chroot.
2. **Point extlinux.conf at an initrd that actually contains NVMe drivers**
   (the upgrade had clobbered `/boot/initrd` with a minimal one that couldn't
   mount the root disk).
3. **Keep GPU/display modules out of the initrd** (an initramfs hook), because
   loading the Tegra DRM stack at ~2 s inside the initrd probe-fails
   permanently and results in a black screen with a fully booted system behind it.

Bonus finding: an **OpenClaw AI gateway** running on the device was a
**vendor leftover** from Yahboom's pre-sale demo (not an intrusion) and was
removed; the account password was changed since the vendor knew it.

---

## Symptoms (what the user saw)

- Power on → NVIDIA logo → **black screen**. No desktop, no text consoles
  (Ctrl+Alt+F1–F6 dead), at various stages no LAN presence either.
- The UEFI bootloader could see the SSD and listed it as a boot option.
- Depending on the phase of the rescue the failure looked different — this
  was actually **four distinct problems stacked on top of each other** (see below).

## The four stacked root causes

### 1. Interrupted unattended upgrade (the original sin)

At 10:04, PackageKit auto-started an upgrade of L4T 36.4.3 → 36.4.7 plus
~190 other packages. The machine went down at ~10:11 **mid-transaction**
(the apt `history.log` entry has no `End-Date`). Result: systemd, udev,
kmod, openssl, all 44 `nvidia-l4t-*` packages and more left
unpacked/unconfigured, plus pending ldconfig/initramfs triggers.

**Key insight:** the boot *files* were never corrupt. `/boot/Image` was a
valid kernel, the PARTUUID in `extlinux.conf` was correct, and `/var/log`
proved the machine had booted fine for days before. "Black screen" was
broken *userspace*, not a broken bootloader. **Diagnose before reflashing —
this saved all the data on the SSD.**

**Fix:** attach the SSD to the x86 host PC and finish the transaction in an
aarch64 chroot (`qemu-user-static` + binfmt). All 1120 .debs were still in
the SSD's `/var/cache/apt/archives`. Scripts: `repair_ssd_dpkg.sh` and
`repair_ssd_dpkg2.sh`. Essentials for chrooting into an L4T rootfs from a
foreign host:

- Bind-mount `/proc`, `/sys`, `/dev`.
- Add a `policy-rc.d` guard so postinst scripts can't start services.
- Create NVIDIA's `.nv-l4t-disable-boot-fw-update-in-preinstall` marker so
  the l4t debs don't try to touch boot firmware from the host.
- Then `dpkg --configure -a --force-confdef --force-confold`, and verify
  with `dpkg --audit` (must come back empty).

### 2. UEFI had marked the boot chain bad

After the crash and a few failed boots, UEFI set "OS chain A status" to bad,
which produced a *totally silent* boot (blinking cursor, zero kernel text) —
easy to misread as a deeper failure.

**Fix:** in the UEFI menu, set **"OS chain A status" back to NORMAL**.
Boot messages reappeared immediately. Check this first whenever a Jetson
boots to a blinking cursor with no text at all.

### 3. `/boot/initrd` had no NVMe drivers → `can't find PARTUUID=…`

The interrupted upgrade's `nvidia-l4t-initrd` package unpack **overwrote
`/boot/initrd` at 10:10:54** with the minimal devkit initrd, which contains
exactly two kernel modules (Realtek NIC drivers) — no `nvme.ko`,
`nvme-core.ko`, `pcie-tegra194.ko`, or `phy-tegra194-p2u.ko`. On this kernel
those are all **modules, not built-ins**, so the initrd literally could not
see the NVMe disk. The pre-crash initrd that used to boot the system was gone.

**Fix:** no rebuild needed — the dpkg repair had already generated a proper
initramfs-tools initrd (`/boot/initrd.img-5.15.148-tegra`, verified via
`lsinitramfs` to contain all four modules). Both `INITRD` lines in
`/boot/extlinux/extlinux.conf` were pointed at it (backup:
`extlinux.conf.pre-initrd-fix`).

### 4. The new initrd loaded the display stack too early → black screen #2

With NVMe fixed, the system booted fully — GNOME session, DHCP, sshd all
running — but the screen stayed black and VTs were dead. Comparing the
failing boot against pre-crash working boots in `kern.log.1`:

- **Working boots:** `host1x`/`tegra-drm` load ~6–8 s from the rootfs via
  udev → `/dev/dri/card0` appears → X's nvidia driver initializes and pulls
  in `nvidia-modeset`/`nvidia-drm` at ~13 s → display works.
- **Failing boot:** the initramfs-tools initrd (`MODULES=most`) had bundled
  the whole DRM/GPU stack. udev **inside the initrd** loaded it at ~2.1 s;
  VIC/NVDEC/NVENC/NVJPG/OFA probe-failed (`failed to init devfreq: -22`) in
  the barren initrd environment — a hard error with **no retry after
  pivot-root** → no `/dev/dri/card0` → Xorg `(EE) No devices detected` →
  black screen. The same missing devfreq/actmon sysfs also explained the
  `nvpower.service` / `nvpmodel` failures seen scrolling by.

**Fix:** initramfs hook `/etc/initramfs-tools/hooks/exclude-display-modules`
that prunes `kernel/drivers/gpu`, `updates/drivers/gpu`,
`updates/drivers/devfreq`, and `updates/nvhwpm.ko` from every initrd build,
then a rebuild via the qemu chroot (script: `repair_initrd_drm.sh`; backup:
`initrd.img-5.15.148-tegra.pre-drm-fix`). Because it's a hook, it survives
future kernel updates.

---

## Side quest: the OpenClaw vendor leftover

An OpenClaw AI gateway was found running (and crash-looping with WhatsApp
401 errors) on the Jetson. Audit (`openclaw_audit.log`) showed it was
installed 2026-03-18 by the **vendor** (hostname still `yahboom` at the
time) as a Chinese-ecosystem bot demo (Bailian/Qwen, QQ, Feishu, WhatsApp).
They sanitized it on Mar 26 before handover but forgot to disable the
service. **No intrusion indicators** — no foreign SSH keys, empty crontabs,
no logins after March.

Cleanup performed: `systemctl --user disable --now openclaw-gateway`,
`npm -g uninstall openclaw`, `rm -rf ~/.openclaw`, and **`passwd`** (the
vendor knew the shipped password — always change it on any pre-imaged
device). Vendor Wi-Fi profiles optionally removed.

**Lesson: treat any vendor-imaged device as untrusted until audited** —
check enabled services (system *and* `systemctl --user`), authorized_keys,
crontabs, and change all passwords.

---

## Diagnostic techniques that paid off

| Technique | What it proved |
|---|---|
| Read apt `history.log` / `term.log` on the mounted SSD | Found the interrupted transaction (missing `End-Date`) — the true root cause |
| `dpkg --audit` in chroot | Enumerated exactly what was half-installed |
| Unpack the initrd (`lsinitramfs`, cpio) and check `modules.builtin` | Proved the "can't find PARTUUID" error was missing NVMe *modules*, not a GPT/UUID problem |
| Diff failing boot vs. pre-crash boots in `kern.log.1`/`syslog.1` | Pinpointed the too-early DRM module load (2.1 s vs 6–13 s) |
| Read the journal/syslog from the SSD on the host PC | Showed the "dead" machine actually had a full GNOME session, DHCP lease, and sshd running |
| CapsLock LED toggle test | Cheap "is the kernel alive?" check on a black screen |
| File timestamps (`/boot/initrd` mtime 10:10:54) | Tied the clobbered initrd precisely to the crashed upgrade |

Also useful: the Jetson gets DHCP on `eno1` even with a black screen —
`ssh jetson@192.168.0.39` / `nknu.local`. Note the Yahboom carrier uses a
**Realtek** NIC, so don't filter LAN scans by NVIDIA MAC OUIs.

## Rescue infrastructure built along the way

- **Bootable USB rescue stick** (58 GB drive, L4T R36.5.0) flashed with
  `l4t_initrd_flash.sh -c tools/kernel_flash/flash_l4t_external.xml
  --external-device sdd1 --direct sdd jetson-orin-nano-devkit external`
  with the board in Force Recovery Mode. Kept as a permanent rescue tool.
  - Gotcha: the flash target for this board on R36.5.0 is
    `jetson-orin-nano-devkit` (covers Orin NX too); `jetson-orin-nx-devkit`
    does not exist.
  - Gotcha: **disable GNOME automount on the host first**
    (`gsettings set org.gnome.desktop.media-handling automount false`, same
    for `automount-open`) or it races the flash tool and fails with
    "partition in use". Re-enable when done.
  - The "Please install the Secureboot package" warning is harmless on
    unfused boards.
- **qemu-user-static aarch64 chroot** on the x86 host — lets you run dpkg,
  update-initramfs, etc. directly on the ARM64 rootfs. Slow but reliable.
- All diagnostic/repair scripts in this directory are re-runnable references:
  `bootdiag*.sh`, `repair_ssd_dpkg*.sh`, `repair_initrd_drm.sh`,
  `openclaw_audit.sh`.

---

## Standing maintenance rules (post-rescue)

1. **Unattended upgrades are disabled on the Jetson** — the entire incident
   started with PackageKit auto-upgrading L4T. Apply JetPack/L4T updates
   manually, at a time when a power loss won't hurt, and let them finish.
2. **After any future L4T/JetPack upgrade, re-check
   `/boot/extlinux/extlinux.conf`:** the `nvidia-l4t-kernel` postinst
   *rewrites* it. Verify `DEFAULT` is still `JetsonIO` (carries the
   dual-IMX219 camera FDT/overlay) and `INITRD` still points at
   `/boot/initrd.img-5.15.148-tegra` (or that `/boot/initrd` finally has
   NVMe modules). The `exclude-display-modules` hook itself survives updates.
3. **Keep the backups on the SSD:** `extlinux.conf.pre-initrd-fix`,
   `initrd.img-5.15.148-tegra.pre-drm-fix`, `initrd.img-*.pre-drm-fix`.
4. **Keep the USB rescue stick.** It boots the Jetson independently of the
   SSD and doubles as a known-good file reference (same BSP).
5. If a future boot dies inside the initrd, the initramfs-tools initrd drops
   to a busybox `(initramfs)` shell — `cat /proc/modules`, `ls /dev/nvme*`,
   `dmesg | grep -iE 'pcie|nvme'` will show what's missing. (The stock L4T
   initrd does *not* offer a shell.)
6. Fallback of last resort: the original Yahboom Orin NX image (Frank has
   the ISO) — contains the factory initrd and full carrier-board setup.
   Never needed during this rescue.

## Timeline (2026-07-05)

| Time | Event |
|---|---|
| 10:04 | PackageKit auto-starts L4T 36.4.3→36.4.7 upgrade (~190 pkgs) |
| ~10:11 | Machine goes down mid-transaction; `/boot/initrd` already clobbered (10:10:54) |
| afternoon | USB rescue stick flashed; SSD attached to host PC; root cause found in apt logs |
| ~17:34 | dpkg repair runs 1 & 2 complete in qemu chroot; `dpkg --audit` clean |
| evening | Boot test #1 fails: `can't find PARTUUID` → initrd diagnosis → extlinux.conf INITRD fix |
| night | Boot test #2: system boots but black screen → journal analysis from SSD |
| ~20:00 | Early-DRM-load root cause confirmed; `repair_initrd_drm.sh` applied & verified |
| 20:16 | OpenClaw audited: vendor leftover, cleanup plan prepared |
| after | Final boot: **display works, system fully recovered**; OpenClaw removed, password changed |
