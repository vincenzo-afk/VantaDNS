# VantaDNS — Android "Private DNS Server Cannot Be Accessed" Fix Guide

If Android shows the error:  
> **"Mobile network has no internet access — Private DNS server cannot be accessed"**

This section explains the exact technical reason why this happens and how to fix it immediately.

---

## Technical Cause of the Error

Android's native **Private DNS** feature enforces 3 strict security requirements before it allows network traffic:

1. **Public Domain Name Resolution:** When you type a hostname (like `dns.vantadns.net`), Android attempts to look up that domain via public root DNS servers (e.g. `8.8.8.8`). Placeholder names like `dns.vantadns.net` fail to resolve to your local home IP address.
2. **Public Certificate Trust:** Android validates that the TLS certificate on Port 853 is signed by a recognized Certificate Authority (e.g., **Let's Encrypt** or **ZeroSSL**). Android explicitly rejects self-signed certificates.
3. **Port 853 Reachability over 4G/5G:** When on cellular Mobile Data, your phone is outside your home Wi-Fi network. Requests to Port 853 must reach your VantaDNS server across the Internet.

---

## Option 1 — The 100% Guaranteed Instant Fix (Tailscale Personal VPN) ⭐

This is the easiest, safest, and most reliable method. It requires **NO router port forwarding, NO domain purchasing, and NO certificate setup**.

### Steps:
1. **Install Tailscale on PC/Server:** Download and install free [Tailscale for Windows](https://tailscale.com/download/windows). Log in.
2. **Install Tailscale on Android Phone:** Download **Tailscale** from Google Play Store. Log in to the same account.
3. **Configure VantaDNS as Global DNS:**
   - Go to [login.tailscale.com/admin/dns](https://login.tailscale.com/admin/dns).
   - Click **Add Nameserver** -> **Custom**.
   - Enter your VantaDNS server's Tailscale IP (found in Tailscale app, e.g. `100.115.82.43`).
   - Enable **Override local DNS**.
4. **Turn ON Tailscale on your phone.**

**Result:** Set Android Private DNS back to **Automatic** or **Off**. Toggle Tailscale ON. 100% of your mobile network data (4G/5G/Wi-Fi) will immediately route all DNS queries through VantaDNS, blocking all ads across all platforms worldwide!

---

## Option 2 — Setting Up Native Android Private DNS (`myname.duckdns.org`)

If you specifically want to use the **Private DNS** text field in Android settings without installing an app:

### Step 1: Create a Free DuckDNS Subdomain
1. Go to [duckdns.org](https://www.duckdns.org) and log in.
2. Create a free subdomain (e.g., `myvantadns.duckdns.org`).
3. Point it to your current public IPv4 address.

### Step 2: Forward Port 853 on Your Router
1. Log into your home router's admin page (`10.76.181.1`).
2. Navigate to **Port Forwarding / Virtual Server**.
3. Add a port forwarding rule:
   - **External Port:** `853` (TCP)
   - **Internal IP:** `10.76.181.43`
   - **Internal Port:** `853` (TCP)

### Step 3: Get a Free Trusted Let's Encrypt Certificate
Android requires a public Let's Encrypt TLS certificate:
- Use `win-acme` or `certbot` to issue a free SSL cert for `myvantadns.duckdns.org`.
- In AdGuard Home (`AdGuardHome.yaml`), update:
  ```yaml
  tls:
    enabled: true
    server_name: myvantadns.duckdns.org
    certificate_path: C:\path\to\fullchain.pem
    private_key_path: C:\path\to\privkey.pem
  ```

### Step 4: Enter Your DuckDNS Domain in Android
1. Go to **Settings** > **Network & Internet** > **Private DNS**.
2. Select **Private DNS provider hostname**.
3. Type: `myvantadns.duckdns.org`
4. Tap **Save**.
