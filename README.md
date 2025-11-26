# DF-Assignment

This project transforms a Raspberry Pi Zero 2 W into a secure, self-encrypting USB storage device. It utilizes a Zymkey 4i HSM for hardware-backed encryption and implements a "Zero-Interaction" authentication protocol using Bluetooth Rolling Codes and RSSI proximity detection.

## Project File Tree


```
.
├── README.md
├── usb_setup.sh (main script for setting up USB drives, includes detection logic, self-destructing capabilities etc.) 
├── usb_cleanup.sh (script to cleanup active USB devices)
├── watchdog.sh (watchdog script that is activated upon the mounting of either public or secret drive)
└── bluetooth_beacon.sh (script for 2FA device to broadcast DGA Bluetooth network)
```


## Prerequisites

* **Hardware:**
    * Raspberry Pi Zero 2 W
    * Zymkey 4i Hardware Security Module
    * MicroSD Card (16GB+ recommended)
    * A secondary Raspberry Pi (or Linux device) to act as the 2FA Beacon
* **Software:**
    * Raspberry Pi Imager

---

## Installation Guide

### 1. Flash the Operating System
1.  Download and install the **Raspberry Pi Imager** from the official website: [https://www.raspberrypi.com/software/](https://www.raspberrypi.com/software/)
2.  Insert your MicroSD card into your computer.
3.  Open Raspberry Pi Imager.
4.  **Choose OS:** Select **Raspberry Pi OS (64-bit)**. Ensure you select the **Bookworm** release.
5.  **Choose Storage:** Select your MicroSD card.
6.  Click **Next** and configure your username (default used in scripts: `pi`), Wi-Fi credentials, and SSH access in the advanced settings menu.
7.  Write the OS to the card.

### 2. System Update & Configuration
Boot the Raspberry Pi with the new SD card and SSH into it. First, ensure all packages are up to date:

```bash
sudo apt update && sudo apt upgrade -y
```

Reboot:

```bash
sudo reboot
```

---

## 3. Configure USB Gadget Mode

Modify the following Raspberry Pi boot configuration files.

### 3.1 Edit ``/boot/firmware/config.txt``

Add this line:

```txt
dtoverlay=dwc2
```

### 3.2 Edit ``/boot/firmware/cmdline.txt``

Append the following (do NOT add a newline):

```txt
modules-load=dwc2,libcomposite
```

Reboot:

```bash
sudo reboot
```

---

## 4. Configure the Zymkey4i (Root Filesystem Encryption)

This project uses the **Zymkey4i** for secure operations and to encrypt the root filesystem.

Follow the official setup guide here: 
https://docs.zymbit.com/getting-started/zymkey4/quickstart/ and https://docs.zymbit.com/tutorials/encrypt-rfs/

This covers:

- Installing Zymkey software
- Pairing the device
- Initializing the secure element
- Encrypting the root filesystem
- Rebooting into the encrypted system

---

### 5. Install Project Scripts & Create Daemon Service

This project includes scripts that will run as a system daemon.

### 5.1 Copy Project Scripts

Clone the repository or copy the project files to the Raspberry Pi:

```bash
git clone https://github.com/rljh1/DF-Assignment.git
cd DF-Assignment
```


### 5.2 Create systemd Service for the USB gadget service

Create a new systemd service file:

```bash
sudo nano /etc/systemd/system/usb-gadget.service
```

Example service file content (replace the file path accordingly):


```ini
[Unit]
Description=USB Gadget Setup Service
# This tells the script to wait until both networking and bluetooth are ready.
After=network-online.target bluetooth.target
Wants=network-online.target bluetooth.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=<path to usb_setup.sh script>

[Install]
# This hooks your service into the standard "fully booted" target.
WantedBy=multi-user.target
```


Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable usb-gadget.service
sudo systemctl start usb-gadget.service
```

Check the service status:

```bash
systemctl status usb-gadget.service
```


## 6. Preparing Virtual Disk Images for USB Gadget


### 6.1 Create the virtual disk image files


```bash
sudo dd if=/dev/zero of=<path to folder>/public_drive.img bs=1M count=<desired size in MB)
sudo dd if=/dev/zero of=<path to folder>/secret_drive.img bs=1M count=<desired size in MB)
```

---

### 6.2 Create partition table using fdisk

### Public drive:

```bash
sudo fdisk <path to folder>/public_drive.img
```

Inside fdisk, type the following keys (press Enter after each):

```\n
o
n
p
1
<enter>
<enter>
t
b
w
```

Repeat the *same fdisk steps* for the secret drive:

---

### 6.3 Map partitions and format them

```bash
sudo losetup -fP <path to public_drive.img>
sudo losetup -fP <path to secret_drive.img>
sudo losetup -a   # note which /dev/loopX is which
```

You should now have /dev/loopXp1 for each image.

Format the *partition*:

```bash
sudo mkfs.vfat -F 32 /dev/loop1p1   # for the public image loop
sudo mkfs.vfat -F 32 /dev/loop2p1   # for the secret image loop
```

Detach the loops:
```bash
sudo losetup -d /dev/loopX
sudo losetup -d /dev/loopY
```
---

## 7. Setup Complete

Your Raspberry Pi should now:

- Run Raspberry Pi OS 64-bit Bookworm
- Be configured for USB gadget mode
- Have your Zymkey4i setup and root filesystem encrypted
- Run your project scripts as a daemon via systemd

---
