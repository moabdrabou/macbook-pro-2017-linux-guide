# Ubuntu 24.04 LTS on MacBook Pro 2017 (Touch Bar) — Fix Guide

> Covers: **Webcam**, **Touch Bar**, and **Audio** fixes for `MacBookPro14,2` (13") and `MacBookPro14,3` (15") running Ubuntu 24.04 LTS.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Step 1 — Install the T2 Kernel](#step-1--install-the-t2-kernel)
- [Step 2 — Add Required Kernel Parameters](#step-2--add-required-kernel-parameters)
- [Step 3 — Load apple-bce Module on Boot](#step-3--load-apple-bce-module-on-boot)
- [Step 4 — Fix Audio](#step-4--fix-audio)
- [Step 5 — Fix Touch Bar](#step-5--fix-touch-bar)
- [Step 6 — Fix Webcam (FaceTime HD)](#step-6--fix-webcam-facetime-hd)
- [Step 7 — Fix WiFi (All Bands including 5GHz)](#step-7--fix-wifi-all-bands-including-5ghz)
- [Verification Checklist](#verification-checklist)
- [Known Caveats](#known-caveats)
- [Resources](#resources)

---

## Prerequisites

First, confirm your exact model identifier:

```bash
sudo dmidecode -s system-product-name
```

Expected output: `MacBookPro14,2` (13-inch) or `MacBookPro14,3` (15-inch).

Make sure you have internet access (via USB-C adapter/Ethernet or external USB WiFi dongle if internal WiFi isn't working yet).

---

## Step 1 — Install the T2 Kernel

The stock Ubuntu kernel lacks support for Apple T1/T2 hardware. Installing the T2 kernel enables the **keyboard, trackpad, Touch Bar, audio, and fan** control.

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

> **Note:** If you get `E: Unable to locate package linux-t2` — it means Step 2 was skipped or failed. The release-specific repo (`noble`) must be appended to `t2.list` for Ubuntu 24.04. Two variants are available: `linux-t2` (Mainline, newer patches) and `linux-t2-lts` (LTS, more stable). Either works.

Reboot and at the GRUB menu, select the **`linux-t2`** kernel entry.

> **Repo:** https://github.com/t2linux/T2-Debian-and-Ubuntu-Kernel

---

## Step 2 — Add Required Kernel Parameters

These parameters are required for audio and proper hardware passthrough.

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

---

## Step 3 — Load apple-bce Module on Boot

The `apple-bce` module handles the Apple T1 Bridge Controller (keyboard, trackpad, Touch Bar communication).

### Load on boot

```bash
echo apple-bce | sudo tee /etc/modules-load.d/t2.conf
```

### Load on early boot (recommended — needed for LUKS or keyboard at boot)

```bash
sudo su
cat <<EOF >> /etc/initramfs-tools/modules
# Required for Apple T1/T2 hardware (keyboard, trackpad, audio)
snd
snd_pcm
apple-bce
EOF
update-initramfs -u
exit
```

---

## Step 4 — Fix Audio

### 4a — Install audio config files

```bash
sudo git clone https://github.com/kekrby/t2-better-audio.git /tmp/t2-better-audio
cd /tmp/t2-better-audio
./install.sh
sudo rm -r /tmp/t2-better-audio
```

Reboot, then verify the T2 audio card is detected:

```bash
sed -n "s/.*\(AppleT2.*\) -.*/\1/p" /proc/asound/cards
# Expected output: AppleT2xN  (where N is a number)
# If output is just "AppleT2" — the driver needs updating (see note below)
# If no output — the T2 kernel from Step 1 is not loaded
```

Also verify with:

```bash
aplay -l
# Should list an Apple T2 card entry
```

### 4b — Switch to PipeWire (recommended)

Ubuntu 24.04 uses PipeWire by default. If for some reason you're on PulseAudio, switch to PipeWire for the best experience (headphone auto-switching, lower latency):

```bash
sudo apt install pipewire pipewire-pulse wireplumber
systemctl --user enable --now pipewire pipewire-pulse wireplumber
```

---

### ⚠️ Kernel 6.17+ HWE Note

If you upgrade to the Ubuntu HWE kernel (6.17+) and audio stops working (sound shows as playing but no output), this is a known regression. The Cirrus Logic CS8409 driver was reorganized in kernel 6.17.

**Fix:** Stay on the T2 kernel, or manually install the updated driver from Launchpad:

```bash
# Download the kernel source package for Ubuntu 24.04
wget https://launchpad.net/~canonical-kernel-security-team/+archive/ubuntu/ppa/+build/32347426/+files/linux-source-6.17.0_6.17.0-19.19_all.deb

sudo dpkg -i linux-source-6.17.0_6.17.0-19.19_all.deb
```

> Follow the full tutorial at: https://9to5linux.com/how-to-fix-no-sound-issue-on-macbook-pro-with-linux-kernel-6-17-and-later

---

## Step 5 — Fix Touch Bar

### 5a — Install tiny-dfr (Touch Bar display manager)

```bash
# The T2 apt repo was added in Step 1
sudo apt install tiny-dfr
sudo reboot
```

The Touch Bar should light up after reboot.

### 5b — Set Touch Bar mode

Available modes:

| Mode | Behavior |
|------|----------|
| `0`  | Function keys (F1–F12) |
| `1`  | Media/brightness controls (default Bootcamp-style) |
| `2`  | Off |

```bash
cat <<EOF | sudo tee /etc/modprobe.d/tb.conf
options hid-appletb-kbd mode=1
EOF

# Apply without rebooting
sudo modprobe -r hid-appletb-kbd
sudo modprobe hid-appletb-kbd
```

### 5c — Suspend/resume fix for Touch Bar

If the Touch Bar goes blank after waking from suspend, create this hook:

```bash
sudo nano /usr/lib/systemd/system-sleep/touchbar.sh
```

Paste:

```bash
#!/bin/bash
case $1/$2 in
  pre/*)
    modprobe -r hid_appletb_kbd
    modprobe -r hid_appletb_bl
    ;;
  post/*)
    sleep 4
    modprobe hid_appletb_bl
    sleep 2
    modprobe hid_appletb_kbd
    ;;
esac
```

Make it executable:

```bash
sudo chmod +x /usr/lib/systemd/system-sleep/touchbar.sh
```

---

## Step 6 — Fix Webcam (FaceTime HD)

The 2017 MacBook Pro has an **Apple FaceTime HD PCIe camera**. It requires a reverse-engineered driver (`facetimehd`) and firmware extracted from Apple's Windows driver.

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

Expected output includes:

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
lsusb | grep -i apple
# Look for: Apple, Inc. FaceTime HD Camera (Built-in)

ls /dev/video*
# Should show /dev/video0

# Quick test with ffplay (install with: sudo apt install ffmpeg)
ffplay /dev/video0
```

---

## Step 7 — Fix WiFi (All Bands including 5GHz)

The 2017 MacBook Pro uses a **Broadcom BCM43602** chip. Without proper firmware, Linux defaults to a generic driver that only sees 2.4GHz networks and has weak signal. The fix requires copying the WiFi firmware from macOS to Linux.

> ⚠️ **Important:** Do NOT install `broadcom-wl` — it breaks things. The correct driver is `brcmfmac` which is already built into the T2 kernel. The issue is missing firmware files, not the driver itself.

### 7a — Copy firmware from macOS (do this while still in macOS)

Before reinstalling Ubuntu, run these commands in macOS Terminal to copy the firmware to your USB drive:

```bash
# Find your USB mount point
diskutil list

# Copy WiFi firmware files to USB (replace YOUR_USB with your volume name)
sudo mkdir -p /Volumes/YOUR_USB/wifi-firmware
sudo cp /usr/share/firmware/wifi/* /Volumes/YOUR_USB/wifi-firmware/ 2>/dev/null
sudo cp /private/var/db/PersistentSystemInstallation/firmware/WiFi/* /Volumes/YOUR_USB/wifi-firmware/ 2>/dev/null

# Also try the standalone path
sudo cp /usr/standalone/firmware/wifi/* /Volumes/YOUR_USB/wifi-firmware/ 2>/dev/null
```

Alternatively, use the official t2linux firmware script — download it on macOS:

```bash
curl -OL https://wiki.t2linux.org/tools/firmware.sh
chmod +x firmware.sh
sudo ./firmware.sh
```

This script automatically finds and packages the correct firmware files for your Mac model.

### 7b — Install firmware on Ubuntu

After booting into Ubuntu, copy the firmware files to the correct location:

```bash
# Create the firmware directory
sudo mkdir -p /lib/firmware/brcm

# Copy from USB (replace YOUR_USB_MOUNT with your actual mount point)
sudo cp /media/$USER/YOUR_USB/wifi-firmware/* /lib/firmware/brcm/

# Or if you used the t2linux script, it produces a tar.gz — extract it:
# sudo tar -xzf wifi-firmware.tar.gz -C /lib/firmware/brcm/
```

### 7c — Fix 5GHz by setting country code

The BCM43602 chip defaults to country code `X0` which Linux doesn't support, blocking 5GHz channels. Fix it:

```bash
# Check current country code
iw reg get

# Set regulatory domain — use your actual country code (TR for Turkey, US, GB, DE, etc.)
sudo iw reg set TR
```

Make it permanent:

```bash
sudo nano /etc/default/crda
# Add or change: REGDOMAIN=TR
```

Also create a firmware config file to set it at the driver level:

```bash
# Find your MAC address
ip link show | grep -A1 wlan
# Note the MAC address e.g. aa:bb:cc:dd:ee:ff

sudo nano /lib/firmware/brcm/brcmfmac43602-pcie.txt
```

Add these contents (replace the MAC address with yours):

```
# Firmware configuration for BCM43602 - MacBook Pro 2017
boardtype=0x073e
boardrev=0x1101
boardflags=0x00080001
boardflags2=0x00000000
sromrev=11
ccode=TR
regrev=0
macaddr=aa:bb:cc:dd:ee:ff
```

### 7d — Reload the driver

```bash
sudo modprobe -r brcmfmac_wcc
sudo modprobe -r brcmfmac
sudo modprobe brcmfmac
```

### 7e — Verify 5GHz networks are visible

```bash
# Scan for networks and check bands
sudo iw dev wlan0 scan | grep -E "SSID|freq"
# 5GHz networks use frequencies 5000MHz+
# 2.4GHz networks use frequencies around 2400MHz

# Check signal and connection info
iwconfig wlan0

# Confirm country code applied
iw reg get
```

### ⚠️ wpa_supplicant regression note

If WiFi connects but immediately drops or won't authenticate despite correct password, this is a known regression in `wpa_supplicant 2.11`. Fix it by disabling offloading:

```bash
# Add to kernel parameters in /etc/default/grub
# GRUB_CMDLINE_LINUX="... brcmfmac.feature_disable=0x82000"
sudo nano /etc/default/grub

# Apply
sudo update-grub
sudo reboot
```

---

## Verification Checklist

| Component   | Command                                                         | Expected Result                        |
|-------------|------------------------------------------------------------------|----------------------------------------|
| Kernel      | `uname -r`                                                       | Contains `-t2`                         |
| Kernel params | `cat /proc/cmdline`                                            | Contains `intel_iommu=on iommu=pt`     |
| Audio card  | `sed -n "s/.*\(AppleT2.*\) -.*/\1/p" /proc/asound/cards`       | `AppleT2xN`                            |
| Audio list  | `aplay -l`                                                       | Lists Apple T2 card                    |
| Touch Bar   | Visual check                                                     | Lights up after `tiny-dfr` + reboot    |
| Webcam      | `ls /dev/video*`                                                 | `/dev/video0` present                  |
| Webcam driver | `lsmod | grep facetimehd`                                      | Module listed                          |
| WiFi bands    | `sudo iw dev wlan0 scan \| grep freq`                           | Shows 5000MHz+ frequencies             |
| WiFi country  | `iw reg get`                                                     | Shows your country code                |

---

## Known Caveats

- **Microphone**: The `t2-better-audio` script fixes speakers and headphone jack. Internal microphone support may vary — check the [t2linux audio guide](https://wiki.t2linux.org/guides/audio-config/) for DSP mic config.
- **WiFi signal strength**: Even after the fix, signal may be weaker than macOS. This is a known limitation of the Linux brcmfmac driver on BCM43602. Positioning closer to the router helps.
- **broadcom-wl**: Do NOT install this package — it conflicts with `brcmfmac` and breaks WiFi entirely.
- **DKMS & kernel updates**: The `facetimehd` driver is installed as a DKMS module, so it should rebuild automatically on kernel updates. If the webcam breaks after a kernel update, run `sudo dkms autoinstall`.
- **Secure Boot**: Must be disabled in Apple's Startup Security Utility for the T2 kernel to load.

---

## Resources

| Resource | URL |
|----------|-----|
| t2linux Wiki | https://wiki.t2linux.org |
| t2linux Ubuntu/Debian Kernel | https://github.com/t2linux/T2-Debian-and-Ubuntu-Kernel |
| t2linux Audio Guide | https://wiki.t2linux.org/guides/audio-config/ |
| t2-better-audio | https://github.com/kekrby/t2-better-audio |
| tiny-dfr (Touch Bar) | https://github.com/AsahiLinux/tiny-dfr |
| facetimehd driver | https://github.com/patjak/facetimehd |
| facetimehd firmware | https://github.com/patjak/facetimehd-firmware |
| Kernel 6.17 audio fix | https://9to5linux.com/how-to-fix-no-sound-issue-on-macbook-pro-with-linux-kernel-6-17-and-later |
| t2linux WiFi & Bluetooth Guide | https://wiki.t2linux.org/guides/wifi-bluetooth/ |
| t2linux firmware script | https://wiki.t2linux.org/tools/firmware.sh |
| t2linux Discord | https://discord.com/invite/68MRhQu |

---

> **Tested on:** MacBookPro14,2 / MacBookPro14,3 · Ubuntu 24.04 LTS · T2 Kernel
>
> Contributions and corrections welcome — open an issue or PR.
