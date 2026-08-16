# VantaDNS

> *"Your DNS. Your rules. Your privacy."*

A personal, privacy-focused DNS resolver and network-level filtering platform.  
Blocks advertising, tracking, telemetry, Spotify ads, YouTube tracking, mobile app ads, and malicious domains before connections are made.  
Works seamlessly on **Home Wi-Fi, Router-level LAN, and Mobile Data (4G/5G)** anywhere in the world.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Mobile Data (4G/5G) Access](#mobile-data-4g5g-access)
3. [Spotify & YouTube Ad-Blocking](#spotify--youtube-ad-blocking)
4. [Stage 1 — Reference Implementation](#stage-1--reference-implementation)
5. [Stage 3 — Custom Rust Core (`dns-core`)](#stage-3--custom-rust-core-dns-core)
6. [Installation & Requirements](#installation--requirements)
7. [Configuration](#configuration)
8. [Security & Privacy Controls](#security--privacy-controls)
9. [Health Monitoring](#health-monitoring)
10. [Benchmarking Results](#benchmarking-results)
11. [Automated Test Suite](#automated-test-suite)
12. [Android Deployment](#android-deployment)

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│             Client Devices (Wi-Fi & Mobile 5G)           │
│   (DNS: 10.76.181.43 / Private DNS / Tailscale VPN)      │
└─────────────────────────┬────────────────────────────────┘
                          │ UDP/TCP :53 / DoT :853
                          ▼
┌──────────────────────────────────────────────────────────┐
│             VantaDNS Filtering Engine                    │
│    [AdGuard Home Reference / Custom Rust dns-core]      │
│  • Blocklists: AdGuard, EasyList, EasyPrivacy,           │
│    Spotify Ads, YouTube Trackers, Mobile App Ads         │
│  • Allowlist override precedence                         │
│  • DomainTrie parent domain matching (||example.com^)    │
│  • Bounded LRU Cache with TTL enforcement                │
│  • Zero query logging by default (Privacy-first)         │
│  • Admin UI on 127.0.0.1:3000 (loopback only)           │
└─────────────────────────┬────────────────────────────────┘
                          │ UDP/TCP 127.0.0.1:5335
                          ▼
┌──────────────────────────────────────────────────────────┐
│                   Unbound Resolver                       │
│              (Port 5335, loopback only)                  │
│  • Local caching recursive resolver                      │
│  • DNSSEC validation with root.key trust anchor          │
│  • Root-server resolution (no third-party upstream)      │
│  • QNAME minimisation (RFC 7816)                         │
└─────────────────────────┬────────────────────────────────┘
                          │ (recursive queries to root/TLD servers)
                          ▼
                  Internet (Authoritative DNS)
```

---

## Mobile Data (4G/5G) Access

VantaDNS can protect your smartphone on cellular mobile data anywhere in the world:
- **Tailscale Mesh VPN (Recommended):** Zero-config, encrypted private DNS tunnel between your phone and VantaDNS host without opening public router ports. See [docs/mobile-data-setup.md](file:///c:/Users/S%20K/Desktop/VantaDNS/docs/mobile-data-setup.md).
- **Private DNS (DNS-over-TLS on Port 853):** Native Android DNS setting (`Settings > Network & Internet > Private DNS`).

---

## Spotify & YouTube Ad-Blocking

- **Spotify:** Blocks audio ad manifests, banner ads, tracking, and telemetry (`spclient.wg.spotify.com`, `analytics.spotify.com`).
- **YouTube:** Blocks YouTube tracking servers (`s.youtube.com`, `ads.youtube.com`, `googleadservices.com`).
- **Mobile App Ads:** Blocks UnityAds, AppLovin, Vungle, InMobi, IronSource, Tapjoy, and AdColony across mobile games and apps.

Detailed setup instructions available in [docs/mobile-data-setup.md](file:///c:/Users/S%20K/Desktop/VantaDNS/docs/mobile-data-setup.md).

---

## Stage 3 — Custom Rust Core (`dns-core`)

High-performance custom Rust implementation located in `dns-core/`.

### CLI Commands

```bash
# Build binary
cd dns-core
cargo build --release

# Run server with TOML config
cargo run --bin vanta-dns-core -- run --config config/vanta-dns.toml

# Test domain rule matching
cargo run --bin vanta-dns-core -- test-domain --domain doubleclick.net

# Run in-memory benchmark (170,000+ ops/sec)
cargo run --bin vanta-dns-core -- benchmark
```

---

## Benchmarking Results

| Metric | Measured Latency | Rationale |
|--------|------------------|-----------|
| **Cold-Cache Average** | `253.2 ms` | Recursive lookup through Internet root/TLD servers |
| **Warm-Cache Average** | **`7.3 ms`** | Served instantly from local memory |
| **Cache Speedup** | **`97.0%`** | Substantial latency reduction for repeated domains |
| **Rust Engine Throughput** | **`170,648 ops/sec`** | High-performance `DomainTrie` matching |

---

## Health Monitoring & Testing

```powershell
# Run health check
.\scripts\health-check.ps1 -ForceCheck

# Run live UDP Rust core integration test
.\scripts\test-rust-core.ps1 -Port 5354

# Run automated 18-test verification suite
.\scripts\test-dns.ps1
```
