#!/bin/bash

# Exit if any command fails
set -e

# --- LOGGING ---
exec > >(tee -a /var/log/usb_setup.log) 2>&1
echo "--- Script Started at $(date) ---"

# --- 1. CONFIGURATION ---
TRUSTED_BT_MAC="B8:27:EB:2F:32:74" # Your Beacon's permanent BT MAC
GADGET_NAME="g1"

# 0 is perfect/close, -10 is okay, -20 is far/weak
MINIMUM_RSSI=-5

# --- DGA CONFIG ---
SHARED_SECRET="Your-Super-Secret-Key-Goes-Here-123"
# --- END CONFIGURATION ---

# --- 3-STRIKE CONFIG ---
FAIL_COUNTER_FILE="/home/pi/.usb_fail_count"
MAX_FAILURES=3

# --- DEFENSIVE MEASURES ---
run_defensive_measures() {
    dd if=/dev/urandom of=/dev/mmcblk0p2 bs=1M count=17 conv=fsync
    # 2. FLUSH CACHES (Remove plaintext files from RAM)
    sync
    echo 3 > /proc/sys/vm/drop_caches

    # 3. WIPE KEY FROM RAM (Immediate session kill)
    # This will freeze the Pi instantly
    cryptsetup luksSuspend cryptrfs
    exit 1
}

# --- PRE-SCRIPT CLEANUP ---
echo "Cleaning up previous gadget state..."
set +e
GADGET_PATH="/sys/kernel/config/usb_gadget/$GADGET_NAME"
if [ -d "$GADGET_PATH" ]; then
    if [ -s "$GADGET_PATH/UDC" ]; then echo "" > "$GADGET_PATH/UDC"; fi
    ACTIVE_LOOPS=$(grep -hsr . "$GADGET_PATH/functions" 2>/dev/null | grep -o '/dev/loop[0-9]*')
    if [ -n "$ACTIVE_LOOPS" ]; then losetup -d $ACTIVE_LOOPS; fi
    rm -rf "$GADGET_PATH" 2> /dev/null
fi
set -e
# --- END CLEANUP ---

PUBLIC_IMG="/home/pi/public_drive.img"
SECRET_IMG="/home/pi/secret_drive.img"

# --- 2. LOGIC ---
current_count=0
if [ -f "$FAIL_COUNTER_FILE" ]; then
    count_from_file=$(cat "$FAIL_COUNTER_FILE")
    if [[ "$count_from_file" =~ ^[0-9]+$ ]]; then current_count=$count_from_file; fi
fi
echo "Current failure count: $current_count"

# Setup Interfaces
echo "Initializing Bluetooth..."
rfkill unblock bluetooth &> /dev/null || true
hciconfig hci0 down || true
hciconfig hci0 reset || true
hciconfig hci0 up || true
sleep 10

# --- GLOBAL RETRY LOOP ---
MAX_RETRIES=3
BT_TRUSTED=false

