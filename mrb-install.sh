#!/bin/bash
# MRB Wi-Fi Portal installer (v2)
# Run from the cloned repo directory:  sudo ./mrb-install.sh
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST=/opt/mrb-portal

echo "=== MRB Wi-Fi Portal Installer ==="

if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo: sudo ./mrb-install.sh"
  exit 1
fi

# --- Step 1: Clean up any previous install -----------------------------------
echo "[1/9] Cleaning previous install..."
systemctl stop mrb-portal 2>/dev/null || true
systemctl disable mrb-portal 2>/dev/null || true
rm -f /etc/systemd/system/mrb-portal.service
rm -rf "$DEST"
nmcli connection delete "MRB_Setup" 2>/dev/null || true
nmcli connection delete "MRB_Setup 1" 2>/dev/null || true
chattr -i /etc/resolv.conf 2>/dev/null || true   # remove old v1 immutable flag if present
systemctl daemon-reload

# --- Step 2: Dependencies ----------------------------------------------------
echo "[2/9] Installing dependencies..."
apt update
apt install -y python3 python3-venv network-manager nftables

# --- Step 3: DNS via NetworkManager -----------------------------------------
echo "[3/9] Configuring DNS..."
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/dns.conf << 'DNSEOF'
[main]
dns=default
DNSEOF
systemctl restart NetworkManager

# --- Step 4: Folders + service user -----------------------------------------
echo "[4/9] Creating folders and service user..."
mkdir -p "$DEST/templates"
useradd -r -s /usr/sbin/nologin mrbportal 2>/dev/null || true

# --- Step 5: Copy application files from repo --------------------------------
echo "[5/9] Copying application files..."
cp "$REPO_DIR/app.py" "$DEST/app.py"
cp "$REPO_DIR/templates/index.html" "$DEST/templates/index.html"
cp "$REPO_DIR/start.sh" "$DEST/start.sh"
chmod +x "$DEST/start.sh"

# --- Step 6: Virtualenv + Flask ---------------------------------------------
echo "[6/9] Building virtualenv..."
python3 -m venv "$DEST/venv"
"$DEST/venv/bin/pip" install --upgrade pip
"$DEST/venv/bin/pip" install flask

# --- Step 7: nftables 80 -> 8080 redirect -----------------------------------
echo "[7/9] Installing nftables redirect..."
cp "$REPO_DIR/nftables.conf" /etc/nftables.conf
systemctl enable --now nftables

# --- Step 8: Ownership -------------------------------------------------------
echo "[8/9] Fixing ownership..."
chown -R mrbportal:mrbportal "$DEST"
chmod 750 "$DEST"

# --- Step 9: systemd service -------------------------------------------------
echo "[9/9] Installing systemd service..."
cp "$REPO_DIR/mrb-portal.service" /etc/systemd/system/mrb-portal.service
systemctl daemon-reload
systemctl enable mrb-portal
systemctl start mrb-portal

echo ""
echo "=== Done! ==="
echo "View logs:   sudo journalctl -u mrb-portal -f"
echo "Portal:      connect to Wi-Fi 'MRB_Setup' (password: mrbsetup), then open http://10.42.0.1"
