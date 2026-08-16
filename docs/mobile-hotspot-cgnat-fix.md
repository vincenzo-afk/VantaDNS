# VantaDNS — Mobile Hotspot & Cellular CGNAT Fix Guide

If you are using **Mobile Data / Cellular Hotspot** directly on your PC:

---

## Technical Explanation — Why `152.57.94.106:853` Failed

When using mobile data (4G/5G), mobile phone carriers (Jio, Airtel, T-Mobile, AT&T, etc.) place all mobile connections behind **CGNAT (Carrier-Grade NAT)**.

This means `152.57.94.106` is a shared public IP owned by the cellular carrier tower. Incoming connections to `152.57.94.106:853` are blocked by the mobile carrier before they ever reach your PC.

Windows Firewall rules for Port 853 and Port 53 have been opened on your PC.

---

## 3 Working Solutions for Mobile Data

---

### Solution 1 — Fly.io / Render Free Cloud Deployment (Recommended ⭐ 100% Free Public DoT Domain)

Deploying `vanta-dns-core` to a free cloud container (Fly.io / Render) gives you a dedicated public domain with a valid Let's Encrypt SSL certificate.

#### Your Personal DoT Domain:
`vanta-dns.fly.dev`

#### Steps:
1. Open Android **Settings** > **Network & Internet** > **Private DNS**.
2. Select **Private DNS provider hostname**.
3. Enter `vanta-dns.fly.dev`.
4. Tap **Save**.

---

### Solution 2 — Phone Connected to PC Mobile Hotspot

If your Android phone is connected to your PC's Wi-Fi / Mobile Hotspot:

1. On your PC, open PowerShell and check your hotspot IP:
   ```powershell
   (Get-NetIPAddress -InterfaceAlias "*Hotspot*", "*Wi-Fi*" -AddressFamily IPv4).IPAddress
   ```
   (Typically `192.168.137.1` or `10.76.181.43`).
2. On your Android phone, go to **Settings** > **Wi-Fi** > select your PC Hotspot > **Edit** > **IP Settings: Static**.
3. Set **DNS 1:** `192.168.137.1` (or your PC IP).
4. Tap **Save**.

---

### Solution 3 — Free Personal NextDNS / RethinkDNS DoT Endpoint (Instant 1-Minute)

If you want a free personal DoT domain right now that works on 4G/5G without deploying anything:

1. Go to [nextdns.io](https://my.nextdns.io) and click **Try now**.
2. Copy your custom **Endpoints** > **DNS-over-TLS** hostname (e.g. `24a1b0.dns.nextdns.io`).
3. On your Android phone, go to **Settings** > **Network & Internet** > **Private DNS**.
4. Type `24a1b0.dns.nextdns.io` and tap **Save**.
5. Enable AdGuard, EasyList, Spotify, and YouTube blocklists with 1 click.
