#!/bin/bash

# ============================================================
#  MRB Wi-Fi Portal — One-File Installer
#  My Retail Buddy | For Operators, By Operators!
# ============================================================

echo ""
echo "============================================"
echo "  My Retail Buddy Wi-Fi Portal Installer"
echo "  For Operators, By Operators!"
echo "============================================"
echo ""

# ── Step 1: Clean up previous install ──────────────────────
echo "[1/8] Cleaning up previous install..."
systemctl stop mrb-portal 2>/dev/null
systemctl disable mrb-portal 2>/dev/null
rm -f /etc/systemd/system/mrb-portal.service
rm -rf /opt/mrb-portal
nmcli connection delete "MRB_Setup" 2>/dev/null
nmcli connection delete "MRB_Setup 1" 2>/dev/null
systemctl daemon-reload

# ── Step 2: Install dependencies ───────────────────────────
echo "[2/8] Installing dependencies..."
apt update -qq && apt install -y python3 python3-pip network-manager
pip3 install flask --break-system-packages -q

# ── Step 3: Fix resolv.conf ─────────────────────────────────
echo "[3/8] Fixing resolv.conf..."
chattr -i /etc/resolv.conf 2>/dev/null
echo "nameserver 8.8.8.8" > /etc/resolv.conf
chattr +i /etc/resolv.conf

if ! grep -q "dns=none" /etc/NetworkManager/NetworkManager.conf; then
    sed -i '/^\[main\]/a dns=none' /etc/NetworkManager/NetworkManager.conf
fi
systemctl restart NetworkManager
sleep 2

# ── Step 4: Create folder structure ────────────────────────
echo "[4/8] Creating folder structure..."
mkdir -p /opt/mrb-portal/templates

# ── Step 5: Copy logo from repo folder ─────────────────────
echo "[5/8] Copying logo..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/MRB_Logo.png" ]; then
    cp "$SCRIPT_DIR/MRB_Logo.png" /opt/mrb-portal/templates/logo.png
    echo "Logo copied from: $SCRIPT_DIR/MRB_Logo.png"
else
    echo "WARNING: MRB_Logo.png not found next to installer. Portal will run without logo."
    touch /opt/mrb-portal/templates/logo.png
fi

# ── Step 6: Create app.py ───────────────────────────────────
echo "[6/8] Creating app.py..."
cat > /opt/mrb-portal/app.py << 'EOF'
import subprocess, threading, time
from flask import Flask, render_template, request, redirect, send_file

app = Flask(__name__)

@app.route('/logo')
def logo():
    return send_file('/opt/mrb-portal/templates/logo.png', mimetype='image/png')

def get_wifi_networks():
    try:
        subprocess.run(['nmcli', 'dev', 'wifi', 'rescan'], capture_output=True)
        time.sleep(2)
        result = subprocess.run(
            ['nmcli', '-t', '-f', 'SSID,SIGNAL,SECURITY', 'dev', 'wifi', 'list'],
            capture_output=True, text=True)
        networks = []
        seen = set()
        for line in result.stdout.strip().split('\n'):
            parts = line.split(':')
            if len(parts) >= 3 and parts[0] and parts[0] not in seen:
                seen.add(parts[0])
                networks.append({'ssid': parts[0], 'signal': parts[1], 'security': parts[2]})
        return sorted(networks, key=lambda x: int(x['signal']) if x['signal'].isdigit() else 0, reverse=True)
    except Exception as e:
        print(f"Scan error: {e}")
        return []

def save_and_reboot(ssid, password):
    time.sleep(3)
    subprocess.run(['nmcli', 'connection', 'delete', ssid], capture_output=True)
    result = subprocess.run(
        ['nmcli', 'dev', 'wifi', 'connect', ssid, 'password', password, 'name', ssid],
        capture_output=True, text=True)
    print(f"nmcli stdout: {result.stdout}")
    print(f"nmcli stderr: {result.stderr}")
    subprocess.run(['nmcli', 'connection', 'down', 'MRB_Setup'], capture_output=True)
    subprocess.run(['nmcli', 'connection', 'delete', 'MRB_Setup'], capture_output=True)
    time.sleep(2)
    subprocess.run(['reboot'])

@app.route('/', methods=['GET'])
def index():
    networks = get_wifi_networks()
    return render_template('index.html', networks=networks)

@app.route('/connect', methods=['POST'])
def connect():
    ssid = request.form.get('ssid')
    password = request.form.get('password')
    threading.Thread(target=save_and_reboot, args=(ssid, password)).start()
    return render_template('index.html', rebooting=True, ssid=ssid, networks=[])

@app.route('/generate_204')
@app.route('/hotspot-detect.html')
@app.route('/connectivity-check')
def captive_redirect():
    return redirect('/', 302)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80, debug=False)
EOF

