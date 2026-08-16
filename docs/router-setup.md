# VantaDNS — Router & Client Network Integration Guide

This guide details how to integrate VantaDNS into your home or office local network (`10.76.181.0/24`) to provide automatic network-wide ad/tracker filtering, DNS caching, and privacy protection for all connected devices.

---

## 1. Prerequisites & Server Details

- **VantaDNS Server IP:** `10.76.181.43`
- **DNS Service Port:** `53` (UDP/TCP)
- **Upstream Resolver:** Local Unbound recursive backend (`127.0.0.1:5335`)
- **Admin Dashboard:** `http://127.0.0.1:3000` (Loopback only for security)

---

## 2. Option A — Router-Level Configuration (Recommended)

Configuring VantaDNS at the router level automatically protects every device connected to your Wi-Fi/LAN without configuring each device individually.

### Step 1: Assign Static IP Reservation
1. Log into your router's web interface (typically `http://10.76.181.1` or `http://192.168.1.1`).
2. Navigate to **DHCP Server / LAN Setup / IP Address Reservation**.
3. Find the MAC address of your VantaDNS server host (PC or Android phone).
4. Assign a fixed static IP address (e.g., `10.76.181.43`).
5. Save settings and apply changes.

### Step 2: Set Router Primary DNS
1. Navigate to **WAN / Internet Settings** or **DHCP Server Settings**.
2. Change **Primary DNS Server** to: `10.76.181.43`
3. Change **Secondary DNS Server** to: `0.0.0.0` or leave blank (do **NOT** use `8.8.8.8` or `1.1.1.1` as secondary, as clients will bypass VantaDNS filtering for up to 50% of requests).
4. Save and reboot your router.

---

## 3. Option B — Per-Device Client Setup

If you prefer to test VantaDNS on specific devices before applying router-wide settings:

### Windows 10 / 11
1. Open **Settings** > **Network & Internet** > **Wi-Fi** (or **Ethernet**).
2. Click **Edit** next to **DNS server assignment**.
3. Select **Manual**, toggle **IPv4** to **On**.
4. Set **Preferred DNS:** `10.76.181.43`
5. Leave **Alternate DNS** empty. Save.

### Android
1. Open **Settings** > **Network & Internet** > **Wi-Fi**.
2. Tap the gear icon next to your connected Wi-Fi network.
3. Select **Edit / Advanced Options** > **IP Settings** -> **Static**.
4. Set **DNS 1:** `10.76.181.43`
5. Set **DNS 2:** `10.76.181.43` (or leave blank). Save.

### iOS (iPhone / iPad)
1. Open **Settings** > **Wi-Fi**.
2. Tap the **(i)** info icon next to your Wi-Fi network.
3. Scroll to **Configure DNS** -> select **Manual**.
4. Delete existing DNS servers, tap **Add Server**, enter `10.76.181.43`.
5. Tap **Save**.

---

## 4. Preventing Rogue DNS Bypassing (Firewall Rules)

Some smart TVs, IoT devices, and applications contain hardcoded fallback DNS servers (e.g., Google `8.8.8.8`, Cloudflare `1.1.1.1`) that bypass DHCP-assigned DNS settings.

To enforce VantaDNS for all network devices, add the following firewall rules on your router or gateway:

### Rule 1: Allow Outbound DNS from VantaDNS Host Only
- **Source IP:** `10.76.181.43`
- **Destination:** Any
- **Port:** `53` (UDP/TCP)
- **Action:** `ALLOW`

### Rule 2: Block Outbound DNS from All Other Devices
- **Source IP:** `10.76.181.0/24` (excluding `.43`)
- **Destination:** Any
- **Port:** `53` (UDP/TCP)
- **Action:** `REJECT` or `REDIRECT` to `10.76.181.43:53`

---

## 5. Verification

Run the following command on any LAN client to confirm VantaDNS is filtering traffic:

```powershell
# Should return 0.0.0.0 (Blocked)
nslookup doubleclick.net 10.76.181.43

# Should return real public IP (Resolved)
nslookup google.com 10.76.181.43
```
