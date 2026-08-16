# VantaDNS

> *"Your DNS. Your rules. Your privacy."*

A personal, privacy-focused DNS resolver and network-level filtering platform.  
Blocks advertising, tracking, telemetry, and malicious domains before connections are made.  
Built incrementally — PC prototype first, Android deployment later.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Request Path](#request-path)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Security Assumptions](#security-assumptions)
6. [Privacy Defaults](#privacy-defaults)
7. [Firewall Rules](#firewall-rules)
8. [Health Monitoring](#health-monitoring)
9. [Benchmarking](#benchmarking)
10. [Troubleshooting](#troubleshooting)
11. [Testing](#testing)
12. [Roadmap](#roadmap)

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
│                   AdGuard Home                           │
│                (Port 53, LAN-only)                       │
│  • Blocklist evaluation (4 curated lists)                │
│  • Allowlist override                                    │
│  • Custom domain blocks                                  │
│  • Aggregate statistics (no per-query history)           │
│  • Admin UI on 127.0.0.1:3000 (loopback only)           │
└─────────────────────────┬────────────────────────────────┘
                          │ UDP/TCP 127.0.0.1:5335
                          ▼
┌──────────────────────────────────────────────────────────┐
│                      Unbound                             │
│              (Port 5335, loopback only)                  │
│  • Local caching recursive resolver                      │
│  • DNSSEC validation                                     │
│  • Root-server resolution (no third-party upstream)      │
│  • Prefetch for hot records                              │
└─────────────────────────┬────────────────────────────────┘
                          │ (recursive queries to authoritative servers)
                          ▼
                  Internet (Authoritative DNS)
```

### Component Responsibilities

| Component | Role | Port | Accessible From |
|-----------|------|------|-----------------|
| AdGuard Home | Filtering + admin UI | 53 (DNS), 3000 (UI) | LAN for DNS; loopback for UI |
| Unbound | Caching recursive resolver | 5335 | Loopback only |
| `health-check.ps1` | Service/network monitor | — | Local only |
| `benchmark.ps1` | Latency measurement | — | Local only |

### Future Components (later stages)

| Stage | Component |
|-------|-----------|
| 3+ | Rust `dns-core` (packet parsing, filtering, cache) |
| 5 | React/TypeScript management dashboard |
| 6 | Android application with VpnService |

---

## Request Path

```
Client → [DNS query] → AdGuard Home (port 53)
           │
           ├─ BLOCKED domain? → Return 0.0.0.0 (A) / :: (AAAA) immediately
           │
           └─ ALLOWED domain? → Forward to Unbound (127.0.0.1:5335)
                                   │
                                   ├─ Cache HIT? → Return cached response
                                   │
                                   └─ Cache MISS? → Recursive resolution
                                                    via root servers → TLD servers
                                                    → Authoritative servers
                                                    → Cache result → Return response
```

---

## Installation

### Prerequisites

- Windows 10/11
- PowerShell 5.1+ (run as Administrator for service installation)
- Git
- Internet connection (for initial downloads)

### Step-by-step

```powershell
# 1. Clone the repository
git clone https://github.com/vincenzo-afk/VantaDNS.git
cd VantaDNS

# 2. Run the installer (requires Administrator)
# Right-click PowerShell → Run as Administrator
.\scripts\install.ps1
```

The install script will:
1. Verify prerequisites
2. Download AdGuard Home binary (from GitHub releases)
3. Download Unbound binary (from NLnet Labs)
4. Fetch root hints
5. Apply all configuration files
6. Install Windows services
7. Apply firewall rules
8. Run post-install health check

### Manual Installation

See [docs/architecture.md](docs/architecture.md) for component-by-component instructions.

---

## Configuration

### What lives in this repository (safe to commit)

| File | Purpose |
|------|---------|
| `config/adguard/AdGuardHome.yaml.template` | AGH config template (no credentials) |
| `config/unbound/unbound.conf` | Unbound configuration |
| `config/blocklists/custom-blocklist.txt` | Your personal block rules |
| `allowlists/custom-allowlist.txt` | Your personal allow rules (false-positive overrides) |
| `scripts/` | All automation scripts |
| `docs/` | All documentation |

### What stays OFF repository (machine-local secrets)

| File/Directory | Contains |
|----------------|---------|
| `config/adguard/AdGuardHome.yaml` | Admin password hash, actual runtime config |
| `config/adguard/data/` | Runtime state, statistics |
| `config/unbound/root.hints` | Downloaded at install time |
| `config/unbound/*.key` | DNSSEC auto-trust key material |
| `logs/` | Any operational logs |

### Key Configuration Values

**AdGuard Home** (`config/adguard/AdGuardHome.yaml.template`)
- DNS listen: `0.0.0.0:53` (filtered to LAN by firewall)
- Admin UI: `127.0.0.1:3000`
- Upstream DNS: `127.0.0.1:5335` (Unbound)
- Query log: **disabled**
- Statistics retention: 24h aggregate only
- Auto-update: **disabled** (you control updates)

**Unbound** (`config/unbound/unbound.conf`)
- Listen: `127.0.0.1:5335`
- Access control: allow `127.0.0.1` only
- DNSSEC: enabled with auto-trust anchor
- Prefetch: enabled
- Cache min TTL: 300s, max TTL: 86400s

### Blocklists

Four curated lists loaded by default:

| List | Source | Purpose |
|------|--------|---------|
| AdGuard DNS filter | `filters.adtidy.org` | Ads + trackers |
| EasyList | `easylist.to` | Ad network domains |
| EasyPrivacy | `easylist.to` | Tracking domains |
| Steven Black Unified | `raw.githubusercontent.com` | Ads + malware |

**Adding a custom block rule:**
```
# config/blocklists/custom-blocklist.txt
||example-bad-domain.com^
```

**Adding an allowlist override (false positive fix):**
```
# allowlists/custom-allowlist.txt
@@||legitimate-domain.com^
```

---

## Security Assumptions

1. **Not an open resolver.** Port 53 is only accessible from `10.76.181.0/24` (your home LAN). It is blocked from all external interfaces. This is enforced by Windows Firewall rules documented in [docs/firewall-rules.md](docs/firewall-rules.md).

2. **Admin UI is loopback-only.** The AdGuard Home web interface (`127.0.0.1:3000`) is never exposed to LAN or Internet. Access it only from the PC itself.

3. **Unbound is loopback-only.** Unbound listens only on `127.0.0.1:5335`. It is not reachable from any other machine.

4. **No credentials in version control.** The `AdGuardHome.yaml` file with the admin password hash is listed in `.gitignore` and never committed.

5. **DNSSEC validation is enabled.** Unbound validates DNSSEC signatures for supported zones. Forged responses for DNSSEC-signed domains will be rejected.

6. **No public recursive resolver.** Creating an open recursive DNS resolver on the public Internet would enable DNS amplification attacks. This system is designed to prevent that by design and by firewall policy.

---

## Privacy Defaults

| Setting | Default | Notes |
|---------|---------|-------|
| Per-query DNS log | **Disabled** | Enable only for debugging, disable again afterward |
| Statistics retention | 24h aggregate | Block count, query count, cache hit rate only |
| AdGuard telemetry | **Disabled** | `check_updates: false` in config |
| Crash reporting | **None** | No external crash reporting configured |
| Unbound query log | **Disabled** | `verbosity: 0` |

### What information leaves your network during normal operation

During recursive DNS resolution, Unbound sends DNS queries to authoritative name servers on the Internet. These queries reveal:
- The domain name being looked up
- Your public IP address (as seen by the authoritative server)

This is inherent to the DNS protocol. Unbound uses QNAME minimisation (RFC 7816) to limit the domain information sent to intermediate servers. Authoritative servers only see the specific label they are authoritative for.

### What information stays on your PC

- Aggregate block count (resets on restart)
- Aggregate query count (resets on restart)
- Cache hit rate (in memory, resets on restart)
- DNS response cache (in memory, expires per TTL)
- **No browsing history is stored or persisted to disk.**

---

## Firewall Rules

See [docs/firewall-rules.md](docs/firewall-rules.md) for the complete rule set with rationale.

Quick summary:
- ✅ `10.76.181.0/24` → port 53: **Allow** (LAN clients)
- ✅ `127.0.0.1` → port 3000: **Allow** (admin UI, loopback only)
- ✅ `127.0.0.1` → port 5335: **Allow** (AGH → Unbound, loopback only)
- ❌ `0.0.0.0/0` → port 53: **Block** (prevent open resolver)

---

## Health Monitoring

Run at any time:
```powershell
.\scripts\health-check.ps1
```

Possible states:

| State | Meaning |
|-------|---------|
| `ONLINE` | All services healthy, Internet reachable, DNS resolving |
| `DEGRADED` | Services running but Internet or a component has issues |
| `OFFLINE` | No Internet connectivity, DNS cache-only mode |
| `RECONNECTING` | Internet was lost, attempting recovery |
| `ERROR` | A service has crashed or failed |
| `STARTING` | Services are starting up |
| `STOPPED` | Services are not running |

---

## Benchmarking

Run a full latency benchmark:
```powershell
.\scripts\benchmark.ps1
```

This measures:
1. Cold-cache resolution latency (first query, cache empty)
2. Warm-cache resolution latency (same query, from cache)
3. Blocked-domain response time (immediate, no upstream)
4. Comparison against `8.8.8.8`, `1.1.1.1`, `9.9.9.9` from the same network

**Important note:** VantaDNS may reduce DNS lookup latency through local caching and may reduce page load time by blocking unnecessary ad/tracker requests. It does **not** make your Internet connection itself faster. Raw throughput and ping to remote servers are determined by your ISP.

---

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for detailed procedures.

Quick checks:
```powershell
# Is AdGuard Home running?
Get-Service -Name "AdGuardHome" | Select-Object Status

# Is Unbound running?
Get-Service -Name "Unbound" | Select-Object Status

# Test DNS resolution from PC
nslookup google.com 127.0.0.1

# Test a blocked domain
nslookup doubleclick.net 127.0.0.1

# Test DNSSEC validation
nslookup -type=A sigok.verteiltesysteme.net 127.0.0.1

# View recent Windows event log for DNS services
Get-EventLog -LogName System -Source "Service Control Manager" -Newest 20
```

---

## Testing

```powershell
# Full verification suite
.\scripts\health-check.ps1

# DNS resolution tests
.\scripts\test-dns.ps1

# Benchmark
.\scripts\benchmark.ps1
```

### Manual test checklist

- [ ] `nslookup google.com 127.0.0.1` returns valid IP
- [ ] `nslookup doubleclick.net 127.0.0.1` returns `0.0.0.0` (blocked)
- [ ] `nslookup nonexistent-xyz123-vanta.com 127.0.0.1` returns `NXDOMAIN`
- [ ] AGH admin UI reachable at `http://127.0.0.1:3000`
- [ ] Warm-cache query < 5ms
- [ ] A second LAN device can browse normally using `10.76.181.43` as DNS

---

## Roadmap

| Stage | Status | Description |
|-------|--------|-------------|
| 1 | 🚧 In Progress | PC reference implementation (AdGuard Home + Unbound) |
| 2 | ⬜ Planned | Local-network testing & benchmarking |
| 3 | ⬜ Planned | Rust DNS-core (alongside reference impl) |
| 4 | ⬜ Planned | Gradual replacement of reference components with Rust |
| 5 | ⬜ Planned | React/TypeScript management dashboard |
| 6 | ⬜ Planned | Android application + Rust-core integration |
| 7 | ⬜ Planned | Android lifecycle & automatic recovery testing |
| 8 | ⬜ Planned | Privacy & security hardening |
| 9 | ⬜ Planned | Secure remote access (authenticated tunnel) |
| 10 | ⬜ Planned | Final 24/7 deployment on low-power hardware |

---

## License

Personal use. All components are open-source (AdGuard Home: GPL-3.0, Unbound: BSD).
