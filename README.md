# MRB Wi-Fi Setup Portal

Captive-portal Wi-Fi onboarding for **My Retail Buddy** devices (Raspberry Pi 3B+, Debian 13 "Trixie").

On boot the Pi checks for internet. If none is found after 3 tries, it launches an access point
(`MRB_Setup`, password `mrbsetup`). Connect a phone to it, open **http://10.42.0.1**, type your
Wi-Fi name (SSID) and password, and submit. The Pi verifies the connection and
reboots into client mode.

> **Note:** the portal asks you to type the exact SSID rather than picking from a
> scanned list. The Pi 3B+ has a single Wi-Fi radio, and while it is hosting the
> `MRB_Setup` access point that radio cannot reliably scan for other networks at
> the same time. Manual entry avoids that limitation and is more reliable.

## Install on the Pi

```bash
sudo apt install -y git
git clone https://github.com/a2goyal-web/MRB-Wifi-Setup.git ~/mrb-setup
cd ~/mrb-setup
chmod +x mrb-install.sh
sudo ./mrb-install.sh
```

## Files

| File | Purpose |
|------|---------|
| `mrb-install.sh` | One-shot installer (run with sudo) |
| `app.py` | Flask captive portal |
| `templates/index.html` | Branded portal page (logo + colors embedded) |
| `start.sh` | Boot logic: ping-check, then launch AP + portal |
| `mrb-portal.service` | systemd unit |
| `nftables.conf` | Redirects port 80 → 8080 |

## Admin

| Task | Command |
|------|---------|
| Live logs | `sudo journalctl -u mrb-portal -f` |
| Restart | `sudo systemctl restart mrb-portal` |
| List saved Wi-Fi | `sudo nmcli connection show` |
| Delete a saved Wi-Fi | `sudo nmcli connection delete "SSID"` |
| Active connections | `nmcli -t -f NAME,TYPE connection show --active` |

## Branding

Colors are CSS variables at the top of `templates/index.html`:
`--brand: #0050ae` · `--bg: #ebeff8` · `--accent: #fea301`.
The logo is embedded as a base64 data URI so it renders with no internet.

## Notes

- Flask runs as the unprivileged `mrbportal` user on port 8080; nftables redirects 80→8080.
- On a wrong password the portal restores the AP and lets you retry instead of bricking the boot.
