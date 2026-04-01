# Ubuntu 24.04 LTS on MacBook Pro 2017 (Touch Bar) — Fix Guide

> Covers: **Webcam**, **Touch Bar**, **Audio**, and **WiFi** for `MacBookPro14,2` (13") and `MacBookPro14,3` (15") running Ubuntu 24.04 LTS.

---

## ⚠️ Critical: T1 Chip vs T2 Chip — Know Your Model

The 2017 MacBook Pro (Touch Bar) uses the **Apple T1 chip**, not T2. This is a fundamental distinction that affects which fixes apply to you. Much of the online documentation — including the t2linux project name itself — is primarily written for **T2 Macs (2018+)**. Some of it applies to T1, some does not.

| Mac Model | Chip | Year |
|-----------|------|------|
| MacBookPro14,2 (13") | **T1** | 2017 |
| MacBookPro14,3 (15") | **T1** | 2017 |
| MacBookPro15,x+ | T2 | 2018+ |

**Key T1 differences from T2:**
- T1 has **no BCE PCIe device** — `apple_bce` module loads but finds nothing to bind to. This is expected and not an error.
- T1 keyboard/trackpad communicate via **SPI** (`applespi` driver), not BCE
- T1 Touch Bar uses a **USB HID** path, not `hid-appletb-kbd`
- T1 internal speakers require a **sub-codec** (CS42L83/CS42L84) that the current Linux kernel driver does not fully support

---

## Current Feature Support Matrix (MBP14,2 / MBP14,3)

| Feature | Status | Notes |
|---------|--------|-------|
| Keyboard | ✅ Works | Via `applespi` (SPI driver) |
| Trackpad | ✅ Works | Via `applespi` (SPI driver) |
| WiFi (2.4GHz) | ✅ Works | BCM43602 with generic firmware |
| WiFi (5GHz) | ❌ Not working | BCM43602 firmware limitation on Linux — no fix available |
| Webcam | ✅ Works | Requires `facetimehd` driver |
| Bluetooth | ✅ Works | Built into T2 kernel |
| USB-C / Thunderbolt | ✅ Works | |
| Internal Speakers | ✅ Works | Requires `snd_hda_macbookpro` out-of-tree driver |
| Headphone Jack | ✅ Works | Requires `snd_hda_macbookpro` out-of-tree driver |
| Internal Microphone | ⚠️ Partial | May work after driver install — test after reboot |
| Bluetooth Audio | ✅ Works | |
| Touch Bar | ❌ Not working | No T1 Touch Bar driver in mainline kernel |
| Keyboard Backlight | ✅ Works | Via `applespi` — requires udev rule for persistence |
| Fan Control | ✅ Works | Via `applesmc` |
| Battery | ✅ Works | |
| Suspend/Resume | ⚠️ Partial | May require tweaks |

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Step 1 — Install the T2 Kernel](#step-1--install-the-t2-kernel)
- [Step 2 — Add Required Kernel Parameters](#step-2--add-required-kernel-parameters)
- [Step 3 — apple-bce Module Note](#step-3--apple-bce-module-note)
- [Step 4 — Audio (CS8409 Status)](#step-4--audio-cs8409-status)
- [Step 5 — Touch Bar (T1 Status)](#step-5--touch-bar-t1-status)
- [Step 6 — Fix Webcam (FaceTime HD)](#step-6--fix-webcam-facetime-hd)
- [Step 7 — Fix WiFi](#step-7--fix-wifi)
- [Step 8 — Keyboard Backlight](#step-8--keyboard-backlight)
- [Step 9 — Restore T1 Firmware (Critical)](#step-9--restore-t1-firmware-critical)
- [Verification Checklist](#verification-checklist)
- [Known Caveats](#known-caveats)
- [Resources](#resources)

---

## Prerequisites

Confirm your exact model identifier:

```bash
sudo dmidecode -s system-product-name
```

Expected output: `MacBookPro14,2` (13-inch) or `MacBookPro14,3` (15-inch).

Make sure you have internet access via USB-C adapter/Ethernet or USB tethering during setup, as internal WiFi firmware may need to be installed first.

---

## Step 1 — Install the T2 Kernel

The stock Ubuntu kernel lacks support for Apple T1 hardware. The T2 kernel (which also supports T1 Macs) enables keyboard, trackpad, fan control, and WiFi.

```bash
# Step 1 — Add GPG key and common repo
curl -s --compressed "https://adityagarg8.github.io/t2-ubuntu-repo/KEY.gpg" \
  | gpg --dearmor \
  | sudo tee /etc/apt/trusted.gpg.d/t2-ubuntu-repo.gpg >/dev/null

sudo curl -s --compressed \
  -o /etc/apt/sources.list.d/t2.list \
  "https://adityagarg8.github.io/t2-ubuntu-repo/t2.list"

# Step 2 — Add the Noble (24.04) release-specific repo
# ⚠️ This step is required — without it, linux-t2 will not be found
CODENAME=noble
echo "deb [signed-by=/etc/apt/trusted.gpg.d/t2-ubuntu-repo.gpg] https://github.com/AdityaGarg8/t2-ubuntu-repo/releases/download/${CODENAME} ./" \
  | sudo tee -a /etc/apt/sources.list.d/t2.list

# Step 3 — Update and install
sudo apt update
sudo apt install linux-t2
```

> **Note:** If you get `E: Unable to locate package linux-t2` — it means the Noble-specific repo line (Step 2) was skipped or failed. Both steps are required for Ubuntu 24.04.

Reboot into the new kernel. Verify with:

```bash
uname -r
# Should contain: -t2  e.g. 6.19.10-2-t2-noble
```

> **Repo:** https://github.com/t2linux/T2-Debian-and-Ubuntu-Kernel

---

## Step 2 — Add Required Kernel Parameters

These parameters are required for hardware passthrough and proper device initialization.

```bash
sudo nano /etc/default/grub
```

Find this line:

```
GRUB_CMDLINE_LINUX="quiet splash"
```

Change it to:

```
GRUB_CMDLINE_LINUX="quiet splash intel_iommu=on iommu=pt pcie_ports=compat"
```

Apply and reboot:

```bash
sudo update-grub
sudo reboot
```

Verify after reboot:

```bash
cat /proc/cmdline
# Should contain: intel_iommu=on iommu=pt pcie_ports=compat
```

> ⚠️ **After a fresh Ubuntu reinstall, these parameters are lost.** Always re-add them after reinstalling the OS.

---

## Step 3 — apple-bce Module Note

> **T1 Mac owners: read this before following T2-focused guides.**

The `apple_bce` module is included in the T2 kernel and will load automatically. On T1 Macs, **this is expected behaviour** — the module loads but finds no BCE device because the T1 chip architecture does not expose a BCE PCIe interface.

```bash
# This will show apple_bce loaded but with 0 users — this is normal on T1
lsmod | grep apple_bce

# /dev/bce* will NOT exist on T1 — this is also normal
ls /dev/bce*  # Expected: "No such file or directory"

# The T1 iBridge appears as USB, not PCIe
lsusb | grep Apple
# Expected: Apple, Inc. iBridge
```

**Do not** add `apple-bce` to `/etc/modules-load.d/` or `/etc/initramfs-tools/modules` on T1 Macs — it serves no purpose.

The keyboard and trackpad on T1 Macs work through the **SPI interface** via the `applespi` driver, which loads automatically:

```bash
sudo dmesg | grep applespi
# Expected:
# applespi spi-APP000D:00: modeswitch done.
# input: Apple SPI Keyboard
# input: Apple SPI Touchpad
```

---

## Step 4 — Fix Audio (Internal Speakers + Headphone Jack)

Internal speakers and headphone jack work on MBP14,2 / MBP14,3 using the community `snd_hda_macbookpro` driver by davidjo. The stock kernel CS8409 driver does not support the T1 sub-codec wiring — this out-of-tree driver adds that support.

### 4a — Prerequisites

```bash
sudo apt install git build-essential
```

### 4b — Install kernel source (required by the installer)

The installer needs the kernel 6.17 source as a build reference. Install it, then create a symlink so the installer can find it under the running kernel version:

```bash
# Install the 6.17 kernel source
sudo apt install linux-source-6.17.0

# Create symlink at the path the installer expects
sudo ln -s /usr/src/linux-source-6.17.0/linux-source-6.17.0.tar.bz2 \
  /usr/src/linux-source-6.19.10.tar.bz2

# Also create the directory version if needed
sudo mkdir -p /usr/src/linux-source-6.19.10
sudo ln -s /usr/src/linux-source-6.17.0/linux-source-6.17.0.tar.bz2 \
  /usr/src/linux-source-6.19.10/linux-source-6.19.10.tar.bz2
```

> **Note:** Replace `6.19.10` with your actual kernel version from `uname -r | cut -d- -f1`. Replace `6.17.0` with the available linux-source version from `apt-cache search linux-source`.

### 4c — Clone and patch the installer

```bash
cd ~
sudo git clone https://github.com/davidjo/snd_hda_macbookpro.git
cd snd_hda_macbookpro
```

The installer extracts HDA source files using the kernel version name internally. Since the tarball contains `linux-source-6.17.0/` but the installer looks for `linux-source-6.19.10/`, patch line 176:

```bash
sudo sed -i 's/linux-source-$kernel_version\/sound\/hda/linux-source-6.17.0\/sound\/hda/g' \
  ~/snd_hda_macbookpro/install.cirrus.driver.sh

# Verify the patch
grep "sound/hda" ~/snd_hda_macbookpro/install.cirrus.driver.sh
```

### 4d — Run the installer

```bash
cd ~/snd_hda_macbookpro
sudo ./install.cirrus.driver.sh
```

Wait a few minutes for it to compile. A successful install ends with:

```
contents of /lib/modules/6.19.10-2-t2-noble/updates/codecs/cirrus
total 352
-rw-r--r-- 1 root root 358312 ... snd-hda-codec-cs8409.ko
```

The SSL signing warning and missing `System.map` warning are harmless — ignore them.

### 4e — Reboot and test

```bash
sudo reboot
```

After reboot:

```bash
# Verify the new module loaded
lsmod | grep snd_hda_codec_cs8409

# Test speakers
speaker-test -c 2 -t wav

# Check PipeWire sees the audio card
pactl list sinks short
```

### 4f — Set up PipeWire (if not already running)

```bash
sudo apt install pipewire pipewire-pulse wireplumber pulseaudio-utils
systemctl --user enable --now pipewire pipewire-pulse wireplumber
```

Set the correct output profile and port:

```bash
pactl set-card-profile alsa_card.pci-0000_00_1f.3 output:analog-stereo+input:analog-stereo
pactl set-sink-port alsa_output.pci-0000_00_1f.3.analog-stereo analog-output-speaker
```

Make the profile persist across reboots:

```bash
mkdir -p ~/.config/wireplumber/wireplumber.conf.d/

cat <<EOF > ~/.config/wireplumber/wireplumber.conf.d/51-apple-audio.conf
monitor.alsa.rules = [
  {
    matches = [{ device.name = "alsa_card.pci-0000_00_1f.3" }]
    actions = {
      update-props = {
        api.acp.auto-profile = true
        api.acp.auto-port = true
      }
    }
  }
]
EOF

systemctl --user restart wireplumber
```

### ⚠️ After kernel updates

The `snd_hda_macbookpro` driver is **not** a DKMS module — it will not rebuild automatically after kernel updates. After every kernel update, re-run the installer:

```bash
cd ~/snd_hda_macbookpro
sudo ./install.cirrus.driver.sh
sudo reboot
```

> **Driver source:** https://github.com/davidjo/snd_hda_macbookpro

---

## Step 5 — Touch Bar (T1 Status)

> ⚠️ **The Touch Bar does not work on MBP14,2 / MBP14,3 with the current kernel.**

The T1 Touch Bar uses a USB HID path that differs from the T2 Touch Bar. The `tiny-dfr` tool and `hid-appletb-kbd` module are designed for **T2 Macs only**. Do not install `tiny-dfr` on a T1 Mac — it will have no effect.

The Touch Bar strip remains **lit** (showing the default brightness controls from firmware) but is not interactive under Linux.

```bash
# The T1 Touch Bar is hosted by the iBridge USB device
lsusb | grep Apple
# Shows: Apple, Inc. iBridge

# No interactive Touch Bar driver is available for T1
sudo dmesg | grep -i "touchbar\|8302"
# No relevant output expected
```

**Tracking support:** T1 Touch Bar Linux support would require a dedicated USB HID driver. There is no active upstream effort for this at time of writing.

---

## Step 6 — Fix Webcam (FaceTime HD)

The 2017 MacBook Pro has an **Apple FaceTime HD PCIe camera**. It requires a reverse-engineered driver (`facetimehd`) and firmware extracted from Apple's drivers.

### 6a — Install dependencies

```bash
sudo apt install git cpio curl xz-utils dkms build-essential
```

### 6b — Extract and install firmware

```bash
sudo git clone https://github.com/patjak/facetimehd-firmware.git /usr/local/src/facetimehd-firmware
cd /usr/local/src/facetimehd-firmware
sudo make
sudo make install
```

Expected output:

```
Extracted firmware version x.x.x
Copying firmware into '/usr/lib/firmware/facetimehd'
```

### 6c — Build and install the DKMS driver

```bash
sudo git clone https://github.com/patjak/facetimehd.git /usr/local/src/facetimehd
cd /usr/local/src/facetimehd
sudo make
sudo make install
sudo depmod
sudo modprobe facetimehd
```

### 6d — Load on boot

```bash
echo facetimehd | sudo tee /etc/modules-load.d/facetimehd.conf
```

Reboot, then verify:

```bash
ls /dev/video*
# Should show /dev/video0

lsmod | grep facetimehd
# Should list the module

# Quick test (install ffmpeg if needed: sudo apt install ffmpeg)
ffplay /dev/video0
```

> **Note:** DKMS rebuilds the driver automatically on kernel updates. If the webcam breaks after a kernel update, run `sudo dkms autoinstall`.

---

## Step 7 — Fix WiFi

The 2017 MacBook Pro uses a **Broadcom BCM43602** chip. The `brcmfmac` driver is built into the T2 kernel, but proper Apple-specific firmware must be copied from macOS for reliable operation.

> ⚠️ **Do NOT install `broadcom-wl`** — it conflicts with `brcmfmac` and breaks WiFi entirely.

> ⚠️ **5GHz WiFi does not work on BCM43602 under Linux.** The Apple-specific firmware binary is incompatible with the `brcmfmac` driver — using it causes the driver to crash. The generic firmware provides reliable 2.4GHz connectivity only.

### 7a — Back up WiFi firmware from macOS

Run this in macOS Terminal **before** wiping macOS:

```bash
# Use the official t2linux firmware script — saves firmware to EFI partition
curl -OL https://wiki.t2linux.org/tools/firmware.sh
chmod +x firmware.sh
sudo ./firmware.sh
# Choose Option 1 (copy to EFI partition) and answer Y to keep a copy
```

This saves `firmware-raw.tar.gz` and `firmware.sh` to your EFI partition, surviving Ubuntu reinstalls.

### 7b — Install firmware on Ubuntu

```bash
# Run the script from the EFI partition (works after any Ubuntu reinstall)
sudo bash /boot/efi/firmware.sh
# Choose Option 1 — retrieves from EFI partition
# Answer Y to keep a copy for future use
```

### 7c — Set regulatory domain

```bash
# Set your country code (TR = Turkey, US, GB, DE, etc.)
sudo iw reg set TR

# Make permanent
sudo nano /etc/default/crda
# Add or change: REGDOMAIN=TR
```

### 7d — Find your WiFi interface name

```bash
ip link show | grep wl
# Interface is likely wlp3s0, not wlan0
```

### 7e — Verify WiFi is working

```bash
sudo iw dev wlp3s0 scan | grep SSID
sudo dmesg | grep brcmfmac | tail -5
```

### ⚠️ wpa_supplicant regression note

If WiFi connects but immediately drops, add this kernel parameter:

```bash
sudo nano /etc/default/grub
# Add to GRUB_CMDLINE_LINUX: brcmfmac.feature_disable=0x82000

sudo update-grub
sudo reboot
```

---

## Step 8 — Keyboard Backlight

The keyboard backlight on MBP14,x is controlled via the `applespi` driver and exposed as `/sys/class/leds/spi::kbd_backlight`. It works out of the box but defaults to 0 (off) on every boot — a udev rule is needed to restore brightness automatically.

### 8a — Test brightness manually

```bash
# Check current brightness (0 = off)
cat /sys/class/leds/spi::kbd_backlight/brightness

# Check maximum value
cat /sys/class/leds/spi::kbd_backlight/max_brightness
# Returns: 255

# Set brightness (0–255)
echo 100 | sudo tee /sys/class/leds/spi::kbd_backlight/brightness
```

### 8b — Make it persist across reboots

```bash
# Create a udev rule to set brightness when the device appears at boot
cat <<EOF | sudo tee /etc/udev/rules.d/90-kbd-backlight.rules
ACTION=="add", SUBSYSTEM=="leds", KERNEL=="spi::kbd_backlight", ATTR{brightness}="100"
EOF

# Reload udev rules
sudo udevadm control --reload-rules
```

Adjust `100` to your preferred brightness level (0–255).

### 8c — Verify after reboot

```bash
sudo reboot
```

After reboot:

```bash
cat /sys/class/leds/spi::kbd_backlight/brightness
# Should return 100 (or whatever value you set)
```

> **Note:** The Fn+F5/F6 brightness keys do not currently adjust the backlight on T1 Macs under Linux — only the udev rule and manual `tee` commands work. This is a limitation of the current `applespi` driver.

---

## Step 9 — Restore T1 Firmware (Critical)

> ⚠️ **If you wipe macOS entirely, the T1 chip gets stuck in Recovery Mode.**

When macOS is wiped, the T1 firmware stored in the EFI partition is deleted. Without it:
- `lsusb` shows `Apple, Inc. Apple Mobile Device [Recovery Mode]` instead of `Apple, Inc. iBridge`
- WiFi firmware installation fails
- The system is in a degraded state

**How to check:**

```bash
lsusb | grep Apple
# Good: Apple, Inc. iBridge
# Bad:  Apple, Inc. Apple Mobile Device [Recovery Mode]
```

**How to fix — full procedure:**

1. Boot into macOS Internet Recovery (`Cmd + Option + R` on boot)
2. Reinstall macOS to a partition with minimum 20GB free space
3. Boot into macOS once — T1 firmware is written to the EFI partition on first boot
4. Back up WiFi firmware using the t2linux script (Step 7a above)
5. Reinstall Ubuntu using **manual/custom partitioning**:
   - Select the EFI partition → set mount point to `/boot/efi` → set **"Leave formatted as VFAT"** (do NOT reformat)
   - Select remaining space for `/` formatted as ext4
6. Boot into Ubuntu — T1 firmware in EFI survives the reinstall

> The Ubuntu installer reuses the existing EFI partition without reformatting it as long as you use manual partitioning. This preserves the Apple T1 firmware files that macOS wrote there.

---

## Verification Checklist

| Component | Command | Expected Result |
|-----------|---------|-----------------|
| Kernel | `uname -r` | Contains `-t2` |
| Kernel params | `cat /proc/cmdline` | Contains `intel_iommu=on iommu=pt` |
| T1 chip mode | `lsusb \| grep Apple` | `Apple, Inc. iBridge` (not Recovery Mode) |
| Keyboard/Trackpad | `sudo dmesg \| grep applespi` | `modeswitch done` + input devices listed |
| WiFi interface | `ip link show \| grep wl` | `wlp3s0` present |
| WiFi connection | `iwconfig wlp3s0` | Shows ESSID and signal |
| Webcam | `ls /dev/video*` | `/dev/video0` present |
| Webcam driver | `lsmod \| grep facetimehd` | Module listed |
| Audio driver | `lsmod \| grep snd_hda_codec_cs8409` | Module listed |
| Audio output | `speaker-test -c 2 -t wav` | Sound from speakers |
| Keyboard backlight | `cat /sys/class/leds/spi::kbd_backlight/brightness` | Returns your set value (e.g. 100) |
| Bluetooth | Settings → Bluetooth | Devices discoverable |

---

## Known Caveats

**Internal speakers / headphone jack:** Work after installing the `snd_hda_macbookpro` out-of-tree driver (Step 4). The driver must be manually reinstalled after every kernel update — it is not a DKMS module and does not rebuild automatically.

**Touch Bar:** No T1 Touch Bar driver exists in the mainline kernel. The bar remains lit (firmware default) but is not interactive. `tiny-dfr` and `hid-appletb-kbd` are for T2 Macs only — do not install them on T1.

**5GHz WiFi:** The BCM43602 Apple-specific firmware binary causes the `brcmfmac` driver to crash. 2.4GHz works reliably with the generic firmware.

**apple_bce:** Loads on T1 without error but finds no device — this is normal and expected. `/dev/bce*` will not exist on T1.

**EFI partition:** Never format the EFI partition during Ubuntu installation. It contains the T1 chip firmware written by macOS. If wiped, the T1 enters Recovery Mode.

**broadcom-wl:** Do NOT install. Conflicts with `brcmfmac` and breaks WiFi.

**DKMS:** The `facetimehd` driver rebuilds automatically on kernel updates. If webcam breaks after a kernel upgrade, run `sudo dkms autoinstall`.

---

## Resources

| Resource | URL |
|----------|-----|
| t2linux Wiki | https://wiki.t2linux.org |
| t2linux Ubuntu/Debian Kernel | https://github.com/t2linux/T2-Debian-and-Ubuntu-Kernel |
| t2linux WiFi & Bluetooth Guide | https://wiki.t2linux.org/guides/wifi-bluetooth/ |
| t2linux firmware script | https://wiki.t2linux.org/tools/firmware.sh |
| facetimehd driver | https://github.com/patjak/facetimehd |
| facetimehd firmware | https://github.com/patjak/facetimehd-firmware |
| snd_hda_macbookpro (audio driver) | https://github.com/davidjo/snd_hda_macbookpro |
| t2linux Discord | https://discord.com/invite/68MRhQu |

---

> **Tested on:** MacBookPro14,3 · Ubuntu 24.04 LTS · T2 Kernel 6.19.10-2-t2-noble · T1 chip
>
> Contributions and corrections welcome — open an issue or PR.
