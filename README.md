# Linux on MacBook Pro 2017 (MBP14,3 — T1 Chip) — Complete Fix Guide

> Covers: **Keyboard Backlight**, **Webcam**, **Touch Bar**, **Audio**, **WiFi**, **Fan Monitoring** and more for `MacBookPro14,2` (13") and `MacBookPro14,3` (15") running Ubuntu 24.04 LTS (also applicable to future LTS versions).

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
- T1 Touch Bar uses a **USB HID** path via the iBridge — requires `apple-ibridge` + `apple-ib-tb` driver stack plus a USB rebind workaround
- T1 internal speakers use a **sub-codec** (CS42L83/CS42L84) — requires the `snd_hda_macbookpro` out-of-tree driver (covered in Step 4)

---

## Current Feature Support Matrix (MBP14,2 / MBP14,3)

| Feature | Status | Notes |
|---------|--------|-------|
| Keyboard | ✅ Works | Via `applespi` (SPI driver) |
| Trackpad | ✅ Works | Via `applespi` (SPI driver) |
| WiFi (2.4GHz) | ✅ Works | BCM43602 with generic firmware |
| WiFi (5GHz) | ✅ Works | Requires NVRAM config with `boardflags3=0xC0000303` |
| Webcam | ✅ Works | Requires `facetimehd` driver |
| Bluetooth | ✅ Works | Built into T2 kernel |
| USB-C / Thunderbolt | ✅ Works | |
| Internal Speakers | ✅ Works | Requires `snd_hda_macbookpro` out-of-tree driver |
| Headphone Jack | ✅ Works | Requires `snd_hda_macbookpro` out-of-tree driver |
| Internal Microphone | ✅ Works | Requires duplex profile set in WirePlumber config |
| Touch Bar | ✅ Works | Requires patched `macbook12-spi-driver` + USB rebind service |
| Keyboard Backlight | ✅ Works | Via `applespi` — requires udev rule for persistence |
| Fan Control | ✅ Works | Via `applesmc` |
| Battery | ✅ Works | |
| Suspend/Resume | ⚠️ Partial | May require tweaks |

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Step 1: Install the T2 Kernel](#step-1-install-the-t2-kernel)
- [Step 2: Add Required Kernel Parameters](#step-2-add-required-kernel-parameters)
- [Step 3: apple-bce Module Note](#step-3-apple-bce-module-note)
- [Step 4: Fix Audio (Internal Speakers + Headphone Jack)](#step-4-fix-audio-internal-speakers--headphone-jack)
- [Step 5: Fix Touch Bar](#step-5-fix-touch-bar)
- [Step 6: Fix Webcam (FaceTime HD)](#step-6-fix-webcam-facetime-hd)
- [Step 7: Fix WiFi (2.4GHz + 5GHz)](#step-7-fix-wifi-24ghz--5ghz)
- [Step 8: Keyboard Backlight](#step-8-keyboard-backlight)
- [Step 9: Temperature & Fan Monitoring](#step-9-temperature--fan-monitoring-optional-but-recommended)
- [Step 10: Restore T1 Firmware (Critical)](#step-10-restore-t1-firmware-critical)
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

## Step 1: Install the T2 Kernel

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

## Step 2: Add Required Kernel Parameters

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

## Step 3: apple-bce Module Note

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

## Step 4: Fix Audio (Internal Speakers + Headphone Jack)

Internal speakers and headphone jack work on MBP14,2 / MBP14,3 using the community `snd_hda_macbookpro` driver by davidjo. The stock kernel CS8409 driver does not support the T1 sub-codec wiring — this out-of-tree driver adds that support.

### 4a — Prerequisites

```bash
sudo apt install git build-essential
```

### 4b — Install kernel source (required by the installer)

The installer needs a kernel source package as a build reference. Since the T2 kernel has no matching source package, install the closest available Ubuntu kernel source and symlink it to the path the installer expects:

```bash
# Check your running kernel version
KVER=$(uname -r | cut -d- -f1)
echo "Running kernel: $KVER"

# Find the available linux-source package
apt-cache search linux-source | grep "^linux-source-"

# Install the available source (e.g. linux-source-6.17.0)
sudo apt install linux-source-6.17.0

# Set the source version you just installed
SRC_VER=6.17.0

# Create symlinks at the paths the installer expects
sudo ln -s /usr/src/linux-source-${SRC_VER}/linux-source-${SRC_VER}.tar.bz2 \
  /usr/src/linux-source-${KVER}.tar.bz2

sudo mkdir -p /usr/src/linux-source-${KVER}
sudo ln -s /usr/src/linux-source-${SRC_VER}/linux-source-${SRC_VER}.tar.bz2 \
  /usr/src/linux-source-${KVER}/linux-source-${KVER}.tar.bz2
```

### 4c — Clone and patch the installer

```bash
cd ~
sudo git clone https://github.com/davidjo/snd_hda_macbookpro.git
cd snd_hda_macbookpro
```

The installer extracts HDA source files using the kernel version name internally. Since the tarball contains the source version name (e.g. `linux-source-6.17.0/`) but the installer looks for the running kernel version, patch line 176:

```bash
# Set to the source version you installed in Step 4b
SRC_VER=6.17.0

sudo sed -i "s/linux-source-\$kernel_version\/sound\/hda/linux-source-${SRC_VER}\/sound\/hda/g" \
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
contents of /lib/modules/<your-kernel>/updates/codecs/cirrus
total 352
-rw-r--r-- 1 root root ... snd-hda-codec-cs8409.ko
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

Set the correct output profile and port, and enable the microphone by using the duplex profile:

```bash
pactl set-card-profile alsa_card.pci-0000_00_1f.3 output:analog-stereo+input:analog-stereo
pactl set-sink-port alsa_output.pci-0000_00_1f.3.analog-stereo analog-output-speaker
```

Make the duplex profile (speakers + mic) persist across reboots:

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
        device.profile = "output:analog-stereo+input:analog-stereo"
      }
    }
  }
]
EOF

systemctl --user restart wireplumber
```

Verify both output and input sources are active:

```bash
pactl list sources short
# Should show both:
# alsa_output.pci-0000_00_1f.3.analog-stereo.monitor
# alsa_input.pci-0000_00_1f.3.analog-stereo

# Test microphone
arecord -d 5 -f cd /tmp/test-mic.wav && aplay /tmp/test-mic.wav
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

## Step 5: Fix Touch Bar

The T1 Touch Bar works using the `apple-ibridge` + `apple-ib-tb` driver stack from the `macbook12-spi-driver` repo, combined with a USB rebind trick to properly initialize the iBridge interface at boot.

> ⚠️ **Do NOT install `tiny-dfr` or `hid-appletb-kbd`** — those are for T2 Macs only and will have no effect on T1.

### 5a — Clone the driver

```bash
cd ~
git clone https://github.com/almas/macbook12-spi-driver
cd macbook12-spi-driver
git checkout touchbar-driver-hid-driver
```

### 5b — Patch for kernel 6.x compatibility

The driver was written for older kernels. Three changes are needed:

```bash
cd ~/macbook12-spi-driver

# Fix 1: remove() return type changed to void in kernel 6.x
sudo sed -i 's/static int appletb_platform_remove/static void appletb_platform_remove/' apple-ib-tb.c
sudo sed -i 's/static int appleals_platform_remove/static void appleals_platform_remove/' apple-ib-als.c

# Fix 2: remove .owner field from acpi_driver (removed in kernel 6.x)
sudo sed -i '/\.owner.*= THIS_MODULE,/d' apple-ibridge.c

# Fix 3: report_fixup return type changed to const __u8 *
sudo sed -i 's/static __u8 \*appleib_report_fixup/static const __u8 *appleib_report_fixup/' apple-ibridge.c
```

Now fix the function bodies — remove the old error-handling return statements since the functions are now void:

```bash
# Fix apple-ib-tb.c remove function body
grep -n "int rc;\|goto error;\|return 0;\|return rc;" apple-ib-tb.c
```

Note the line numbers for the remove function block (around line 1262) and use awk to remove the `int rc;`, `goto error;`, `return 0;`, and `return rc;` lines. Example (adjust line numbers to match your output):

```bash
# Remove int rc; line
sudo awk 'NR==1267 { next } { print }' apple-ib-tb.c > /tmp/fix.c && sudo cp /tmp/fix.c apple-ib-tb.c
# Remove goto error; line  
sudo awk 'NR==1269 { next } { print }' apple-ib-tb.c > /tmp/fix.c && sudo cp /tmp/fix.c apple-ib-tb.c
# Remove return 0; line
sudo awk 'NR==1269 { next } { print }' apple-ib-tb.c > /tmp/fix.c && sudo cp /tmp/fix.c apple-ib-tb.c
# Remove error: label and return rc;
sudo awk 'NR==1269 { next } NR==1270 { next } { print }' apple-ib-tb.c > /tmp/fix.c && sudo cp /tmp/fix.c apple-ib-tb.c
# Remove remaining return rc;
sudo awk 'NR==1269 { next } { print }' apple-ib-tb.c > /tmp/fix.c && sudo cp /tmp/fix.c apple-ib-tb.c
```

Do the same for `apple-ib-als.c` — find the remove function lines and remove `int rc;`, `goto error;`, `return 0;`, `error:`, and `return rc;` from that function only.

Verify both functions end cleanly:

```bash
grep -n "appletb_platform_remove\|appleals_platform_remove" apple-ib-tb.c apple-ib-als.c
```

### 5c — Install via DKMS

```bash
cd ~/macbook12-spi-driver
sudo ln -s `pwd` /usr/src/applespi-0.1
sudo dkms install applespi/0.1 --force
```

A successful install shows:

```
apple-ibridge.ko ... Installing to /lib/modules/.../updates/dkms/
apple-ib-tb.ko   ... Installing to /lib/modules/.../updates/dkms/
apple-ib-als.ko  ... Installing to /lib/modules/.../updates/dkms/
```

### 5d — Load modules and test

```bash
sudo modprobe apple-ibridge
sudo modprobe apple-ib-tb
sudo modprobe apple-ib-als

# Trigger USB rebind to activate the Touch Bar display
echo '1-3' | sudo tee /sys/bus/usb/drivers/usb/unbind
sleep 1
echo '1-3' | sudo tee /sys/bus/usb/drivers/usb/bind
sleep 2
```

The Touch Bar should light up and show content.

### 5e — Make it persistent across reboots

```bash
# Load modules on boot
cat <<EOF | sudo tee /etc/modules-load.d/apple-touchbar.conf
apple-ibridge
apple-ib-tb
apple-ib-als
EOF

# Create systemd service for USB rebind
sudo tee /etc/systemd/system/macbook-quirks.service << 'EOF'
[Unit]
Description=Re-enable MacBook 14,3 TouchBar
After=multi-user.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 2
ExecStart=/bin/sh -c "echo '1-3' > /sys/bus/usb/drivers/usb/unbind"
ExecStart=/bin/sh -c "echo '1-3' > /sys/bus/usb/drivers/usb/bind"
RemainAfterExit=yes
TimeoutSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable macbook-quirks.service
sudo reboot
```

After reboot verify:

```bash
lsmod | grep apple_ib
# Should show: apple_ibridge, apple_ib_tb, apple_ib_als

sudo systemctl status macbook-quirks.service
# Should show: active (exited)
```

### 5f — Optional: configure Touch Bar mode

```bash
# Default to function keys (F1-F12) instead of media controls
cat <<EOF | sudo tee /etc/modprobe.d/apple_ib_tb.conf
options apple_ib_tb fnmode=2
options apple_ib_tb idle_timeout=60
EOF

sudo modprobe -r apple_ib_tb
sudo modprobe apple_ib_tb
```

Available `fnmode` values: `0` = media keys only, `1` = fn key switches modes, `2` = function keys by default.

> **Note:** The USB rebind workaround (`1-3` unbind/bind) is needed due to a known Linux/usbmuxd initialization issue with the T1 iBridge. Follow upstream progress at https://github.com/roadrunner2/macbook12-spi-driver/issues/42

> **Driver source:** https://github.com/almas/macbook12-spi-driver (fork of roadrunner2/macbook12-spi-driver)

---

## Step 6: Fix Webcam (FaceTime HD)

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

## Step 7: Fix WiFi (2.4GHz + 5GHz)

The 2017 MacBook Pro uses a **Broadcom BCM43602** chip. The `brcmfmac` driver is built into the T2 kernel. With the right NVRAM firmware configuration file, both 2.4GHz and 5GHz bands work simultaneously.

> ⚠️ **Do NOT install `broadcom-wl`** — it conflicts with `brcmfmac` and breaks WiFi entirely.

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

### 7c — Enable 5GHz with the NVRAM configuration fix

The key to enabling both bands simultaneously is the `boardflags3` value in the NVRAM config file. The value `0xC0000303` enables both 2.4GHz and 5GHz bands. Without this file only 2.4GHz works.

First find your MAC address:

```bash
ip link show wlp3s0 | grep ether
# Note the MAC address e.g. 00:90:4c:0d:f4:3e
```

Back up the existing config and create the new one:

```bash
# Back up existing config
sudo cp /lib/firmware/brcm/brcmfmac43602-pcie.txt \
  /lib/firmware/brcm/brcmfmac43602-pcie.txt.bak

# Create the new NVRAM config with 5GHz support
sudo tee /lib/firmware/brcm/brcmfmac43602-pcie.txt << 'EOF'
sromrev=11
subvid=0x14e4
boardtype=0x61b
boardrev=0x1421
vendid=0x14e4
devid=0x43ba
macaddr=YOUR_MAC_ADDRESS
ccode=YOUR_COUNTRY_CODE
regrev=245
boardflags=0x10401001
boardflags2=0x00000002
boardflags3=0xC0000303
aa2g=7
aa5g=7
agbg0=133
agbg1=133
agbg2=133
aga0=71
aga1=71
aga2=71
txchain=7
rxchain=7
antswitch=0
EOF
```

> Replace `YOUR_MAC_ADDRESS` with your actual MAC address from `ip link show wlp3s0 | grep ether`. Replace `YOUR_COUNTRY_CODE` with your country code (e.g. `US`, `GB`, `TR`, `DE`).

> **Credit:** The `boardflags3=0xC0000303` discovery is from Andy Holst via https://gist.github.com/almas/5f75adb61bccf604b6572f763ce63e3e

### 7d — Set regulatory domain

```bash
# Set your country code (US, GB, TR, DE, etc.)
sudo iw reg set YOUR_COUNTRY_CODE

# Make permanent
sudo nano /etc/default/crda
# Add or change: REGDOMAIN=YOUR_COUNTRY_CODE
```

### 7e — Reload the driver and verify

```bash
sudo modprobe -r brcmfmac_wcc
sudo modprobe -r brcmfmac
sudo modprobe brcmfmac
sleep 3

# Scan for networks — 5GHz shows as freq 5000MHz+
sudo iw dev wlp3s0 scan | grep -E "SSID|freq"
```

You should see both 2.4GHz (~2400MHz) and 5GHz (~5000MHz+) networks listed.

### 7f — Find your WiFi interface name

```bash
ip link show | grep wl
# Interface is likely wlp3s0, not wlan0
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

## Step 8: Keyboard Backlight

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

## Step 9: Temperature & Fan Monitoring (Optional but Recommended)

Install `lm-sensors` to monitor fan speeds and temperatures from `applesmc`:

```bash
sudo apt install lm-sensors
```

Run with:

```bash
sensors
```

Expected output includes an `applesmc-acpi-0` section showing both fans and all temperature sensors:

```
applesmc-acpi-0
Adapter: ACPI interface
Left side  : 2603 RPM  (min = 2160 RPM, max = 5927 RPM)
Right side : 2412 RPM  (min = 2000 RPM, max = 5489 RPM)
TC0P:         +58.2°C
TG0P:         +56.8°C
...
```

This confirms fan control is working via `applesmc`. If the `applesmc-acpi-0` section is missing, the module isn't loaded — check with `lsmod | grep applesmc`.

---

## Step 10: Restore T1 Firmware (Critical)

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
4. Back up WiFi firmware using the t2linux script (Step 7a)
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
| WiFi 2.4GHz | `sudo iw dev wlp3s0 scan \| grep freq` | Shows ~2400MHz networks |
| WiFi 5GHz | `sudo iw dev wlp3s0 scan \| grep freq` | Shows ~5000MHz+ networks |
| Webcam | `ls /dev/video*` | `/dev/video0` present |
| Webcam driver | `lsmod \| grep facetimehd` | Module listed |
| Touch Bar modules | `lsmod \| grep apple_ib` | `apple_ibridge`, `apple_ib_tb`, `apple_ib_als` listed |
| Touch Bar display | Visual check | Shows content on boot |
| Touch Bar service | `systemctl status macbook-quirks.service` | Active (exited) |
| Audio driver | `lsmod \| grep snd_hda_codec_cs8409` | Module listed |
| Audio output | `speaker-test -c 2 -t wav` | Sound from speakers |
| Microphone | `pactl list sources short` | Shows `alsa_input...analog-stereo` |
| Keyboard backlight | `cat /sys/class/leds/spi::kbd_backlight/brightness` | Returns your set value (e.g. 100) |
| Fan Control | `sensors` | Shows fan RPM and temperatures from `applesmc-acpi-0` |
| Bluetooth | Settings → Bluetooth | Devices discoverable |

---

## Known Caveats

**Internal speakers / headphone jack:** Work after installing the `snd_hda_macbookpro` out-of-tree driver (Step 4). The driver must be manually reinstalled after every kernel update — it is not a DKMS module and does not rebuild automatically.

**Touch Bar:** Works after installing the patched `macbook12-spi-driver` DKMS module and enabling the `macbook-quirks.service` systemd service (Step 5). The driver requires kernel API patches for 6.x compatibility. `tiny-dfr` and `hid-appletb-kbd` are for T2 Macs only — do not install them on T1.

**5GHz WiFi:** Works with the NVRAM config fix in Step 7c using `boardflags3=0xC0000303`. Without this config file only 2.4GHz is available.

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
| BCM43602 5GHz NVRAM fix (gist) | https://gist.github.com/almas/5f75adb61bccf604b6572f763ce63e3e |
| macbook12-spi-driver (Touch Bar) | https://github.com/almas/macbook12-spi-driver |
| Touch Bar USB rebind issue | https://github.com/roadrunner2/macbook12-spi-driver/issues/42 |
| snd_hda_macbookpro (audio driver) | https://github.com/davidjo/snd_hda_macbookpro |
| t2linux Discord | https://discord.com/invite/68MRhQu |

---

> **Tested on:** MacBookPro14,3 · Ubuntu 24.04 LTS · T1 chip
>
> Kernel versions tested: T2 Kernel 6.19.10-2-t2-noble
>
> Contributions and corrections welcome — open an issue or PR.
