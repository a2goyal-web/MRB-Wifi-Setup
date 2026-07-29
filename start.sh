#!/bin/bash
set -u

AP_NAME="MRB_Setup"
LOCK=/run/mrb-portal.lock

# Prevent overlapping runs from stacking APs
exec 9>"$LOCK"
flock -n 9 || { echo "Another instance is running. Exiting."; exit 0; }

# Clean any leftover AP from a previous run
nmcli connection down "$AP_NAME" 2>/dev/null
nmcli connection delete "$AP_NAME" 2>/dev/null
nmcli connection delete "MRB_Setup 1" 2>/dev/null
sleep 2

echo "Waiting 30s for Wi-Fi to establish..."
sleep 30

FAIL_COUNT=0
while [ $FAIL_COUNT -lt 3 ]; do
    echo "Ping test (fail count: $FAIL_COUNT)..."
    if ping -c 3 -W 5 8.8.8.8 > /dev/null 2>&1; then
        echo "Internet connected. No AP needed."
        exit 0
    fi
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "Ping failed. Attempt $FAIL_COUNT of 3. Waiting 30s..."
    sleep 30
done

echo "3 ping failures. Starting AP portal..."
nmcli connection add type wifi ifname wlan0 con-name "$AP_NAME" autoconnect no ssid "$AP_NAME"
nmcli connection modify "$AP_NAME" 802-11-wireless.mode ap 802-11-wireless.band bg ipv4.method shared
nmcli connection modify "$AP_NAME" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "mrbsetup"
nmcli connection up "$AP_NAME"
sleep 3

# Run Flask from the venv, unprivileged, on 8080
exec sudo -u mrbportal /opt/mrb-portal/venv/bin/python3 /opt/mrb-portal/app.py
