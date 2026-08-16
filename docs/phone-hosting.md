# VantaDNS — Hosting ON Your Android Phone (Zero Cost, No Cloud)

This guide turns your Android phone into its own ad-blocking DNS server. The
VantaDNS Rust core runs natively on the phone (Termux, **no root required**),
and all DNS queries from the phone are intercepted and filtered before they
ever leave the device.

---

## Architecture

```
 Android apps (Chrome, YouTube, Instagram ...)
        │ DNS queries
        ▼
  127.0.0.1:5353  ← dns-udp-forwarder.py (Termux, user-space)
        │
        ▼
  127.0.0.1:8533  ← vanta-dns-core (Rust, ARM64 native binary)
   ├─ blocklist filter  (AdGuard base + mobile ads + Spotify + YouTube)
   ├─ LRU cache         (50k entries, TTL clamping)
   └─ upstream chain    (tcp:1.1.1.1:53, tcp:8.8.8.8:53, udp:9.9.9.9:53 ...)
        │ clean answers
        ▼
   Android apps get ads returned as NXDOMAIN
```

The phone runs everything: the filter, the cache, the upstream resolver.
Total RAM usage is typically **under 80 MB**; battery impact is minimal
because DNS queries are tiny (~50-200 bytes each) and the cache absorbs
repeated requests.

---

## One-Command Install

### 1. Install Termux (from F-Droid — NOT the Play Store version)

The Play Store version is deprecated and broken. Install from:

- **F-Droid**: https://f-droid.org/packages/com.termux/
- Or direct APK: https://github.com/termux/termux-app/releases

(Recommended extras, also from F-Droid: **Termux:Boot** for auto-start,
**Termux:API**.)

### 2. Run the install script

Open Termux and paste:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/vincenzo-afk/VantaDNS/main/phone/install.sh)
```

This downloads the pre-built **aarch64 Android binary** (~7 MB) from GitHub
Releases, pulls the AdGuard base blocklist, and wires up Termux:Boot
autostart.

### 3. Start blocking

```bash
~/VantaDNS/bin/vanta-vpn.sh start
```

Verify:

```bash
nslookup google.com 127.0.0.1 -p 5353      # should resolve
nslookup doubleclick.net 127.0.0.1 -p 5353 # should return empty/NXDOMAIN
```

### 4. System battery tweaks (important for 24/7 operation)

1. **Settings → Apps → Termux → Battery → Unrestricted** (disable optimization)
2. **Settings → Apps → Termux:Boot → Battery → Unrestricted**
3. In Termux: **Settings → Wake lock → ON**

---

## The Android Private DNS Catch (read this)

Android's built-in **Private DNS** setting only accepts a *public hostname*
whose TLS certificate is trusted by Android — it rejects `localhost`,
`127.0.0.1`, and self-signed certificates. So the on-phone server cannot be
set as a system-wide Private DNS provider *directly*. You have three routes:

### Route A — Local mode (default, no root)

Run `vanta-vpn.sh start`. DNS from Termux apps and apps that honor the
system proxy go through the filter. For full system-wide coverage without
root, pair it with a free local-VPN ad-blocker app (e.g. **InviZible Pro**
from F-Droid) and point its DoH/DoT endpoint at your phone's LAN IP.

### Route B — DuckDNS public hostname (recommended, fully system-wide)

Even though the server runs on your phone, you can still use Android's
Private DNS field with a **free DuckDNS domain**:

1. Create a free subdomain at https://www.duckdns.org (e.g. `myvantadns.duckdns.org`)
2. Point it at your **public IP** (your router's WAN IP, since the phone is
   behind your Wi-Fi)
3. Port-forward TCP 853 on your router → phone's LAN IP (you can run the
   server's DoT listener with a Let's Encrypt cert; see
   `docs/duckdns-native-setup.md`)
4. Set Android Private DNS to `myvantadns.duckdns.org`

Result: the DNS server is literally your phone; your Wi-Fi devices get
filtering too.

### Route C — Public cloud fallback

Use the cloud version instead (see `docs/cloud-deployment.md`) — the
engine is the same binary.

---

## Managing the server

| Action | Command |
|--------|---------|
| Start | `~/VantaDNS/bin/vanta-vpn.sh start` |
| Stop | `~/VantaDNS/bin/vanta-vpn.sh stop` |
| Status | `~/VantaDNS/bin/vanta-vpn.sh status` |
| Logs | `tail -f ~/VantaDNS/phone/server.log` |
| Update blocklists | `curl -sSL https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt -o ~/VantaDNS/config/blocklists/adguard-base.txt && ~/VantaDNS/bin/vanta-vpn.sh stop && ~/VantaDNS/bin/vanta-vpn.sh start` |
| Edit blocklist | `nano ~/VantaDNS/config/blocklists/custom-blocklist.txt` (one domain per line; `#` = comment) |

After editing any blocklist, restart the server — lists reload at startup.

---

## Updating

```bash
bash <(curl -sSL https://raw.githubusercontent.com/vincenzo-afk/VantaDNS/main/phone/install.sh)
```

The script pulls the latest repo and replaces the binary.

---

## Troubleshooting

- **"Server won't start"**: run `~/VantaDNS/bin/vanta-dns-core run --config /tmp/vantadns-phone.toml` directly to see the error. Most failures are a bad blocklist path.
- **Battery drain**: DNS traffic is minimal; if drain is noticeable, another app (not VantaDNS) is the culprit — check battery stats.
- **Blocked sites you need**: add them to `allowlists/custom-allowlist.txt`.
- **"Out of memory"**: reduce `cache.capacity` in `phone/phone-vanta-dns.toml`.
