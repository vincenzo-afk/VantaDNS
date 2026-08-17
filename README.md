# VantaDNS

<div align="center">

```text
██╗   ██╗ █████╗ ██╗   ██╗███████╗██╗      ██████╗ ██████╗ ███████╗██████╗
██║   ██║██╔══██╗██║   ██║██╔════╝██║     ██╔═══██╗██╔══██╗██╔════╝██╔══██╗
██║   ██║███████║██║   ██║█████╗  ██║     ██║   ██║██████╔╝█████╗  ██████╔╝
╚██╗ ██╔╝██╔══██║██║   ██║██╔══╝  ██║     ██║   ██║██╔══██╗██╔══╝  ██╔══██╗
 ╚████╔╝ ██║  ██║╚██████╔╝██║     ███████╗╚██████╔╝██║  ██║███████╗██║  ██║
  ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
         DNS — High-performance, privacy-focused ad & tracker blocker
```

**A high-performance, privacy-focused custom Rust DNS filtering engine and caching resolver that blocks ads and trackers system-wide — runs directly on your Android phone via Termux, no root required.**

| | |
|---|---|
| **Version** | 0.1.0 |
| **Language** | Rust 2021 |
| **License** | MIT |
| **Platforms** | Android (Termux, ARM64) · Linux · macOS · Windows |
| **Blocking rules** | 560,000+ (OISD · Hagezi Pro++ · StevenBlack · AdGuard · KADhosts) |
| **Block mode** | NXDOMAIN (configurable: `nxdomain` · `zero_ip`) |

