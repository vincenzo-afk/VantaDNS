# VantaDNS — DuckDNS Setup Without Modifying Your Router

**Domain Name:** `user-vanta.duckdns.org`  
**Current Public IP:** `152.57.94.106`  
**DuckDNS Token:** `60dafe7b-4059-469b-abae-36ca31a146de`

---

## Technical Problem

Your domain `user-vanta.duckdns.org` is now registered and pointing to your public IP `152.57.94.106`.

However, when you are on 4G/5G Mobile Data outside your home, inbound network requests hit your Internet Service Provider's gateway. Without forwarding ports on your router, incoming connections on Port 853 are blocked by your router's firewall.

---

## 2 Solutions to Make `user-vanta.duckdns.org` Work WITHOUT Changing Your Router

---

### Solution A — Tailscale Tunnel (100% Recommended ⭐ Zero Router Setup)

Tailscale creates an encrypted outbound tunnel from your PC to your phone. It bypasses router firewalls completely without modifying router settings.

#### Steps:
1. **On your PC:** Install free [Tailscale for Windows](https://tailscale.com/download/windows). Log in.
2. **On your Android Phone:** Install **Tailscale** from Google Play Store. Log in to the same account.
3. **In Tailscale Admin Console ([login.tailscale.com/admin/dns](https://login.tailscale.com/admin/dns)):**
   - Click **Add Nameserver** -> **Custom**.
   - Enter your VantaDNS host's Tailscale IP (e.g. `100.115.82.43`).
   - Enable **Override local DNS**.
4. Turn **Tailscale ON** on your phone.

**Result:** Works instantly on 4G, 5G, and any Wi-Fi. Blocks 100% of ads across all apps without touching your router!

---

### Solution B — Cloudflare Tunnel (`cloudflared`) — Zero Router Port Forwarding

Cloudflare Tunnel creates an encrypted outbound bridge between your PC and Cloudflare's global edge network.

#### Steps:
1. Download `cloudflared` for Windows (or install via Scoop: `scoop install cloudflared`).
2. Run `cloudflared tunnel --url tcp://127.0.0.1:853`.
3. Cloudflare provides a public secure HTTPS/DoT address that routes directly to your VantaDNS server over 4G/5G without opening any ports on your router!