# ── Step 7: Create index.html ───────────────────────────────
echo "[7/8] Creating index.html..."
cat > /opt/mrb-portal/templates/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>My Retail Buddy Wi-Fi Setup</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', sans-serif;
      background: #ebeff8;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .card {
      background: #ffffff;
      border-radius: 16px;
      padding: 36px 32px;
      width: 100%;
      max-width: 420px;
      box-shadow: 0 8px 32px rgba(0,80,174,0.12);
      text-align: center;
    }
    .logo-wrapper {
      background: #ffffff;
      border-radius: 12px;
      padding: 16px 24px;
      display: flex;
      align-items: center;
      justify-content: center;
      margin: 0 auto 10px;
      max-width: 300px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.08);
    }
    .logo-wrapper img {
      max-width: 260px;
      max-height: 100px;
      width: 100%;
      height: auto;
      display: block;
    }
    .tagline {
      color: #0050ae;
      font-size: 0.85em;
      font-style: italic;
      margin-bottom: 24px;
      font-weight: 500;
    }
    h1 {
      font-size: 1.3em;
      color: #1a1a2e;
      margin-bottom: 20px;
      font-weight: 600;
    }
    label {
      display: block;
      text-align: left;
      font-size: 0.85em;
      color: #555;
      margin-bottom: 4px;
      margin-top: 14px;
      font-weight: 500;
    }
    select, input {
      width: 100%;
      padding: 11px 14px;
      font-size: 0.95em;
      border: 1.5px solid #d0d8ee;
      border-radius: 8px;
      background: #f7f9ff;
      color: #222;
      outline: none;
      transition: border 0.2s;
    }
    select:focus, input:focus { border-color: #0050ae; }
    .password-wrapper { position: relative; }
    .password-wrapper input { padding-right: 48px; }
    .eye-btn {
      position: absolute;
      right: 12px;
      top: 50%;
      transform: translateY(-50%);
      background: none;
      border: none;
      cursor: pointer;
      padding: 0;
      width: 24px;
      height: 24px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: #888;
    }
    .eye-btn:hover { color: #0050ae; }
    .eye-btn svg { width: 20px; height: 20px; }
    .connect-btn {
      width: 100%;
      padding: 13px;
      margin-top: 24px;
      background: #0050ae;
      color: white;
      border: none;
      border-radius: 8px;
      font-size: 1em;
      font-weight: 600;
      cursor: pointer;
      letter-spacing: 0.5px;
      transition: background 0.2s;
    }
    .connect-btn:hover { background: #003d8a; }
    .connecting-screen {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 10px 0 20px;
    }
    .connecting-title {
      font-size: 1.8em;
      font-weight: 700;
      color: #0050ae;
      margin-bottom: 6px;
    }
    .connecting-sub {
      font-size: 1em;
      color: #555;
      margin-bottom: 28px;
    }
    .ssid-name { font-weight: 700; color: #1a1a2e; }
    .gears {
      position: relative;
      width: 120px;
      height: 120px;
      margin: 0 auto 24px;
    }
    .gear {
      position: absolute;
      border-radius: 50%;
      border: 8px solid #0050ae;
    }
    .gear-big {
      width: 72px; height: 72px;
      top: 8px; left: 4px;
      animation: spin 2s linear infinite;
    }
    .gear-small {
      width: 44px; height: 44px;
      top: 4px; left: 60px;
      border-color: #3a7bd5;
      animation: spin-reverse 1.3s linear infinite;
    }
    .gear-big::after, .gear-small::after {
      content: '';
      position: absolute;
      top: 50%; left: 50%;
      transform: translate(-50%, -50%);
      border-radius: 50%;
      background: #ebeff8;
    }
    .gear-big::after  { width: 24px; height: 24px; }
    .gear-small::after { width: 14px; height: 14px; }
    .tooth { position: absolute; background: #0050ae; border-radius: 2px; }
    .gear-small .tooth { background: #3a7bd5; }
    @keyframes spin         { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
    @keyframes spin-reverse { from { transform: rotate(0deg); } to { transform: rotate(-360deg); } }
    .reboot-note { font-size: 0.82em; color: #888; margin-top: 16px; line-height: 1.6; }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo-wrapper">
      <img src="/logo" alt="My Retail Buddy Logo">
    </div>
    <div class="tagline">For Operators, By Operators!</div>

    {% if rebooting %}
    <div class="connecting-screen">
      <div class="connecting-title">Connecting...</div>
      <div class="connecting-sub">Joining <span class="ssid-name">{{ ssid }}</span></div>
      <div class="gears">
        <div class="gear gear-big">
          <div class="tooth" style="width:10px;height:18px;top:-13px;left:23px;"></div>
          <div class="tooth" style="width:10px;height:18px;bottom:-13px;left:23px;"></div>
          <div class="tooth" style="width:18px;height:10px;left:-13px;top:23px;"></div>
          <div class="tooth" style="width:18px;height:10px;right:-13px;top:23px;"></div>
          <div class="tooth" style="width:12px;height:16px;top:-10px;left:8px;transform:rotate(-45deg);"></div>
          <div class="tooth" style="width:12px;height:16px;top:-10px;right:8px;transform:rotate(45deg);"></div>
          <div class="tooth" style="width:12px;height:16px;bottom:-10px;left:8px;transform:rotate(45deg);"></div>
          <div class="tooth" style="width:12px;height:16px;bottom:-10px;right:8px;transform:rotate(-45deg);"></div>
        </div>
        <div class="gear gear-small">
          <div class="tooth" style="width:7px;height:12px;top:-9px;left:12px;"></div>
          <div class="tooth" style="width:7px;height:12px;bottom:-9px;left:12px;"></div>
          <div class="tooth" style="width:12px;height:7px;left:-9px;top:12px;"></div>
          <div class="tooth" style="width:12px;height:7px;right:-9px;top:12px;"></div>
        </div>
      </div>
      <div class="reboot-note">Please wait — the device will reboot automatically.<br>This may take up to 60 seconds.</div>
    </div>

    {% else %}
    <h1>Wi-Fi Setup</h1>
    <form method="POST" action="/connect">
      <label>Select Network</label>
      <select name="ssid">
        {% for n in networks %}
          <option value="{{ n.ssid }}">{{ n.ssid }} ({{ n.signal }}%) {% if n.security != '--' %}🔒{% endif %}</option>
        {% endfor %}
      </select>
      <label>Password</label>
      <div class="password-wrapper">
        <input type="password" name="password" id="password" placeholder="Enter Wi-Fi password">
        <button type="button" class="eye-btn" onclick="togglePassword()" aria-label="Toggle password visibility">
          <svg id="eyeOpen" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
            <circle cx="12" cy="12" r="3"/>
          </svg>
          <svg id="eyeClosed" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="display:none;">
            <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94"/>
            <path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19"/>
            <line x1="1" y1="1" x2="23" y2="23"/>
          </svg>
        </button>
      </div>
      <button type="submit" class="connect-btn">Connect</button>
    </form>
    {% endif %}
  </div>

  <script>
    function togglePassword() {
      const input = document.getElementById('password');
      const eyeOpen = document.getElementById('eyeOpen');
      const eyeClosed = document.getElementById('eyeClosed');
      if (input.type === 'password') {
        input.type = 'text';
        eyeOpen.style.display = 'none';
        eyeClosed.style.display = 'block';
      } else {
        input.type = 'password';
        eyeOpen.style.display = 'block';
        eyeClosed.style.display = 'none';
      }
    }
  </script>
</body>
</html>
EOF

# ── Step 8: Create start.sh & systemd service ───────────────
echo "[8/8] Creating start.sh and systemd service..."
cat > /opt/mrb-portal/start.sh << 'EOF'
#!/bin/bash

nmcli connection down MRB_Setup 2>/dev/null
nmcli connection delete MRB_Setup 2>/dev/null
nmcli connection delete "MRB_Setup 1" 2>/dev/null
sleep 2

echo "Waiting 30s for Wi-Fi to establish..."
sleep 30

FAIL_COUNT=0

while [ $FAIL_COUNT -lt 3 ]; do
    echo "Running ping test (fail count: $FAIL_COUNT)..."
    if ping -c 3 -W 5 8.8.8.8 > /dev/null 2>&1; then
        echo "Internet connected! No AP needed."
        exit 0
    fi
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "Ping failed. Attempt $FAIL_COUNT of 3. Waiting 30s..."
    sleep 30
done

echo "3 ping failures. Starting AP portal..."
nmcli connection add type wifi ifname wlan0 con-name MRB_Setup autoconnect no ssid MRB_Setup
nmcli connection modify MRB_Setup 802-11-wireless.mode ap 802-11-wireless.band bg ipv4.method shared
nmcli connection modify MRB_Setup wifi-sec.key-mgmt wpa-psk wifi-sec.psk "mrbsetup"
nmcli connection up MRB_Setup

sleep 3
python3 /opt/mrb-portal/app.py
EOF
chmod +x /opt/mrb-portal/start.sh

cat > /etc/systemd/system/mrb-portal.service << 'EOF'
[Unit]
Description=MRB Wi-Fi Setup Portal
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=simple
ExecStart=/bin/bash /opt/mrb-portal/start.sh
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mrb-portal
systemctl start mrb-portal

echo ""
echo "============================================"
echo "  Installation Complete!"
echo "  Hotspot: MRB_Setup | Password: mrbsetup"
echo "  Portal:  http://10.42.0.1"
echo "  Logs:    sudo journalctl -u mrb-portal -f"
echo "============================================"
echo ""
