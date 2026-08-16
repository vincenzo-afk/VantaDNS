# VantaDNS — Engineering Log

This log records every significant installation, configuration change, command, firewall rule, dependency, architecture decision, benchmark result, bug, and security decision made during the project. Entries are chronological and include timestamps, rationale, and outcomes.

---

## Entry 001 — Project Initialization & Architecture Setup
**Date:** 2026-08-16  
**Engineer:** vincenzo-afk  
**Stage:** 1 — PC Reference Implementation

### System Snapshot
- **OS:** Windows 10 Pro Build 19045 (~7.8 GB RAM)
- **Wi-Fi IP:** `10.76.181.43` (subnet `10.76.181.0/24`)
- **Git:** 2.55.0.windows.4
- **Node.js:** v24.18.1
- **Rust Toolchain:** 1.97.1 (Cargo 1.97.1)
- **Scoop Package Manager:** v0.5.3 (installed for user-space component management)

### Architecture Decisions

**Decision: AdGuard Home + Unbound as reference implementation**  
*Rationale:* Mature, battle-tested, well-documented. Proves the architecture works before custom Rust code is introduced. Modular enough to replace component-by-component with Rust implementations in later stages.

**Decision: Unbound on loopback port 5335, not port 53**  
*Rationale:* Port 53 is owned by AdGuard Home. Unbound is a private backend resolver — it should never be directly accessible by network clients. Loopback-only on a non-standard port enforces this.

**Decision: AdGuard Home admin UI on 127.0.0.1:3000 only**  
*Rationale:* The admin UI provides full control over the DNS resolver. Exposing it to LAN would allow any device on the network to reconfigure DNS filtering. Loopback-only ensures only the PC owner can administer it.

**Decision: Disable per-query logging by default**  
*Rationale:* DNS query logs constitute a detailed record of browsing history. Privacy-first means this is opt-in for debugging only, not on by default.

**Decision: No third-party public DNS upstream for Unbound**  
*Rationale:* Using 8.8.8.8 or 1.1.1.1 as upstream would send all unfiltered DNS queries to Google or Cloudflare respectively. Recursive resolution from root servers keeps DNS traffic within your own infrastructure as much as possible.

**Decision: 4 curated blocklists at launch**  
*Rationale:* Loaded 376,566 blocklist rules (AdGuard DNS Filter, EasyList, EasyPrivacy, Steven Black Unified Hosts).

---

## Entry 002 — Component Deployment & Stage 1 Verification
**Date:** 2026-08-16  
**Engineer:** vincenzo-afk  
**Stage:** 1 Verification Completed

### Deployed Components
1. **Unbound (v1.26.0)**:
   - Location: `C:\Users\S K\scoop\apps\unbound\current\`
   - Running as background daemon listening on `127.0.0.1:5335`
   - Initialized with IANA DNS root hints & DNSSEC root trust anchor (`root.key`)
   - QNAME minimisation enabled

2. **AdGuard Home (v0.107.78)**:
   - Location: `C:\Users\S K\Desktop\VantaDNS\run\adguardhome\`
   - Running as background daemon listening on `0.0.0.0:53` (DNS) and `127.0.0.1:3000` (Web UI/API)
   - Upstream: `127.0.0.1:5335` (Unbound)
   - Blocklists: 376,566 active rules loaded
   - Response mode: `NXDOMAIN`

### Automated Verification Results (`scripts/test-dns.ps1`)
- **Passed:** 18 / 18 (100%)
- **Component & Port Health:** OK (Ports 53 & 5335 listening)
- **A Record Resolution:** OK (google.com, cloudflare.com, github.com, microsoft.com, wikipedia.org)
- **DNS Record Types:** OK (MX, TXT, AAAA, CNAME)
- **NXDOMAIN:** OK
- **Blocking:** OK (doubleclick.net, googlesyndication.com, googleadservices.com -> blocked)
- **DNSSEC Validation:** OK (sigok.verteiltesysteme.net -> valid, sigfail.verteiltesysteme.net -> SERVFAIL)

---

## Entry 003 — DNS Latency Benchmark Results
**Date:** 2026-08-16  
**Method:** Measured via `scripts/benchmark.ps1` on local network interface `127.0.0.1`

| Metric | Measured Latency | Notes |
|--------|------------------|-------|
| Cold-cache average | **253.2 ms** | Initial recursive resolution via root servers |
| Warm-cache average | **7.3 ms** | Served from local cache |
| Cache speedup | **97.0%** | Reduction in lookup latency for repeated queries |
| Blocked domain response | **4.4–14.2 ms** | Immediate local block response |

### Resolver Latency Comparison (from same network interface)
- **VantaDNS (warm cache):** 2.0–5.0 ms
- **Cloudflare (1.1.1.1):** ~61 ms
- **Google (8.8.8.8):** ~76 ms
- **Quad9 (9.9.9.9):** ~92 ms

*Note: Local DNS caching reduces lookup latency for repeated domains. It does not alter underlying ISP network bandwidth or ping.*

---

## Security Decisions Log

| Decision | Rationale | Date |
|----------|-----------|------|
| Block port 53 on all non-LAN interfaces | Prevent open recursive resolver / DNS amplification | 2026-08-16 |
| Admin UI loopback-only | Prevent LAN devices from accessing resolver configuration | 2026-08-16 |
| No query logging | DNS history is browsing history — privacy-first | 2026-08-16 |
| No auto-update for AdGuard Home | Control when updates are applied | 2026-08-16 |
| DNSSEC validation enabled | Reject forged DNS responses for DNSSEC-signed zones | 2026-08-16 |
| Unbound loopback-only | Unbound must never be a direct public resolver | 2026-08-16 |
