#!/bin/bash

# A script to safely disable and clean up the USB gadget.
# MUST be run with sudo.

# --- Configuration ---
GADGET_NAME="g1"
GADGET_PATH="/sys/kernel/config/usb_gadget/$GADGET_NAME"

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use 'sudo'." >&2
  exit 1
fi

echo "--- Starting USB Gadget Cleanup ---"
set +e # Temporarily disable exit-on-error to ensure cleanup finishes

if [ -d "$GADGET_PATH" ]; then
    echo "Gadget '$GADGET_NAME' found. Cleaning up..."

    # 1. Deactivate the gadget by unbinding it from the USB controller
    if [ -s "$GADGET_PATH/UDC" ]; then
        echo "Deactivating gadget..."
        echo "" > "$GADGET_PATH/UDC" || true
    fi

    # First, find which loop devices are currently being used by this gadget
    ACTIVE_LOOPS=$(grep -hsr . "$GADGET_PATH/functions" 2>/dev/null | grep -o '/dev/loop[0-9]*' | sort -u || true)

    # CRITICAL STEP: "Eject" the backing files from the gadget functions.
    # This releases the kernel's lock on the loop device.
    echo "Releasing backing files from gadget..."
    find "$GADGET_PATH/functions" -name "file" 2>/dev/null | while read -r file_path; do
        echo "" > "$file_path" || true
    done

    # 2. Detach the loop devices
    if [ -n "$ACTIVE_LOOPS" ]; then
        echo "Detaching loop devices: $ACTIVE_LOOPS"
        sudo losetup -d $ACTIVE_LOOPS || true
    fi

    # 3. Recursively remove the old gadget directory.
    echo "Removing old gadget configuration..."
    rm -rf "$GADGET_PATH" 2> /dev/null
    echo "Cleanup complete."
else
    echo "Gadget '$GADGET_NAME' not found. Nothing to do."
fi

set -e # Re-enable exit-on-error
echo "--- USB Gadget Cleanup Complete ---"