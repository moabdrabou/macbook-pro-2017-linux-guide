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
# Add the T2 Ubuntu apt repository GPG key
curl -s --compressed "https://adityagarg8.github.io/t2-ubuntu-repo/KEY.gpg" \
  | gpg --dearmor \
  | sudo tee /etc/apt/trusted.gpg.d/t2-ubuntu-repo.gpg >/dev/null

# Add the repository source list
sudo curl -s --compressed \
  -o /etc/apt/sources.list.d/t2.list \
  "https://adityagarg8.github.io/t2-ubuntu-repo/t2.list"

# Update and install the T2 kernel
sudo apt update
sudo apt install linux-t2
```

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

---

## Known Caveats

- **Microphone**: The `t2-better-audio` script fixes speakers and headphone jack. Internal microphone support may vary — check the [t2linux audio guide](https://wiki.t2linux.org/guides/audio-config/) for DSP mic config.
- **WiFi**: Not covered in this guide. See the [t2linux WiFi guide](https://wiki.t2linux.org/guides/wifi-bluetooth/).
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
| t2linux Discord | https://discord.com/invite/68MRhQu |

---

> **Tested on:** MacBookPro14,2 / MacBookPro14,3 · Ubuntu 24.04 LTS · T2 Kernel
>
> Contributions and corrections welcome — open an issue or PR.
