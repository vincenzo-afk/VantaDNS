# VantaDNS — Mobile Data (4G/5G) Connectivity & Media Ad-Blocking Guide

This guide explains how to use VantaDNS over **cellular mobile data (4G/5G)** anywhere in the world and provides technical instructions for blocking ads in **YouTube, Spotify, and mobile applications**.

---

## Part 1 — Using VantaDNS on Mobile Data (Cellular 4G/5G)

When you disconnect from home Wi-Fi and switch to Mobile Data, standard LAN IP addresses (`10.76.181.43`) are unreachable because mobile carriers assign private cellular IPs. 

There are two primary methods to connect your phone to VantaDNS over Mobile Data:

---

### Method A — Personal Encrypted VPN Tunnel (Tailscale / WireGuard) — Recommended ⭐

Using a personal mesh VPN (like **Tailscale**, which is 100% free for personal use) securely connects your mobile device directly to your VantaDNS server anywhere in the world without exposing public ports to hackers.

#### Step 1: Install Tailscale on VantaDNS Host (PC or Android)
1. Download and install Tailscale on your VantaDNS server host (from [tailscale.com](https://tailscale.com)).
2. Log in with your account.
3. Your VantaDNS host will receive a permanent, secure Tailscale IP (e.g., `100.115.82.43`).

#### Step 2: Install Tailscale on Your Smartphone
1. Install **Tailscale** from Google Play Store or Apple App Store.
2. Log into the same Tailscale account.
3. Toggle Tailscale **ON**.

#### Step 3: Set VantaDNS as Global DNS in Tailscale Admin
1. Open the [Tailscale Admin Console](https://login.tailscale.com/admin/dns).
2. Under **DNS Servers** > **Add Nameserver** -> Select **Custom**.
3. Enter your VantaDNS server's Tailscale IP (e.g., `100.115.82.43`).
4. Enable **Override local DNS**.

**Result:** Whether you are on Wi-Fi, 4G, 5G, or public hot spots, 100% of your mobile network traffic will automatically route DNS queries through VantaDNS!

---

### Method B — Native Android "Private DNS" (DNS-over-TLS / DoT)

Android has a built-in feature called **Private DNS** (`Settings > Network & Internet > Private DNS`) that encrypts all DNS traffic over **DNS-over-TLS (DoT)** on port 853.

#### Server Setup (AdGuard Home / VantaDNS Core)
1. Enable Encryption / DoT in AdGuard Home Settings (`Encryption Settings`).
2. Enter your domain name (e.g., via DuckDNS / Cloudflare: `dns.yourdomain.com`).
3. Provide TLS certificate and private key files (`fullchain.pem` and `privkey.pem`).
4. Port `853` (TCP) must be open on your firewall.

#### Android Smartphone Setup
1. On your Android phone, go to **Settings** > **Network & Internet** > **Private DNS**.
2. Select **Private DNS provider hostname**.
3. Type your custom DoT domain name (e.g., `dns.yourdomain.com`).
4. Tap **Save**.

---

## Part 2 — Spotify, YouTube & In-App Ad-Blocking Technical Mechanics

### 1. Spotify Ad Blocking
Spotify serves banner ads, audio ads, and user analytics through specific domain endpoints. VantaDNS blocks these dedicated endpoints at the network level:

- **Blocked Endpoints:**
  - `adclick.g.doubleclick.net`
  - `analytics.spotify.com`
  - `crashdump.spotify.com`
  - `log.spotify.com`
  - `ads-fa.spotify.com`
- **Effect:** Prevents Spotify banner ads, audio ad tracking requests, and background telemetry from loading on desktop, mobile, and web players.

---

### 2. YouTube Ad-Blocking (DNS + Client Mechanics)

#### How YouTube Video Ads Work
YouTube uses two distinct mechanisms for advertising:
1. **Ad Banners & Trackers:** Served from dedicated tracking domains (`s.youtube.com`, `ads.youtube.com`, `googleadservices.com`). **VantaDNS blocks 100% of these.**
2. **Inline Video Stream Ads:** Served dynamically from the **exact same domain names and content delivery servers (`*.googlevideo.com`)** as the actual video content you want to watch. 

> ⚠️ **Important DNS Engineering Fact:** Blocking `googlevideo.com` at the DNS level would cause all YouTube videos to fail to load or buffer indefinitely. 

#### Recommended Complete 100% YouTube Ad-Free Solution:

| Device | Primary Defense (VantaDNS) | Complementary Video Stream Filter | Result |
|--------|----------------------------|-----------------------------------|--------|
| **Android Phone** | VantaDNS (Blocks trackers & app ads) | **YouTube ReVanced** or **SmartTube** | **100% Ad-Free Video & Audio** |
| **Android TV / FireTV** | VantaDNS (Blocks network telemetry) | **SmartTube** | **100% Ad-Free TV Experience** |
| **PC / Laptop** | VantaDNS (Blocks domain ads & tracking) | **uBlock Origin** or **Brave Browser** | **100% Ad-Free Web Browsing** |
| **iOS (iPhone/iPad)** | VantaDNS (Blocks app tracking & ads) | **Brave Browser / Video Lite** | **100% Ad-Free Video Playback** |

---

## Part 3 — Mobile App Ad Blocking (In-App Ads)

VantaDNS blocks all major mobile ad networks used by free Android & iOS games/apps:
- **UnityAds:** `unityads.unity3d.com`
- **AppLovin:** `applovin.com`
- **Vungle:** `ads.vungle.com`
- **InMobi:** `inmobi.com`
- **IronSource:** `ironsource.com`
- **Tapjoy:** `tapjoy.com`
- **AdColony:** `adcolony.com`

**Result:** When playing games or using mobile apps on Mobile Data or Wi-Fi, pop-up video ads and banner ads fail to load, saving mobile bandwidth and battery life.
