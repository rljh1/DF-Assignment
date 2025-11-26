#!/bin/bash

# A script to broadcast a "Classic" Bluetooth beacon for a limited time, using a DGA-style "rolling code" for the name.
# MUST be run with sudo.

# --- 1. CONFIGURATION ---
BEACON_DURATION=300          # How long to beacon (in seconds)
SHARED_SECRET="Your-Super-Secret-Key-Goes-Here-123"
ORIGINAL_HOSTNAME="raspberrypi2fa" # Your Pi's normal name
# --- END CONFIGURATION ---


# --- DGA (Dynamic Name Generation) ---
# We use the current minute, so the key is stable for 60 seconds.
CURRENT_MINUTE=$(date +%Y-%m-%d-%H:%M)

# Generate the Bluetooth *Name* (not MAC)
GENERATED_BT_NAME=$(echo -n "$SHARED_SECRET-BT-$CURRENT_MINUTE" | sha256sum | cut -c 1-8)
# --- END DGA ---


# --- CLEANUP FUNCTION ---
# This function runs when the script exits (on timeout or Ctrl+C)
cleanup() {
    echo ""
    echo "Stopping Bluetooth beacon..."

    # Stop being discoverable
    sudo hciconfig hci0 noscan

    # Restore the original, permanent name
    # We ensure the interface is UP before changing the name back
    sudo hciconfig hci0 up
    sudo hciconfig hci0 name "$ORIGINAL_HOSTNAME"

    # Power down the hardware interface
    sudo hciconfig hci0 down

    # Restart the system Bluetooth service
    echo "Restarting system Bluetooth service..."
    sudo systemctl start bluetooth

    echo "Cleanup complete. Bluetooth is reset."
}

# This 'trap' ensures the 'cleanup' function runs when the script exits normally or if you interrupt it (Ctrl+C).
trap cleanup EXIT INT TERM

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use 'sudo'." >&2
  exit 1
fi

echo "--- Starting Classic Bluetooth Beacon ---"
echo "  DGA Name: $GENERATED_BT_NAME"
echo "  (Will run for $BEACON_DURATION seconds)"

# Stop the system service to prevent interference
echo "Stopping system Bluetooth service..."
sudo systemctl stop bluetooth
sleep 1

# --- Setup Classic Bluetooth Beacon ---
sudo rfkill unblock bluetooth &> /dev/null || true

# Bring the interface UP so we can talk to it
sudo hciconfig hci0 up

# Set the name (Now that it's up, this command will succeed)
sudo hciconfig hci0 name "$GENERATED_BT_NAME"

sudo hciconfig hci0 noauth

# Start broadcasting (piscan = Page and Inquiry Scan, i.e., "discoverable")
sudo hciconfig hci0 piscan
echo "Bluetooth Beacon is ON (Name: $GENERATED_BT_NAME)."

echo "--- Beacon is ON. (Press Ctrl+C to stop early) ---"
sleep $BEACON_DURATION

# After duration, the script will end, and the 'trap' will automatically call the 'cleanup' function.
exit 0