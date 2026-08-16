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

---

## Entry 004 — Stage 3 Custom Rust Core (`dns-core/`) Implementation
**Date:** 2026-08-16  
**Engineer:** vincenzo-afk  
**Stage:** 3 — Custom Rust DNS Core

### Architecture & Implementation
Created `dns-core/` standalone Rust project containing:
1. **`protocol`**: Binary DNS packet parser and encoder for RFC 1035 headers, questions, resource records (A, AAAA, CNAME, MX, TXT, PTR), and label compression pointers.
2. **`filter`**: `DomainTrie` in-memory structure using `AHashSet` for O(1) exact domain lookups and fast parent domain wildcard matching (`||example.com^`). `FilterEngine` enforces allowlist precedence over blocklists.
3. **`cache`**: Bounded LRU DNS response cache with TTL expiration, remaining TTL adjustment, and hit/miss/eviction metrics.
4. **`resolver`**: Asynchronous Tokio UDP forwarder querying the recursive Unbound backend (`127.0.0.1:5335`).
5. **`health`**: Service state machine (`ONLINE`, `DEGRADED`, `OFFLINE`, `ERROR`, `STOPPED`).
6. **`config`**: TOML configuration loader and validator with `config/vanta-dns.toml`.
7. **`cli`**: Commands (`Run`, `TestDomain`, `ValidateConfig`, `Benchmark`).
8. **Unit Tests**: Full unit test suite in `tests/unit_tests.rs` covering packet codec, normalization, wildcard rules, LRU eviction, and config validation.

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

## 2026-08-16 — Cloud-ready DoT rewrite (v0.2.0)

- Added plain DNS-over-TCP (RFC 1035 length framing) and DNS-over-TLS (RFC 7858,
  RFC 8446 via tokio-rustls) listeners to dns-core. Standalone TLS enabled via
  TLS_CERT/TLS_KEY env vars; TLS binds its own port (tls_port, default 853).
- Replaced local Unbound dependency: resolver now forwards to a chain of
  configurable upstreams over TCP/UDP (e.g. tcp:1.1.1.1:53, udp:9.9.9.9:53)
  with first-success fallback — the container is fully standalone.
- Blocklists (mobile ads, Spotify, YouTube, custom + adguard-base) and
  allowlists load at startup from /data paths; block_mode nxdomain|zero_ip.
- Added Dockerfile (rust:1-bookworm -> alpine multi-stage), fly.toml
  (Fly TLS handler on 853), render.yaml (alternative), config/docker-vanta-dns.toml,
  tests/dot_integration.rs (TCP + TLS against live server), docs/cloud-deployment.md.
- All unit tests pass; integration test passes TCP/TLS resolution + blocking.
