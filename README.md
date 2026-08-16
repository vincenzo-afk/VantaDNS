# VantaDNS

> *"Your DNS. Your rules. Your privacy."*

A personal, privacy-focused DNS resolver and network-level filtering platform.  
Blocks advertising, tracking, telemetry, and malicious domains before connections are made.  
Built incrementally — PC reference implementation (AdGuard Home + Unbound) first, custom Rust `vanta-dns-core` engine, and Android deployment.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Stage 1 — Reference Implementation](#stage-1--reference-implementation)
3. [Stage 3 — Custom Rust Core (`dns-core`)](#stage-3--custom-rust-core-dns-core)
4. [Installation & Requirements](#installation--requirements)
5. [Configuration](#configuration)
6. [Security & Privacy Controls](#security--privacy-controls)
7. [Firewall Rules](#firewall-rules)
8. [Health Monitoring](#health-monitoring)
9. [Benchmarking Results](#benchmarking-results)
10. [Automated Test Suite](#automated-test-suite)
11. [Roadmap & Android Path](#roadmap--android-path)

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                     Client Devices                       │
│            (DNS set to 10.76.181.43 / PC IP)             │
└─────────────────────────┬────────────────────────────────┘
                          │ UDP/TCP :53
                          ▼
┌──────────────────────────────────────────────────────────┐
│             VantaDNS Filtering Engine                    │
│    [AdGuard Home Reference / Custom Rust dns-core]      │
│  • Blocklist evaluation (376,566 rules loaded)           │
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

## Stage 3 — Custom Rust Core (`dns-core`)

VantaDNS includes a high-performance custom Rust implementation located in `dns-core/`.

### Key Components

- **`protocol/`**: Binary DNS packet encoder and parser (RFC 1035). Handles Headers, Questions, Resource Records (A, AAAA, CNAME, MX, TXT, PTR), and label compression pointers.
- **`filter/`**: `DomainTrie` in-memory structure using `AHashSet` for O(1) exact domain lookups and fast parent domain wildcard matching (`||domain.com^`). `FilterEngine` enforces allowlist precedence.
- **`cache/`**: Bounded LRU DNS response cache with TTL expiration, remaining TTL adjustment, and hit/miss/eviction metrics.
- **`resolver/`**: Asynchronous Tokio UDP forwarder querying the recursive Unbound backend (`127.0.0.1:5335`).
- **`health/`**: `ServiceState` state machine (`ONLINE`, `DEGRADED`, `OFFLINE`, `ERROR`, `STOPPED`).

### CLI Usage (`vanta-dns-core`)

```bash
# Build the Rust binary
cd dns-core
cargo build --release

# Run the DNS server with default TOML config
cargo run --bin vanta-dns-core -- run --config config/vanta-dns.toml

# Evaluate a domain against the filtering engine
cargo run --bin vanta-dns-core -- test-domain --domain doubleclick.net

# Validate configuration file syntax
cargo run --bin vanta-dns-core -- validate-config --config config/vanta-dns.toml

# Run in-memory filtering engine benchmark
cargo run --bin vanta-dns-core -- benchmark
```

---

## Benchmarking Results

Measured using `scripts/benchmark.ps1`:

| Metric | Measured Latency | Rationale |
|--------|------------------|-----------|
| **Cold-Cache Average** | `253.2 ms` | Recursive lookup through Internet root/TLD servers |
| **Warm-Cache Average** | **`7.3 ms`** | Served instantly from local cache |
| **Cache Speedup** | **`97.0%`** | Substantial latency reduction for repeated domains |
| **Blocked Domain Response** | **`4.4 ms`** | Network-level block returned immediately |

### Resolver Latency Comparison

- **VantaDNS (local warm cache):** `2.0 - 5.0 ms`
- **Cloudflare (1.1.1.1):** `61 ms`
- **Google (8.8.8.8):** `76 ms`
- **Quad9 (9.9.9.9):** `92 ms`

---

## Health Monitoring & Testing

```powershell
# Run health check
.\scripts\health-check.ps1

# Run automated 18-test verification suite
.\scripts\test-dns.ps1

# Run latency benchmark
.\scripts\benchmark.ps1
```

All 18 critical verification checks pass with a **100% success rate**.
