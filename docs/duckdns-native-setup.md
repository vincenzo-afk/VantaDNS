# VantaDNS — Native Android Private DNS Guide (`user-vanta.duckdns.org`)

**Your Domain:** `user-vanta.duckdns.org`  
**Your DuckDNS Token:** `60dafe7b-4059-469b-abae-36ca31a146de`  
**Your Current Public IP:** `152.57.94.106`

This guide explains how to get `user-vanta.duckdns.org` working **directly** in Android's Private DNS setting without Cloudflare or Tailscale.

---

## Technical Overview

When you type `user-vanta.duckdns.org` into Android Private DNS on 4G/5G:
1. Android looks up `user-vanta.duckdns.org` -> Resolves to `152.57.94.106`.
2. Android connects over TCP to Port **853** (`152.57.94.106:853`).
3. Android verifies that Port 853 is presenting a trusted **Let's Encrypt SSL Certificate** for `user-vanta.duckdns.org`.

To make this direct connection work without third-party proxy apps, we need **2 quick steps**:

---

## Step 1: Issue Free Let's Encrypt Certificate for `user-vanta.duckdns.org`

Android rejects self-signed certificates in Private DNS. We use `win-acme` (`wacs`) to issue a free, trusted Let's Encrypt SSL certificate.

### Run Cert Issuance Script:
Execute in PowerShell:
```powershell
$env:PATH += ";$env:USERPROFILE\scoop\shims"
wacs --source manual --host user-vanta.duckdns.org --validation script --validation-script-path "c:\Users\S K\Desktop\VantaDNS\scripts\update-duckdns.ps1" --store pemfiles --pemfilespath "c:\Users\S K\Desktop\VantaDNS\certs" --accepttos --emailaddress "itsmebk2007@gmail.com"
```

Once issued, `certs/fullchain.pem` and `certs/privkey.pem` are updated automatically in AdGuard Home (`AdGuardHome.yaml`).

---

## Step 2: Open Port 853 on Your Router (1-Minute Setup)

Because there is no middleman app (like Cloudflare or Tailscale), your home router's firewall is the doorway to your PC. Opening Port 853 tells your router to pass 4G/5G mobile DNS requests directly to VantaDNS on your PC.

### Instructions:
1. Open your browser and go to your router's login page: `http://10.76.181.1` (or `192.168.1.1`).
2. Log in (default username/password is often on the sticker on the back of your router).
3. Look for **Port Forwarding**, **Virtual Server**, or **NAT**.
4. Add 1 rule:
   - **Service Name:** VantaDNS DoT
   - **Protocol:** TCP
   - **External Port:** `853`
   - **Internal IP Address:** `10.76.181.43` (your PC's local IP)
   - **Internal Port:** `853`
5. Click **Save / Apply**.

---

## Step 3: Connect Your Android Phone on 4G / 5G

1. On your Android smartphone, open **Settings** > **Network & Internet** > **Private DNS**.
2. Select **Private DNS provider hostname**.
3. Type: `user-vanta.duckdns.org`
4. Tap **Save**.

**Result:** Android connects over encrypted TLS on Port 853. All ads across Spotify, YouTube trackers, games, and web browsing are blocked globally on 4G/5G mobile data and Wi-Fi!