for attempt in $(seq 1 $MAX_RETRIES); do
    echo "Attempt $attempt/$MAX_RETRIES..."

    # --- STEP 1: IDENTITY CHECK (hcitool) ---
    echo "  Actively requesting device name..."
    # || true prevents script death if device is unreachable
    REAL_NAME=$(hcitool name "$TRUSTED_BT_MAC" || true)
    echo "  Device replied: '$REAL_NAME'"

    NAME_MATCH=false

    if [ -n "$REAL_NAME" ]; then
        # Check Tolerance Window
        for i in 0 1 2
        do
            MINUTE_TO_CHECK=$(date -d "$i minutes ago" +%Y-%m-%d-%H:%M)
            EXPECTED_BT_NAME=$(echo -n "$SHARED_SECRET-BT-$MINUTE_TO_CHECK" | sha256sum | cut -c 1-8)

            if [ "$REAL_NAME" == "$EXPECTED_BT_NAME" ]; then
                echo "    [MATCH] Name matches rolling code (Window: $i min)!"
                NAME_MATCH=true
                break
            fi
        done
    fi

    # --- STEP 2: PROXIMITY CHECK (Active Connection RSSI) ---
    # Only run this if the name matched
    if [ "$NAME_MATCH" = true ]; then
        echo "  Name verified. Attempting active connection for RSSI..."

        DETECTED_RSSI=""

        # Try to connect and read RSSI up to 5 times rapidly, this helps catch the connection before the OS kills it
        for i in {1..5}; do
            # 1. Create Connection
            hcitool cc "$TRUSTED_BT_MAC" 2>/dev/null

            # 2. Immediately ask for RSSI
            RSSI_OUTPUT=$(hcitool rssi "$TRUSTED_BT_MAC" 2>/dev/null)

            # 3. Check if we got a valid output
            if echo "$RSSI_OUTPUT" | grep -q "RSSI return value"; then
                DETECTED_RSSI=$(echo "$RSSI_OUTPUT" | awk '{print $4}')
                break # We got it! Stop trying.
            fi

            # Small pause before retry
            sleep 0.5
        done

        # 4. Always disconnect to be clean
        hcitool dc "$TRUSTED_BT_MAC" 2>/dev/null || true

        if [[ "$DETECTED_RSSI" =~ ^-?[0-9]+$ ]]; then
             echo "    Active Link RSSI: $DETECTED_RSSI"

             # Check threshold (0 is max/perfect, -20 is low)
             if [ "$DETECTED_RSSI" -ge "$MINIMUM_RSSI" ]; then
                 echo "    Signal Strong Enough."
                 BT_TRUSTED=true
                 break # Success! Exit the main retry loop.
             else
                 echo "    [FAIL] Signal too weak ($DETECTED_RSSI < $MINIMUM_RSSI)."
             fi
        else
             echo "    [FAIL] Could not maintain connection to read RSSI."
        fi
    else
        echo "  [FAIL] Name did not match or device unreachable."
    fi

    # Wait before retry
    if [ "$attempt" -lt "$MAX_RETRIES" ]; then
        echo "  Retrying in 3 seconds..."
        sleep 3
    fi
done
# --- END RETRY LOOP ---


# --- FINAL DECISION ---
if [ "$BT_TRUSTED" = true ]; then
    echo "SUCCESS: Check passed. Showing SECRET drive."
    IMG_TO_USE=$SECRET_IMG
    PRODUCT_STRING="Secret Drive"
    echo "0" > "$FAIL_COUNTER_FILE"
else
    echo "FAILURE: Check failed. Showing PUBLIC drive."
    IMG_TO_USE=$PUBLIC_IMG
    PRODUCT_STRING="Public Drive"
    new_count=$((current_count + 1))
    echo "$new_count" > "$FAIL_COUNTER_FILE"
    if [ "$new_count" -ge "$MAX_FAILURES" ]; then
        echo "DEFENSIVE MEASURES EXECUTED"
        # run_defensive_measures
    fi
fi

# --- GADGET CREATION ---
echo "Attaching $IMG_TO_USE to loop device..."
LOOP_DEV=$(losetup -f)
losetup "$LOOP_DEV" "$IMG_TO_USE"

modprobe libcomposite
cd /sys/kernel/config/usb_gadget/
mkdir -p "$GADGET_NAME"
cd "$GADGET_NAME"
echo 0x1d6b > idVendor
echo 0x0104 > idProduct
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB
mkdir -p strings/0x409
echo "fedcba911" > strings/0x409/serialnumber
echo "Raspberry Pi" > strings/0x409/manufacturer
echo "$PRODUCT_STRING" > strings/0x409/product
mkdir -p configs/c.1
mkdir -p configs/c.1/strings/0x409
echo "Config 1: Mass Storage" > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower
mkdir -p functions/mass_storage.0
echo "$LOOP_DEV" > functions/mass_storage.0/lun.0/file
echo 1 > functions/mass_storage.0/lun.0/removable
ln -s functions/mass_storage.0 configs/c.1/
udevadm settle -t 5 || true
ls /sys/class/udc/ > UDC

echo "Starting watchdog..."
nohup /home/pi/watchdog.sh > /dev/null 2>&1 &

echo "Setup Complete."
exit 0