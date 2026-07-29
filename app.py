import subprocess, threading, time
from flask import Flask, render_template, request, redirect

app = Flask(__name__)

AP_NAME = "MRB_Setup"


def redact(s):
    return (s[:2] + "***") if s else "***"


def try_connect(ssid, password):
    """Attempt connection. Returns True on verified success, else rolls back to AP."""
    print(f"Connecting to SSID={redact(ssid)}...")
    subprocess.run(['nmcli', 'connection', 'delete', ssid], capture_output=True)

    # Bring down the AP so wlan0 is free to join the target network
    subprocess.run(['nmcli', 'connection', 'down', AP_NAME], capture_output=True)
    time.sleep(2)

    result = subprocess.run(
        ['nmcli', 'dev', 'wifi', 'connect', ssid, 'password', password, 'name', ssid],
        capture_output=True, text=True)
    print(f"nmcli rc={result.returncode}")  # stdout/stderr intentionally NOT logged (may contain creds)

    if result.returncode == 0:
        # Verify we actually have internet before committing
        ping = subprocess.run(['ping', '-c', '3', '-W', '5', '8.8.8.8'], capture_output=True)
        if ping.returncode == 0:
            print("Connection verified. Rebooting into client mode.")
            subprocess.run(['nmcli', 'connection', 'delete', AP_NAME], capture_output=True)
            time.sleep(2)
            subprocess.run(['reboot'])
            return True

    # Failure path: clean up and bring the AP back so user can retry
    print("Connection failed. Restoring AP.")
    subprocess.run(['nmcli', 'connection', 'delete', ssid], capture_output=True)
    subprocess.run(['nmcli', 'connection', 'up', AP_NAME], capture_output=True)
    return False


# Shared status for the UI
STATUS = {'state': 'idle', 'ssid': None}


def worker(ssid, password):
    STATUS.update(state='connecting', ssid=ssid)
    time.sleep(1)
    ok = try_connect(ssid, password)
    STATUS.update(state='success' if ok else 'failed')


@app.route('/', methods=['GET'])
def index():
    return render_template('index.html', status=STATUS)


@app.route('/connect', methods=['POST'])
def connect():
    ssid = (request.form.get('ssid') or '').strip()
    password = request.form.get('password') or ''
    if not ssid or len(ssid) > 32:
        return render_template('index.html',
                               status={'state': 'failed', 'ssid': ssid})
    threading.Thread(target=worker, args=(ssid, password), daemon=True).start()
    return render_template('index.html', rebooting=True, ssid=ssid,
                           status={'state': 'connecting', 'ssid': ssid})


@app.route('/status')
def status():
    return STATUS


# Captive-portal catch-all: any unknown host/path bounces to the portal
@app.route('/generate_204')
@app.route('/gen_204')
@app.route('/hotspot-detect.html')
@app.route('/connectivity-check')
@app.route('/ncsi.txt')
def captive_redirect():
    return redirect('http://10.42.0.1/', 302)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
