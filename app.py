import subprocess, threading, time
from flask import Flask, render_template, request, redirect

app = Flask(__name__)

AP_NAME = "MRB_Setup"
WIFI_IFACE = "wlan0"


def redact(s):
    return (s[:2] + "***") if s else "***"


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.returncode, ((r.stdout or "") + (r.stderr or "")).strip()


def save_profile(ssid, password):
    """Write an autoconnect NetworkManager profile to disk. Does NOT touch the
    radio, so it is safe to call while the AP is still up."""
    print(f"Saving profile for SSID={redact(ssid)}...")
    run(['nmcli', 'connection', 'delete', ssid])
    rc, out = run(['nmcli', 'connection', 'add',
                   'type', 'wifi',
                   'con-name', ssid,
                   'ifname', WIFI_IFACE,
                   'ssid', ssid,
                   'autoconnect', 'yes'])
    print(f"add rc={rc}: {out}")
    if rc != 0:
        return False
    rc2, out2 = run(['nmcli', 'connection', 'modify', ssid,
                     'wifi-sec.key-mgmt', 'wpa-psk',
                     'wifi-sec.psk', password,
                     'connection.autoconnect', 'yes',
                     'connection.autoconnect-priority', '100'])
    print(f"modify rc={rc2}: {out2}")
    return rc2 == 0


def connect_and_reboot():
    """Tear down the AP and reboot. On the next clean boot NetworkManager
    autoconnects to the saved profile (radio free, no AP in the way)."""
    print("Tearing down AP and rebooting into client mode...")
    time.sleep(2)
    run(['nmcli', 'connection', 'down', AP_NAME])
    run(['nmcli', 'connection', 'delete', AP_NAME])
    time.sleep(2)
    subprocess.run(['systemctl', 'reboot'])


STATE = {'saved_ssid': None}


@app.route('/', methods=['GET'])
def index():
    return render_template('index.html', saved_ssid=STATE['saved_ssid'])


@app.route('/save', methods=['POST'])
def save():
    ssid = (request.form.get('ssid') or '').strip()
    password = request.form.get('password') or ''
    if not ssid or len(ssid) > 32:
        return render_template('index.html', saved_ssid=None,
                               error="Please enter a valid network name.")
    ok = save_profile(ssid, password)
    if ok:
        STATE['saved_ssid'] = ssid
        return render_template('index.html', saved_ssid=ssid)
    return render_template('index.html', saved_ssid=None,
                           error="Could not save. Please try again.")


@app.route('/connect', methods=['POST'])
def connect():
    if not STATE['saved_ssid']:
        return redirect('/', 302)
    ssid = STATE['saved_ssid']
    threading.Thread(target=connect_and_reboot, daemon=True).start()
    return render_template('index.html', rebooting=True, saved_ssid=ssid)


@app.route('/generate_204')
@app.route('/gen_204')
@app.route('/hotspot-detect.html')
@app.route('/connectivity-check')
@app.route('/ncsi.txt')
def captive_redirect():
    return redirect('http://10.42.0.1/', 302)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
