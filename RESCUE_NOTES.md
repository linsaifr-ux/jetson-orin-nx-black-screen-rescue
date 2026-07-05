# Jetson Orin NX (Yahboom carrier) Rescue — Progress Notes

## Goal
The Jetson's internal NVMe SSD has broken boot files (bootloader sees the SSD,
lists it as a boot option, but boot results in a black screen — likely a
missing/corrupt kernel, initrd, or bad `extlinux.conf`, not a dead drive).
Plan: flash a bootable external USB drive so the Jetson can boot independent
of the SSD, then use that known-good environment to repair the SSD's boot
files without wiping its data.

## Hardware
- Board: Yahboom carrier + Jetson Orin NX module (clones NVIDIA's P3768 devkit
  design — same flash target name as the official devkit applies).
- Board is **unfused** (no PKC/SBK production fuses) — confirmed by user, so
  no secure-boot key files are needed.
- Target USB drive: `/dev/sdd` on this host PC — a 58.2GB drive, originally a
  vfat "UBUNTU 24_0" live USB, now repartitioned as the Jetson's L4T rootfs.

## Key gotchas discovered (don't re-waste time on these)
1. **Board name**: `jetson-orin-nx-devkit` does **not** exist in this L4T
   release (R36.5.0). The correct target name for the devkit carrier (and
   Yahboom's clone) covering both Orin Nano and Orin NX SKUs is
   **`jetson-orin-nano-devkit`** — the actual module variant is
   auto-detected from the module's board-ID/fuse info at flash time.
2. **"Please install the Secureboot package..." warning**: harmless/non-fatal.
   `bootloader/odmsign.func` already exists in this BSP, so secure-boot
   support is already present; this warning only matters for fused boards
   anyway (not applicable here).
3. **Physical connection required**: the initrd-flash workflow needs the
   Jetson module physically connected via USB and in **Force Recovery Mode**
   (REC pins jumpered/shorted, then power applied while shorted, release
   after ~2s) — confirmed working, showed up as `ID 0955:7323 NVIDIA Corp.
   APX` in `lsusb`.
4. **GNOME automount races the flash tool**: as soon as the flash tool
   creates a filesystem on `/dev/sdd1`, GNOME's automount (GVFS/udisks2)
   grabs it and mounts it, causing the flash tool to fail with
   `錯誤: 正在使用 /dev/sdd 上的分割區` ("partition in use"). Fixed by disabling
   automount before flashing:
   ```
   gsettings set org.gnome.desktop.media-handling automount false
   gsettings set org.gnome.desktop.media-handling automount-open false
   ```
   (Currently still disabled on this machine — may want to re-enable later
   with `automount true` / `automount-open true` once done with this project.)
5. `sudo` in this environment needs an interactive terminal for the password
   — Bash tool calls to `sudo ...` fail with "a terminal is required". Any
   sudo command must be run by the user directly (or via the `!` prefix in
   the Claude Code prompt, which runs in the real terminal session).

## Status: DONE — USB flash succeeded
Command used (from `~/jetson_rescue/Linux_for_Tegra`):
```
sudo ./tools/kernel_flash/l4t_initrd_flash.sh \
  -c tools/kernel_flash/flash_l4t_external.xml \
  --external-device sdd1 --direct sdd \
  jetson-orin-nano-devkit external
```
Log confirms success: `initrdlog/flash_1-3_0_20260705-142215.log` —
"Successfully flashed the external device." / "Flashing success".
(A harmless GPT-size note also appeared: the partition layout XML assumed a
slightly smaller device than actual; the tool auto-fixed the GPT. Not an
error.)

## Next steps (pick up here after reboot)
Two possible paths to fix the SSD's boot files — user was mid-decision on
approach 2 when this PC needed a reboot:

### Approach A: Boot the Jetson itself from the USB drive
1. Power off Jetson, remove REC jumper, unplug from this PC.
2. Plug the flashed USB drive into the Jetson's own USB port, power on
   normally — should boot Ubuntu standalone from USB (no recovery mode, no
   host PC needed).
3. Once booted, on the *Jetson's own* terminal:
   ```
   lsblk                                   # find nvme0n1 + partitions
   sudo mkdir -p /mnt/ssd
   sudo mount /dev/nvme0n1p1 /mnt/ssd       # or fsck first if mount fails
   cat /mnt/ssd/boot/extlinux/extlinux.conf # compare vs /boot/extlinux/extlinux.conf
   ls -la /mnt/ssd/boot/                    # look for missing/0-byte Image or initrd
   blkid /dev/nvme0n1p1                     # check UUID matches extlinux.conf's root=
   ```
4. Fix whatever's broken: bad `extlinux.conf` entries, or copy a known-good
   `Image`/`initrd` from the working USB `/boot` into `/mnt/ssd/boot/`
   (safe since same BSP/kernel version on both).

### Approach B: Repair the SSD directly from this host PC (was in progress)
Since this is pure file-level repair (mount + copy/edit files on ext4), it
doesn't require running on the Jetson's ARM hardware at all — this x86 PC
can do it directly, which avoids needing to physically re-boot the Jetson
for this step.
1. **Reconnect the USB boot drive to this PC.**
2. **Connect the Jetson's NVMe SSD to this PC** — needs an M.2-to-USB
   enclosure/adapter (or an internal M.2 slot if opening the case).
3. Run `lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT,FSTYPE` to identify both
   devices by their new names (do NOT assume `sdd`/`nvme0n1` — those may
   shift; this PC's own OS drive is already `nvme0n1`, so the Jetson SSD
   will likely enumerate as something else, maybe another `nvme` node or a
   USB-attached `sd*` device via the enclosure).
4. Mount both:
   ```
   sudo mkdir -p /mnt/jetson-usb /mnt/jetson-ssd
   sudo mount /dev/sdd1 /mnt/jetson-usb        # adjust device name as needed
   sudo mount /dev/<ssd-partition> /mnt/jetson-ssd
   ```
5. Compare `/mnt/jetson-usb/boot/extlinux/extlinux.conf` against
   `/mnt/jetson-ssd/boot/extlinux/extlinux.conf`, and check
   `/mnt/jetson-ssd/boot/` for missing/corrupt `Image`/`initrd`.
6. Copy/fix files as needed (`cp -a` to preserve permissions/ownership).
7. Unmount cleanly, disconnect, reinstall SSD into Jetson, test boot.

**Important**: don't blindly `dd`/reflash the SSD — the goal is to preserve
its existing data, only touching the specific broken boot files. A full
reflash (`l4t_initrd_flash.sh --external-device nvme0n1 --direct nvme0n1
...`) is the fallback **only** if the filesystem itself turns out to be
unmountable/corrupted beyond repair, and it will erase all data on the SSD.

## Where things stand right now
Was about to reconnect both drives to this host PC for Approach B when the
user needed to reboot the PC. Nothing destructive is in progress — safe to
reboot. After reboot, resume at "Next steps" above (user was leaning toward
Approach B).

## 2026-07-05 (after PC reboot): ROOT CAUSE FOUND — interrupted apt upgrade
Approach B in progress. Both drives attached to host PC:
- USB boot drive = `sdd` (rootfs `sdd1`)
- Jetson SSD = `nvme1n1` (rootfs `nvme1n1p1`, mounted at /mnt/jetson-ssd;
  USB at /mnt/jetson-usb)

**The SSD's boot files are NOT corrupt.** Diagnosis from the SSD itself:
- `/boot/Image` is a valid ARM64 kernel (5.15.148-tegra, L4T 36.4.7 build),
  initrd gzip-intact and contains matching 5.15.148 modules, extlinux.conf's
  `root=PARTUUID=e04a3889-...` correctly matches nvme1n1p1, and the FDT +
  camera overlay referenced by the default `JetsonIO` entry both exist.
- `/var/log` proves the Jetson booted fine for days, last alive 10:11 today.
- Real cause: at **10:04 today PackageKit auto-ran a huge update
  (L4T 36.4.3 → 36.4.7 + ~190 other packages)** and the machine went down
  at ~10:11 mid-transaction (apt history.log entry has no End-Date).
  Result: ~190 packages left "unpacked"/unconfigured — including systemd,
  udev, mount, kmod, openssl, all 44 nvidia-l4t-* — plus pending ldconfig/
  initramfs triggers and samba-libs "half-installed". Black screen = broken
  userspace, not broken bootloader/kernel files.
- `Image.org`/`initrd.org` on the SSD are byte-identical to the R36.5.0 BSP
  (= USB drive) kernel/initrd — leftovers of an earlier repair attempt;
  `Image`/`initrd` == their `.bak` copies (the 36.4.7 versions). Do NOT
  "fix" these by copying the USB's 5.15.185 kernel over — the SSD only has
  /lib/modules/5.15.148-tegra; mixing kernels would genuinely break it.

**Fix**: finish the interrupted upgrade via qemu-user-static chroot from
this x86 host (qemu + aarch64 binfmt verified working; all 1120 debs of the
update still in the SSD's /var/cache/apt/archives).
Script: `~/jetson_rescue/repair_ssd_dpkg.sh` — binds proc/sys/dev, adds
policy-rc.d guard + NVIDIA's `.nv-l4t-disable-boot-fw-update-in-preinstall`
marker (so l4t debs don't touch boot firmware from the host), re-unpacks
samba-libs from cache, then `dpkg --configure -a --force-confdef
--force-confold`, then `dpkg --audit`. Run it:
```
sudo bash ~/jetson_rescue/repair_ssd_dpkg.sh 2>&1 | tee ~/jetson_rescue/repair_run1.log
```
Expect it to be slow under qemu (initramfs/man-db triggers). After it
finishes clean: verify extlinux.conf PARTUUID unchanged, `dpkg --audit`
empty, then unmount, put SSD back in Jetson, boot. QSPI/bootloader payload
update (nvidia-l4t-bootloader 36.4.7) will apply itself on-device on first
boot via nv update engine if needed.

## 2026-07-05 evening: REPAIR COMPLETE ✅
- Run 1 (`repair_run1.log`): configured everything except openssh-sftp-server
  (its matching openssh-client/server 0.15 debs were never unpacked before
  the crash). Run 2 (`repair_ssd_dpkg2.sh` / `repair_run2.log`): unpacked
  both from apt cache, `dpkg --configure -a` exit 0, `dpkg --audit` clean.
- Verified: /boot/Image = 5.15.148 (36.4.7), fresh depmod with nvgpu.ko +
  opensrc-disp OOT display modules present, fresh initrd.img-5.15.148-tegra
  generated, extlinux.conf PARTUUID correct.
- Note: nvidia-l4t-kernel postinst rewrote extlinux.conf and reset
  `DEFAULT JetsonIO` → `DEFAULT primary`; restored to JetsonIO before
  unmount (the JetsonIO entry carries the dual-IMX219 camera FDT/overlay
  the system used pre-crash).
- DONE on host PC: `DEFAULT JetsonIO` restored in extlinux.conf, both
  drives unmounted cleanly, SSD detached from the PC. Host-side work is
  finished.

## ~~ONLY REMAINING STEP~~ (superseded — boot test failed, see next section): boot test on the Jetson
1. Reinstall the NVMe SSD in the Jetson, boot normally (no recovery
   jumper, no USB drive, no host PC).
2. First boot may be slower and may auto-reboot once — the deferred
   36.4.7 bootloader-firmware update can apply itself on-device. Let it
   finish undisturbed.
3. Keep the flashed USB drive as a rescue stick (bootable R36.5.0
   environment, independent of the SSD).
4. If it boots: consider disabling unattended L4T upgrades (the root
   cause was PackageKit auto-updating L4T and being interrupted at
   2026-07-05 10:11) — e.g. turn off automatic updates in Software &
   Updates, or apply JetPack updates manually in future.
5. On this host PC, re-enable GNOME automount when done:
   `gsettings set org.gnome.desktop.media-handling automount true`
   `gsettings set org.gnome.desktop.media-handling automount-open true`

## 2026-07-05 night: BOOT TEST FAILED — initrd can't find root partition

### What happened, in sequence
1. First boot attempts (SSD, and also the rescue USB via UEFI Boot Manager):
   NVIDIA logo, then only a blinking cursor top-left, **zero** kernel text,
   no auto-reboot. CapsLock LED **did** toggle → kernel was alive at least
   once. Jetson never appeared on the LAN (mDNS + full ping sweep of
   192.168.0.0/24 from this PC found no NVIDIA MAC `48:b0:2d`/`00:04:4b`).
2. User went into the UEFI menu and set **"OS chain A status" back to
   NORMAL** (UEFI had marked the boot chain bad after the crash/failed
   boots). After that, real boot messages finally appeared — the silent
   blinking-cursor behavior was at least partly the bad-chain state, not
   (only) a display problem.
3. Boot now fails visibly in the initrd with:
   `mount: /mnt: can't find PARTUUID=e04a3889-579f-4382-80d2-91a7aa75b1ae`
   (that's the SSD rootfs PARTUUID from extlinux.conf — correct value).
   **No rescue shell** is offered after the error, so no on-device
   diagnosis possible (no serial console available so far).

### Interpretation
- UEFI reads the SSD fine (it loads kernel+initrd from the SSD's /boot),
  but once the kernel runs, the NVMe disk (or that partition) is not
  found from inside the initrd.
- **Top suspect: the initrd we regenerated during the dpkg repair**
  (`initrd.img-5.15.148-tegra`, built by update-initramfs inside the qemu
  chroot) is missing the nvme driver modules or not loading them. It's the
  one boot component the repair rebuilt.
- Alternative to rule out: PARTUUID actually changed / GPT issue (unlikely
  — nothing repartitioned the SSD; verify with blkid anyway).

### ~~NEXT STEPS~~ (superseded — diagnosis complete, see next section)

## 2026-07-05 late night: INITRD DIAGNOSIS COMPLETE — wrong initrd file, easy fix

SSD reattached to host PC as `nvme1n1`, rootfs mounted at /mnt/jetson-ssd.
Findings (all verified directly, no guesswork):

1. **PARTUUID is correct** — `lsblk -o PARTUUID` shows nvme1n1p1 =
   `e04a3889-579f-4382-80d2-91a7aa75b1ae`, exactly matching extlinux.conf
   `root=`. GPT theory ruled out.
2. **extlinux.conf boots `INITRD /boot/initrd`** (both `primary` and
   `JetsonIO` entries; all backups too — this path was always used).
3. **`/boot/initrd` cannot mount an NVMe root.** Fully unpacked it
   (single gzip cpio, 217 files): it contains exactly TWO kernel modules —
   r8168.ko and r8126.ko (Realtek NICs). No nvme.ko, no nvme-core.ko,
   no pcie-tegra194.ko, no phy-tegra194-p2u.ko.
4. On this kernel (5.15.148-tegra) **nvme, nvme-core, pcie-tegra194 and
   phy-tegra194-p2u are all modules, not built-in** (checked
   modules.builtin). So with that initrd the kernel literally cannot see
   the NVMe disk → `can't find PARTUUID=…` — exact observed failure.
   (ext4 + crc32c ARE built-in, so filesystem support is fine.)
5. Why it used to boot: `/boot/initrd` was **overwritten at 10:10:54 —
   mid-crash-upgrade** — by the nvidia-l4t-initrd 36.4.7 package unpack
   (content == `initrd.bak`, the package-shipped minimal devkit initrd).
   The pre-crash initrd that actually booted the system is gone.
6. **The good initrd already exists**: `/boot/initrd.img-5.15.148-tegra`
   (29MB, built 17:34 by update-initramfs during the dpkg repair, proper
   initramfs-tools initrd). Verified via lsinitramfs it contains nvme.ko,
   nvme-core.ko, pcie-tegra194.ko, phy-tegra194-p2u.ko. No chroot
   rebuild needed.

**Fix applied**: point both INITRD lines in extlinux.conf at
`/boot/initrd.img-5.15.148-tegra` (backup saved as
`extlinux.conf.pre-initrd-fix`):
```
sudo sed -i.pre-initrd-fix 's|^\(\s*\)INITRD /boot/initrd$|\1INITRD /boot/initrd.img-5.15.148-tegra|' \
  /mnt/jetson-ssd/boot/extlinux/extlinux.conf
```
DEFAULT stays JetsonIO. **Applied and verified**: both `primary` and
`JetsonIO` now use `INITRD /boot/initrd.img-5.15.148-tegra`; all files the
boot entries reference (Image, initrd.img, FDT, camera .dtbo) confirmed
present on the SSD. Remaining: unmount cleanly, reinstall SSD in the
Jetson, boot test (SSD only, no USB drive attached).

**Caveat for the future**: nvidia-l4t-kernel's postinst rewrites
extlinux.conf on L4T upgrades (it already reset DEFAULT once) — after any
future JetPack/L4T upgrade, re-check that INITRD still points at the
initramfs-tools initrd (or that /boot/initrd finally contains nvme
modules) and DEFAULT is still JetsonIO.

**If the next boot still fails** in the initrd, the initramfs-tools initrd
drops to a busybox `(initramfs)` rescue shell on failure (unlike the L4T
one) — `cat /proc/modules`, `ls /dev/nvme*`, `dmesg | grep -iE 'pcie|nvme'`
there will show what's missing.

**Fallback resource**: the user has the Yahboom Jetson Orin NX image/ISO
file available (offered 2026-07-05, not needed so far). It contains
Yahboom's original pre-crash `/boot/initrd` (the file destroyed at 10:10
by the interrupted upgrade) and their full carrier-board setup — plan B
if the boot test fails, or the source for a full reflash in the worst case.

## ~~Status after initrd fix~~ (superseded — boot test #2 done, see next section)
- extlinux.conf fix applied & verified on the SSD; SSD unmounted cleanly.
- Standing reminders (still valid):
  - After any future JetPack/L4T upgrade: re-check extlinux.conf
    (postinst rewrites it — DEFAULT and INITRD may get reset).
  - When the rescue is done: disable unattended/automatic L4T upgrades
    on the Jetson (PackageKit auto-update was the root cause); keep the
    flashed USB as a rescue stick; re-enable GNOME automount on this PC:
    `gsettings set org.gnome.desktop.media-handling automount true`
    `gsettings set org.gnome.desktop.media-handling automount-open true`

## 2026-07-05 boot test #2: INITRD FIX WORKED — new failure at graphical stage

### Result
The `can't find PARTUUID` error is gone. Boot messages now scroll normally
(kernel + initrd fine, root mounted, systemd runs deep into userspace),
then the screen goes **black at the point where the console would hand
off to the graphical stack (GDM + NVIDIA display driver)** and stays black.

### Symptoms collected
- No text VT reachable: Ctrl+Alt+F1..F6 all give nothing (no login
  prompt), CapsLock gives no response after the black screen, HDMI
  unplug/replug does not recover. (Suggests more than a plain GDM crash —
  possibly console/PAM also broken, or a display-driver hang.)
- Jetson NOT on the LAN: full ping sweep + mDNS from the host PC found
  no new SSH host (checked all live hosts' port 22). NB: Yahboom carrier
  uses a **Realtek** NIC (hence r8168.ko in the L4T initrd) — do not
  filter scans by NVIDIA MAC OUIs. (Unknown whether the Ethernet cable
  was actually connected during the test.)
- FAILED lines user saw during boot:
  - `Failed to start nvidia specific power service` and
    `Dependency failed for nvpmodel service` — L4T 36.4.7 services,
    not display-related, but possibly same root cause (config/library
    still bad after the interrupted upgrade).
  - `Dependency failed for sssd * responder socket` (nss/autofs/pac/
    pam/ssh/sudo) — cascade from sssd.service failing; usually cosmetic
    on Jetsons, BUT combined with no-VT-login it raises suspicion of a
    broken PAM/NSS stack (openssl/libc were among the crash-affected
    packages).
  - `Failed to start process error reports ...` (whoopsie) — harmless.

### Interpretation
System is alive well into userspace; the black screen is at GDM/display-
driver start. Candidate causes, to be decided by the journal on the SSD:
GDM crash, nvidia-drm/nvgpu modeset failure or hang, or broken PAM/NSS
(would explain sssd failures AND dead VT logins).

### ~~NEXT STEP~~ (done — see next section): read the boot logs from the SSD on the host PC
The SSD now boots far enough to write a journal — that will pinpoint the
failure. Diagnostic script prepared: `~/jetson_rescue/bootdiag.sh`
(mounts the SSD at /mnt/jetson-ssd, dumps extlinux.conf, last-boot
journal tail + priority<=3 errors + gdm/nvgpu/drm/nvidia lines, syslog
tail, nv_update_engine log → writes report to
`~/jetson_rescue/bootdiag.log`, leaves SSD mounted).
1. Shut Jetson down (hold power ~10 s), move SSD to host PC (enclosure).
2. `! lsblk -o NAME,SIZE,MODEL,TRAN,FSTYPE`  (confirm device name —
   was nvme1n1 before, never assume)
3. `! sudo bash ~/jetson_rescue/bootdiag.sh /dev/nvme1n1p1`
4. Read bootdiag.log, pick the fix. Likely moves depending on findings:
   set default boot to text mode (`systemd.unit=multi-user.target` via
   extlinux APPEND) to get a usable console; repair display-driver or
   PAM/NSS packages via the qemu chroot; plan B remains Yahboom's
   original image (initrd/rootfs reference).

## 2026-07-05 ~20:00: ROOT CAUSE OF BLACK SCREEN FOUND — initrd loads display stack too early

Diagnosis from bootdiag.log / bootdiag2.log / bootdiag3.log / bootdiag4.log
(SSD on host PC as nvme1n1, mounted /mnt/jetson-ssd):

1. **The system is NOT hung — it boots completely.** During the "black
   screen" a full GNOME session was running (auto-login user `jetson`,
   Wayland off, X11), openclaw/node app had working internet, anacron ran.
   PAM/NSS fine (auth.log clean); sssd/nvpower failures were side-effects,
   not cause. No VT output because the display engine never lit up.
2. **It WAS on the LAN**: eno1 (r8168) got DHCP **192.168.0.39** at
   19:28:01, avahi registered `nknu.local`, sshd listening on 22, UFW
   disabled. Earlier sweep just missed it (wrong moment). → Next boot:
   `ssh jetson@192.168.0.39` (or nknu.local) works even with black screen.
3. **Display failure chain** (failing boot vs pre-crash working boots in
   kern.log.1/syslog.1):
   - Working boots: host1x/tegra-drm load ~6-8s from rootfs via udev →
     tegra drm creates /dev/dri/card0 → X nvidia_drv initializes →
     it triggers nvidia-modeset + nvidia-drm load at ~13s →
     "fb0: switching to nvidia-drm from simple" → display OK.
   - Failing boot: the NEW initramfs-tools initrd (MODULES=most) contains
     the DRM stack (updates/gpu/host1x.ko, updates/gpu/drm/tegra/tegra-drm.ko,
     nvhwpm, tegra_wmark + whole kernel/drivers/gpu/drm). udev inside the
     initrd loads them at ~2.1s; VIC/NVDEC/NVENC/NVJPG/OFA probe-fail
     "failed to init devfreq: -22" (barren initrd env), a HARD error — no
     retry after pivot → tegra-drm never creates card0 → Xorg
     "(EE) No devices detected" (AllowEmptyInitialConfiguration lets X run
     with 0 outputs) → nvidia-modeset/nvidia-drm never load → black screen.
   - Same mechanism explains nvpower.service failure (missing devfreq/
     actmon sysfs) and thus nvpmodel dependency failure.
   - Static config all verified OK: modules present, vermagic match,
     depmod/alias DBs correct (tested with modprobe -d from host), no
     blacklists, udev rules identical to stock BSP.

**FIX (prepared): `~/jetson_rescue/repair_initrd_drm.sh`** (run with sudo):
- installs initramfs hook `/etc/initramfs-tools/hooks/exclude-display-modules`
  on the SSD (prunes kernel/drivers/gpu, updates/drivers/gpu,
  updates/drivers/devfreq, updates/nvhwpm.ko from every future initrd —
  survives kernel updates),
- backs up initrd as initrd.img-5.15.148-tegra.pre-drm-fix,
- rebuilds initrd via qemu chroot (update-initramfs -u -k 5.15.148-tegra),
- verifies (0 display modules, nvme still present, extlinux INITRD lines),
- unmounts the SSD if verification passes.

Then: SSD back in Jetson, boot. Even if display were still bad, SSH at
192.168.0.39 / nknu.local now known to work for live debugging.

Still standing after success: disable unattended L4T upgrades on the
Jetson (root cause of the whole saga), keep USB rescue stick, re-enable
GNOME automount on host PC, and after any future L4T upgrade re-check
extlinux.conf (INITRD/DEFAULT) — plus note the initramfs hook above.

## 2026-07-05 20:12: INITRD FIX APPLIED & VERIFIED ✅
`repair_initrd_drm.sh` ran clean:
- Hook `/etc/initramfs-tools/hooks/exclude-display-modules` installed on the
  SSD (prunes kernel/drivers/gpu, updates/drivers/gpu, updates/drivers/devfreq,
  updates/nvhwpm.ko from every future initrd build — survives kernel updates).
- Initrd rebuilt in qemu chroot: 0 display/gpu modules left, 6 nvme module
  files present, both extlinux INITRD lines still point at
  /boot/initrd.img-5.15.148-tegra. New initrd 26 MB (was 29 MB).
- Backup kept: /boot/initrd.img-5.15.148-tegra.pre-drm-fix.
- ("W: Couldn't identify type of root file system for fsck hook" during the
  chroot build is harmless — no root fsck helper embedded, kernel mounts
  ext4 directly.)

## 2026-07-05 20:16: OpenClaw discovery — vendor leftover, NOT user-installed
Frank did not install the OpenClaw AI gateway found running on the Jetson.
Audit (`openclaw_audit.sh` → openclaw_audit.log, SSD mounted read-only):
- Installed 2026-03-18 09:44 (npm global, user jetson) while hostname was
  still `yahboom`; systemd user service openclaw-gateway enabled same minute.
- Used Mar 13–26 as a Chinese-ecosystem bot demo: Bailian/Qwen backend,
  QQ bot, Feishu, WhatsApp paired to a +86 number; Chinese test cron jobs;
  bilingual vendor-style setup.sh for Bailian API key.
- Mar 26 17:52 pre-handover cleanup by vendor/previous owner: gateway
  identity wiped, paired devices emptied, phone/appId values hand-masked
  ("xxx") in openclaw.json — but they forgot to disable the service and
  left stale WhatsApp session files → the 401 "session logged out"
  crash-loop seen in the Jul 5 boot logs. Harmless but noisy.
- No intrusion indicators: no authorized_keys anywhere, crontabs empty,
  SSH logins only from the vendor's own LANs in March, nothing since.
- Residual risk: gateway binds LAN :18789 with token auth + "coding" tool
  profile; vendor knew the jetson account password (password SSH logins).

### Cleanup plan
1. BEFORE boot (prepared, may already be done): remove autostart symlink —
   `sudo mount -o remount,rw /mnt/jetson-ssd && sudo rm /mnt/jetson-ssd/home/jetson/.config/systemd/user/default.target.wants/openclaw-gateway.service && sudo umount /mnt/jetson-ssd`
2. After boot, on the Jetson (ssh jetson@192.168.0.39 or nknu.local):
   `systemctl --user disable --now openclaw-gateway`
   `npm -g uninstall openclaw`
   `rm -rf ~/.openclaw`
   `passwd`   (vendor knew the current password)
   Optionally delete vendor Wi-Fi profiles (Yahboom/Yahboom2/Yahboom3; also
   PDCN / "Porsche 911 Turbo S" if not Frank's).

## CURRENT STATE / NEXT STEPS
1. Run the autostart-removal command above (if not yet done), SSD unmounts.
2. Reinstall SSD in Jetson, boot (no USB stick). Display expected to work:
   host1x/tegra-drm now load post-boot → /dev/dri/card0 → X → nvidia-drm.
   nvpower/nvpmodel failures should also be gone.
3. Even with a black screen the Jetson is reachable: it gets DHCP on eno1
   (was 192.168.0.39), hostname nknu, `ssh jetson@nknu.local`, UFW off.
4. Do the OpenClaw cleanup + password change (above).
5. Disable unattended L4T/PackageKit upgrades (original root cause of the
   whole saga) — Software & Updates → never auto-install, or apt config.
6. Host PC: re-enable GNOME automount:
   `gsettings set org.gnome.desktop.media-handling automount true`
   `gsettings set org.gnome.desktop.media-handling automount-open true`
7. Keep the USB drive as rescue stick; keep initrd backup .pre-drm-fix.
8. After any future L4T upgrade: re-check extlinux.conf INITRD/DEFAULT
   (postinst rewrites it) — the initramfs hook itself survives updates.