**[Repository](https://github.com/vincenzo-afk/VantaDNS)** · **[Docs](docs/)** · **[Report Bug](https://github.com/vincenzo-afk/VantaDNS/issues)** · **[Request Feature](https://github.com/vincenzo-afk/VantaDNS/issues)**

</div>

---

## Table of Contents

- [About the Project](#about-the-project)
- [Tech Stack](#tech-stack)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation — On Your Android Phone (no root)](#installation--on-your-android-phone-no-root)
  - [Installation — From Source](#installation--from-source)
- [Configuration](#configuration)
- [Usage](#usage)
- [Blocklist Sources](#blocklist-sources)
- [Project Structure](#project-structure)
- [Features & Roadmap](#features--roadmap)
- [Testing](#testing)
- [Deployment Options](#deployment-options)
- [One-Tap Home Screen Launcher](#one-tap-home-screen-launcher)
- [Known Limitations](#known-limitations)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgments](#acknowledgments)

---

## About the Project

**VantaDNS** is a custom DNS filtering engine written in Rust that protects every app on your device from ads, trackers, telemetry, and malicious domains. Instead of running on a server you pay for, it runs **locally on your own Android phone** via [Termux](https://termux.dev) — your DNS never leaves your device until it is forwarded upstream to trusted resolvers (Cloudflare, Google, Quad9).

### The problem it solves

System-wide ad blocking on Android usually requires root, a VPN app with subscriptions, or trusting a third-party DNS provider with your query history. VantaDNS eliminates all three: it runs on localhost, intercepts DNS through a local UDP forwarder, and returns `NXDOMAIN` for 560,000+ known ad/tracker domains while resolving everything else normally through upstream forwarding with automatic fallback.

### Key features

- 🚀 **Blazing fast** — async Rust (Tokio) engine; sub-millisecond responses from the 50,000-entry local cache
- 🛡️ **560k+ blocking rules** — OISD Big, Hagezi Pro++, StevenBlack, AdGuard DNS Filter, KADhosts, and more
- 📦 **Multi-format parsing** — AdGuard syntax (`||domain^`), Adblock Plus, wildcards (`*.domain`), and hosts format (`0.0.0.0 domain`)
- 🔐 **DNS-over-TLS support** (RFC 7858) — optional TLS listener with self-signed or custom certificates
- 🧠 **Smart LRU cache** — configurable capacity, TTL clamping (`min 60s` – `max 86400s`)
- 🔄 **Resumable blocklist updates** — chunked, retry-aware downloads that survive flaky mobile connections
- 📱 **Zero root** — runs entirely in Termux with a UDP forwarder workaround for unprivileged ports
- 🔁 **Reboot-proof** — auto-starts via Termux:Boot 15 seconds after every boot
- 🎯 **One-tap control** — Termux:Widget shortcuts to toggle blocking with a single home-screen icon
- ⚡ **Multiple upstreams with fallback** — Cloudflare (1.1.1.1), Google (8.8.8.8), Quad9 (9.9.9.9) over TCP+UDP

### Architecture overview

```
  Apps on your phone
        │  DNS queries
        ▼
  Android per-network DNS
  set to 127.0.0.1:5353
        │
        ▼
  dns-udp-forwarder.py          ── UDP listener on :5353 (no root needed)
        │
        ▼
  vanta-dns-core (:8533)
   ┌──────────────────────┐
   │  Blocklist filter    │  560k rules in a radix trie — sub-ms matching
   │  LRU response cache  │  50,000 entries
   │  Upstream forwarder  │  TCP+UDP with automatic fallback
   └──────────────────────┘
        │
        ▼
  Cloudflare / Google / Quad9
```

Blocked domains receive an immediate `NXDOMAIN` response — no upstream query, no delay, no data leakage.

---

## Tech Stack

| Layer | Technology | Details |
|---|---|---|
| Language | Rust 2021 | `dns-core` crate, edition 2021 |
| Async runtime | Tokio 1.38 | Full features: UDP/TCP/TLS I/O |
| TLS | rustls + tokio-rustls 0.26 | Optional, behind the `tls` feature flag |
| Config parsing | serde 1.0 + toml 0.8 | `config.toml` based configuration |
| CLI | clap 4.5 | Derive-based argument parsing |
| Logging | tracing 0.1 + tracing-subscriber | `env-filter` controlled log levels |
| Cache | Custom LRU (ahash) | O(1) domain lookups |
| Filter engine | Custom radix trie | Handles AdGuard/Adblock/wildcard/hosts formats |
| Platform runtime | Termux on Android | ARM64 (`aarch64-linux-android`) |
| Helper scripts | Bash + Python 3 | `vanta-vpn.sh`, `update-blocklists.sh`, `dns-udp-forwarder.py` |

---

## Getting Started

### Prerequisites

| Requirement | Minimum | Phone install |
|---|---|---|
| Termux app | Latest from F-Droid or termux.dev | **Required** (Play Store build is outdated) |
| Termux:Boot | Latest | **Required** for auto-start after reboot |
| Termux:Widget | Latest (optional) | For one-tap home screen icon |
| Android version | 7.0+ | — |
| Storage | ~80 MB free | Binary (7 MB) + blocklists (~30 MB) + cache |
| Root | Not required | — |

No API keys or cloud accounts are needed. Everything runs locally.

### Installation — On Your Android Phone (no root)

The fastest path: clone the repo, then run the bundled installer which downloads the pre-built ARM64 binary and fetches all blocklists in small, resumable chunks.

```bash
# 1. Install dependencies (run one line at a time, wait for each to finish)
pkg update -y && pkg install -y git python bind-tools unzip

# 2. Clone the repository
git clone https://github.com/vincenzo-afk/VantaDNS.git

# 3. Run the phone installer (binary + blocklists + Termux:Boot autostart)
bash ~/VantaDNS/phone/install.sh

# 4. Start the server
bash ~/VantaDNS/bin/vanta-vpn.sh start

# 5. Verify — blocked domains return NXDOMAIN
dig @127.0.0.1 -p 8533 doubleclick.net | grep status
# ;; ->>HEADER<<- ... status: NXDOMAIN   ✅ blocked

dig @127.0.0.1 -p 8533 google.com | grep status
# ;; ->>HEADER<<- ... status: NOERROR    ✅ resolves normally
```

Finally, point your device DNS at the local server. The simplest universal method:

1. Settings → Network & internet → Private DNS → **Off** (the built-in Private DNS only accepts public hostnames)
2. For your Wi-Fi network: long-press the network → Modify → DNS set to **Manual** → `127.0.0.1`
3. For mobile data, see [docs/mobile-data-setup.md](docs/mobile-data-setup.md)

### Installation — From Source

```bash
# Install the Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup default stable

# Build the release binary
cd VantaDNS/dns-core
cargo build --release

# The binary is at ./target/release/vanta-dns-core
./target/release/vanta-dns-core --help
```

For a cross-compiled Android ARM64 binary on a desktop machine, see [docs/android-deployment.md](docs/android-deployment.md).

---

## Configuration

The server is configured via TOML. The phone profile lives at `phone/phone-vanta-dns.toml`; edit it before starting the server, then restart.

```toml
[server]
bind_addr = "127.0.0.1:8533"       # local UDP/TCP server port
upstreams = [
    "tcp:1.1.1.1:53",              # Cloudflare (TCP primary)
    "tcp:8.8.8.8:53",              # Google (TCP fallback)
    "udp:1.1.1.1:53",              # Cloudflare (UDP fallback)
    "udp:9.9.9.9:53",              # Quad9 (UDP fallback)
]
tcp_enabled = true                 # serve DNS over TCP on the same port
tls_enabled = false                # enable for DNS-over-TLS (RFC 7858)
tls_cert_path = "$HOME/.certs/tls.crt"   # used when tls_enabled = true
tls_key_path  = "$HOME/.certs/tls.key"
block_mode = "nxdomain"            # "nxdomain" | "zero_ip"
logging_enabled = false            # quiet by default on the phone

[cache]
capacity = 50000                   # LRU cache entries
min_ttl_secs = 60                  # force minimum cache lifetime
max_ttl_secs = 86400               # cap cache lifetime at 24 hours

[filter]
blocklist_paths = [                # $HOME is expanded automatically
    "$HOME/VantaDNS/config/blocklists/oisd-big.txt",
    "$HOME/VantaDNS/config/blocklists/hagezi-pro-wild.txt",
    "$HOME/VantaDNS/config/blocklists/hagezi-pro-plus.txt",
    "$HOME/VantaDNS/config/blocklists/stevenblack-domains.txt",
    "$HOME/VantaDNS/config/blocklists/adguard-base.txt",
    "$HOME/VantaDNS/config/blocklists/adguard-dns-filter.txt",
    "$HOME/VantaDNS/config/blocklists/kadhosts.txt",
    # ...plus the bundled chunk files (oisd-big.parta..partm, kadhosts.parta..partd)
]
allowlist_paths = [                # never block these domains
    "$HOME/VantaDNS/allowlists/custom-allowlist.txt",
]
```

| Key | Values | Default | Meaning |
|---|---|---|---|
| `block_mode` | `nxdomain` / `zero_ip` | `nxdomain` | How blocked domains are answered |
| `tls_enabled` | `true` / `false` | `false` | Expose the DoT (853) listener |
| `capacity` | integer | `50000` (phone) | Response cache size |
| `logging_enabled` | `true` / `false` | `false` | Write query logs to `server.log` |

---

## Usage

### Start, stop, and status

```bash
bash ~/VantaDNS/bin/vanta-vpn.sh start    # start server + UDP forwarder
bash ~/VantaDNS/bin/vanta-vpn.sh stop     # stop everything
bash ~/VantaDNS/bin/vanta-vpn.sh status   # show running state
```

### Query the server directly

```bash
# Against the main server
dig @127.0.0.1 -p 8533 doubleclick.net
dig @127.0.0.1 -p 8533 ads.yahoo.com

# Against the local forwarder (what your apps actually use)
dig @127.0.0.1 -p 5353 instagram.com
```

### Refresh the blocklists

The updater downloads lists in small, resumable chunks with automatic retries — safe on mobile data:

```bash
bash ~/VantaDNS/bin/update-blocklists.sh
```

Output:

```text
✔ fetched: adguard-base.txt (XXXXX lines)
✔ fetched: hagezi-pro-wild.txt (XXXXX lines)
✔ fetched: hagezi-pro-plus.txt (XXXXX lines)
```

### One-Tap Home Screen Launcher

Add a home-screen icon to toggle blocking with one tap:

```text
# 1. Install Termux:Widget from F-Droid:
#    https://f-droid.org/packages/com.termux.widget/

# 2. The launchers are already installed in ~/.shortcuts/ by install.sh

# 3. Long-press your home screen → Widgets → Termux:Widget
#    → drag "Shortcut" → pick toggle_vantadns
```

One tap = ads blocked. Tap again = ads return.

---

## Blocklist Sources

VantaDNS bundles and maintains the industry's most respected blocklists:

| Blocklist | Rules | Focus |
|---|---|---|
| [OISD Big](https://oisd.nl/) | ~269k | False-positive-free; safe for daily use |
| [Hagezi Pro](https://github.com/hagezi/dns-blocklists) | ~216k | Aggressive ads + trackers + telemetry |
| Hagezi Pro++ | ~240k | Sweeper-level: phishing, scam, cryptojacking |
| [StevenBlack Unified Hosts](https://github.com/StevenBlack/hosts) | ~99k | Ads + malware + adware |
| [AdGuard DNS Filter](https://adguard.com/en/adguard-dns/overview.html) | ~30k+ | AdGuard's curated DNS blocklist |
| [KADhosts](https://github.com/PolishFiltersTeam/KADhosts) | ~62k | Fraud/malware-focused |
| **Total** | **560k+ unique** | — |

All lists are parsed by a single trie engine that accepts AdGuard (`||domain^`), Adblock Plus, wildcard (`*.domain`), and hosts-format (`0.0.0.0 domain`) rules.

---

## Project Structure

```text
VantaDNS/
├── dns-core/                  # The Rust DNS engine
│   ├── Cargo.toml             # Dependencies (tokio, rustls, serde, clap)
│   └── src/
│       ├── main.rs            # Entry point: UDP/TCP/TLS listeners, list loading
│       ├── config.rs          # TOML config parsing, $HOME expansion, TLS env overrides
│       ├── lib.rs             # DnsCache (LRU) + server plumbing
│       ├── filter/
│       │   ├── engine.rs      # FilterEngine: load/merge blocklists + allowlists
│       │   └── trie.rs        # Radix-trie matcher: AdGuard/Adblock/wildcard/hosts
│       ├── resolver/
│       │   └── forwarder.rs   # Multi-upstream forwarder: TCP+UDP with fallback
│       └── protocol/          # DNS wire-format types (header, question, RR)
├── config/
│   ├── vanta-dns.toml        # Desktop/server reference config
│   └── blocklists/          # Bundled lists + line-safe chunks (parta..partm)
├── phone/                   # Everything for the Android/phone deployment
│   ├── install.sh           # One-shot installer (binary + lists + autostart)
│   ├── vanta-vpn.sh          # start / stop / status wrapper
│   ├── update-blocklists.sh # Chunked, resumable list updater
│   ├── dns-udp-forwarder.py # UDP :5353 → :8533 forwarder (no-root workaround)
│   ├── phone-vanta-dns.toml # Phone-optimized config
│   └── toggle_vantadns      # Termux:Widget one-tap launchers
├── docs/                    # Deployment & troubleshooting guides
├── releases/                # Pre-built ARM64 Android binaries
└── Dockerfile               # Container image (server/cloud mode)
```

---

## Features & Roadmap

### Current features

- [x] UDP + TCP DNS server (single port, configurable)
- [x] DNS-over-TLS (RFC 7858) listener with certificate support
- [x] 560k+ rule blocklist trie with 4 syntax formats
- [x] Allowlist support
- [x] LRU response cache with TTL clamping
- [x] Multi-upstream forwarding (Cloudflare/Google/Quad9) with TCP+UDP fallback
- [x] `nxdomain` and `zero_ip` block modes
- [x] $HOME expansion in all config paths
- [x] Chunked, resumable blocklist updates for mobile data
- [x] Termux:Boot auto-start
- [x] Termux:Widget one-tap launchers
- [x] Pre-built ARM64 Android binary (no on-phone compilation needed)

### Roadmap

- [ ] Built-in DoH (DNS-over-HTTPS) server endpoint
- [ ] Query log dashboard (AdGuard-style web UI)
- [ ] Per-app DNS routing rules
- [ ] Automated nightly list refresh via Termux cron
- [ ] IPv6 upstream and AAAA filtering

### Known limitations

- **YouTube video ads cannot be blocked by DNS.** Video ads are served from the same domains as the video content itself (`googlevideo.com`). Use [ReVanced](https://revanced.app) for YouTube. See [docs/youtube-revanced-combo.md](docs/youtube-revanced-combo.md).
- Android's system **Private DNS** setting cannot point at localhost (it requires a public hostname with a trusted certificate). Use per-network manual DNS instead.
- The phone runs without root, so the forwarder listens on 5353, not 53.

---

## Testing

```bash
cd dns-core
cargo test                    # unit + integration tests
```

Manual verification on the phone:

```bash
# Blocked → NXDOMAIN
dig @127.0.0.1 -p 8533 doubleclick.net | grep status
dig @127.0.0.1 -p 8533 ads.yahoo.com  | grep status

# Allowed → resolves
dig @127.0.0.1 -p 8533 google.com     | grep status
dig @127.0.0.1 -p 8533 instagram.com  | grep status

# Server health
bash ~/VantaDNS/bin/vanta-vpn.sh status
```

---

## Deployment Options

| Environment | Guide |
|---|---|
| Android phone (Termux, no root) | This README + [docs/phone-hosting.md](docs/phone-hosting.md) |
| Mobile data / hotspot / CGNAT | [docs/mobile-data-setup.md](docs/mobile-data-setup.md), [docs/mobile-hotspot-cgnat-fix.md](docs/mobile-hotspot-cgnat-fix.md) |
| Router (whole-network blocking) | [docs/router-setup.md](docs/router-setup.md) |
| Cloud (Fly.io, Render — free tiers) | [docs/cloud-deployment.md](docs/cloud-deployment.md) |
| Docker / self-hosted server | [docs/android-deployment.md](docs/android-deployment.md) + `Dockerfile` |
| Firewall rules (iptables/nft) | [docs/firewall-rules.md](docs/firewall-rules.md) |
| Troubleshooting | [docs/troubleshooting.md](docs/troubleshooting.md) |

---

## Security

VantaDNS is designed with privacy as a first principle:

- **No query logging by default** — `logging_enabled = false` in the phone profile
- **Local-first** — all filtering happens on-device; only resolved domains travel upstream to Cloudflare/Google/Quad9
- **Trusted TLS stack** — `rustls` (no OpenSSL) for the DoT listener
- **Minimal attack surface** — binds to `127.0.0.1` by default; nothing exposed externally

To report a vulnerability, open an issue at [github.com/vincenzo-afk/VantaDNS/issues](https://github.com/vincenzo-afk/VantaDNS/issues) or email the repository owner.

> **Note (Aug 2026):** the repository owner's GitHub account was briefly locked by GitHub's automated security system after a suspicious-login event. The account has been restored. If you stored a GitHub personal access token on a device that showed signs of compromise, revoke it immediately at [github.com/settings/tokens](https://github.com/settings/tokens) and enable [two-factor authentication](https://docs.github.com/en/authentication/securing-your-account-with-two-factor-authentication-2fa/configuring-two-factor-authentication).

---

## Contributing

Contributions are welcome. A suggested workflow:

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Commit with conventional prefixes: `feat:`, `fix:`, `docs:`, `perf:`
4. Run `cargo test` before opening a pull request
5. Open a PR against `main`

Please keep changes small and focused, and update `config/vanta-dns.toml` comments when adding configuration keys.

---

## License

This project is licensed under the [MIT License](LICENSE) — see the LICENSE file in the repository.

Copyright (c) 2026 vincenzo-afk <itsmebk2007@gmail.com>

---

## Acknowledgments

Blocklist data and inspiration from the outstanding blocklist community:

- [OISD](https://oisd.nl/) — the gold standard for false-positive-free lists
- [HaGeZi](https://github.com/hagezi/dns-blocklists) — comprehensive multi-tier DNS blocklists
- [StevenBlack Unified Hosts](https://github.com/StevenBlack/hosts) — the original unified hosts project
- [AdGuard DNS Filter](https://github.com/AdguardTeam/AdguardFilters) — AdGuard's DNS filter
- [KADhosts (PolishFiltersTeam)](https://github.com/PolishFiltersTeam/KADhosts) — fraud/malware hosts
- [Termux](https://termux.dev) — the Linux environment that makes this whole thing possible on Android

Built with ❤️ by **vincenzo-afk**
