#!/bin/bash

# --- 1. CONFIGURATION ---

SECRET_IMAGE_FILE="/home/pi/secret_drive.img"
PUBLIC_IMAGE_FILE="/home/pi/public_drive.img"
CLEANUP_SCRIPT="/home/pi/usb_cleanup.sh"
TIMEOUT=30
LUKS_DEVICE_NAME="cryptrfs"

# --- 2. SCRIPT ---

echo "Watchdog starting... looking for active drive."

# First, check if the SECRET drive is attached
LOOP_DEV_PATH=$(sudo losetup -a | grep "$SECRET_IMAGE_FILE" | awk -F: '{print $1}')
FILE_BEING_WATCHED=$SECRET_IMAGE_FILE

# If the secret drive isn't found, check for the PUBLIC drive
if [ -z "$LOOP_DEV_PATH" ]; then
    LOOP_DEV_PATH=$(sudo losetup -a | grep "$PUBLIC_IMAGE_FILE" | awk -F: '{print $1}')
    FILE_BEING_WATCHED=$PUBLIC_IMAGE_FILE
fi

# Robustness Check: If *neither* drive is mounted, do nothing.
if [ -z "$LOOP_DEV_PATH" ]; then
    echo "Error: No monitored image file is attached. Watchdog exiting."
    exit 1
fi

# We have a device to watch. Get its name (e.g., "loop1")
DEVICE_TO_WATCH=$(basename "$LOOP_DEV_PATH")

# Construct the full path to the kernel's statistics file
STAT_FILE="/sys/block/$DEVICE_TO_WATCH/stat"
echo "Watchdog started for /dev/$DEVICE_TO_WATCH (File: $FILE_BEING_WATCHED). Timeout is $TIMEOUT seconds."

# Get the initial I/O counter (reads + writes)
last_io_count=$(awk '{print $1 + $5}' "$STAT_FILE")

# Loop forever
while true; do
    sleep $TIMEOUT

    # Get the *current* I/O counter
    current_io_count=$(awk '{print $1 + $5}' "$STAT_FILE")

    # Compare the counters
    if [ "$last_io_count" -eq "$current_io_count" ]; then
        # --- TIMEOUT DETECTED ---
        echo "********************************************************"
        echo "INACTIVITY TIMEOUT REACHED! Locking device."
        echo "********************************************************"

        # 1. Sever the USB connection
        if [ -f "$CLEANUP_SCRIPT" ]; then
            sudo "$CLEANUP_SCRIPT"
        else
            echo "Warning: Cleanup script not found at $CLEANUP_SCRIPT"
        fi

        # 2. Detach the loop device
        sudo losetup -d "$LOOP_DEV_PATH"

        # 3. Destroy the FDE Master Key (Commented out as requested)
        sudo cryptsetup luksSuspend "$LUKS_DEVICE_NAME"

        echo "Device is locked and secure. Exiting watchdog."
        exit 0
    else
        # --- Activity Detected ---
        echo "Activity detected. Resetting timer."
        last_io_count=$current_io_count
    fi
done