# VantaDNS — Mobile Data (4G/5G) Connectivity & Media Ad-Blocking Guide

This guide explains how to use VantaDNS over **cellular mobile data (4G/5G)** anywhere in the world and provides technical instructions for blocking ads in **YouTube, Spotify, and mobile applications**.

---

## Important Notice on Android "Private DNS Server Cannot Be Accessed" Error

If Android displays:
> **"Mobile network has no internet access — Private DNS server cannot be accessed"**

**Why this happens:**  
1. Placeholder domain names like `dns.vantadns.net` do not exist in public DNS, so Android cannot look them up on 4G/5G.
2. Android Private DNS requires a **trusted public TLS certificate** (such as Let's Encrypt) and rejects self-signed certificates for security.
3. TCP Port 853 must be reachable over the Internet via router port forwarding or a private mesh network.

👉 **See [docs/private-dns-fix.md](file:///c:/Users/S%20K/Desktop/VantaDNS/docs/private-dns-fix.md) for full step-by-step instructions to fix this error immediately.**

---

## Solution 1 — Tailscale Personal Mesh VPN (Recommended ⭐ 100% Free & Guaranteed)

Using **Tailscale** gives you global 4G/5G DNS protection with **zero router configuration, no domain costs, and no certificate maintenance**.

1. Install Tailscale on your VantaDNS server host (PC or Android).
2. Install Tailscale on your smartphone.
3. In [Tailscale Admin Console](https://login.tailscale.com/admin/dns), add your VantaDNS server IP as the **Global Custom DNS** and check **Override local DNS**.
4. Set Android Private DNS back to **Automatic** or **Off** and toggle Tailscale **ON**.

**Result:** All 4G, 5G, and Wi-Fi data traffic automatically routes DNS queries through VantaDNS!

---

## Solution 2 — Public DuckDNS + Let's Encrypt Certificate + Router Port 853

To use native Android Private DNS (`Settings > Network & Internet > Private DNS`) without installing Tailscale:

1. Create a free public subdomain at [duckdns.org](https://www.duckdns.org) (e.g. `myvantadns.duckdns.org`).
2. Forward TCP Port 853 on your Wi-Fi router (`10.76.181.1`) to `10.76.181.43`.
3. Issue a free trusted Let's Encrypt certificate for `myvantadns.duckdns.org`.
4. Enter `myvantadns.duckdns.org` into Android Private DNS.

---

## Media Ad-Blocking Mechanics

- **Spotify:** Blocks `spclient.wg.spotify.com`, `analytics.spotify.com`, `log.spotify.com`, and `adclick.g.doubleclick.net`.
- **YouTube:** Blocks `s.youtube.com`, `ads.youtube.com`, and `googleadservices.com`.
- **Mobile Apps:** Blocks UnityAds, AppLovin, Vungle, InMobi, IronSource, Tapjoy, and AdColony across mobile apps/games.
