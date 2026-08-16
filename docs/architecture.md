# VantaDNS — Architecture Documentation

## Overview

VantaDNS is a personal DNS filtering and caching platform designed for privacy-first operation on a home network. It intercepts DNS queries at the network level before connections are made, applying filtering rules to block advertising, tracking, telemetry, and malicious domains.

## Design Principles

1. **Privacy by default** — No persistent query logging. Aggregate metrics only, reset on restart.
2. **No open resolver** — The system must never be accessible as a public recursive DNS resolver.
3. **Fail-safe** — When upstream connectivity is lost, the DNS service continues serving cached responses rather than failing entirely.
4. **Modular** — Components are independently replaceable. The reference implementation (AdGuard Home + Unbound) will be replaced component-by-component with the Rust dns-core in later stages.
5. **Verifiable** — Every behavior is testable and measurable.

## Stage 1 Component Architecture

### AdGuard Home

**Role:** Primary DNS listener and filtering engine.

**Why AdGuard Home?**
- Mature, actively maintained, battle-tested
- Built-in blocklist management with automatic updates
- HTTPS-served admin UI
- Supports per-client rules, allowlists, custom blocklists
- Can forward to any upstream resolver
- Minimal configuration surface for a privacy-focused setup

**What it does NOT do:**
- Recursive resolution (delegated to Unbound)
- DNSSEC validation (delegated to Unbound)
- Persistent query history (disabled)

### Unbound

**Role:** Local caching recursive resolver and DNSSEC validator.

**Why Unbound?**
- Mature, NLnet Labs maintained, used in production globally
- True recursive resolver (no mandatory upstream dependency)
- DNSSEC validation with auto-trust anchors
- Excellent caching with prefetch support
- QNAME minimisation (RFC 7816) — limits domain leakage to intermediate servers
- Low memory footprint

**What it does NOT do:**
- Accept queries from non-loopback addresses (by configuration)
- Forward to third-party DNS providers (by configuration — pure recursive)

## Data Flow

### Normal Resolution (Cache Miss)
```
Client device
    → DNS query (A example.com)
    → AdGuard Home :53
        → Blocklist check: NOT blocked
        → Forward to Unbound :5335
            → Cache check: MISS
            → Recursive query:
                → Root servers (13 root server IPs, via root.hints)
                → TLD server (.com NS)
                → Authoritative server (example.com NS)
                → Authoritative answer
            → DNSSEC validation
            → Cache response (TTL-bounded)
            → Return to AdGuard Home
        → Return to client
```

### Blocked Domain
```
Client device
    → DNS query (A doubleclick.net)
    → AdGuard Home :53
        → Blocklist check: BLOCKED (AdGuard DNS filter)
        → Return 0.0.0.0 (A record) immediately
        → Unbound is never contacted
```

### Cache Hit
```
Client device
    → DNS query (A example.com)
    → AdGuard Home :53
        → Blocklist check: NOT blocked
        → Forward to Unbound :5335
            → Cache check: HIT
            → Return cached response (remaining TTL)
        → Return to client
        (sub-millisecond response time)
```

### Upstream Outage (Internet Down)
```
Client device
    → DNS query (A example.com)
    → AdGuard Home :53
        → Blocklist check: NOT blocked
        → Forward to Unbound :5335
            → Cache check: HIT → Return cached response
            OR
            → Cache check: MISS
                → Recursive query fails (no Internet)
                → Return SERVFAIL to AdGuard Home
                → Return SERVFAIL to client
```

## Network Topology

```
Internet
    │
    │ (WAN)
    ▼
Home Router (10.76.181.1)
    │
    │ (LAN: 10.76.181.0/24, Wi-Fi)
    ├─── PC / VantaDNS Server (10.76.181.43)
    │        AdGuard Home :53 (LAN)
    │        Unbound :5335 (loopback only)
    │        Admin UI :3000 (loopback only)
    │
    ├─── Phone / Tablet / Other device
    │        DNS → 10.76.181.43
    │
    └─── Other LAN devices
             DNS → 10.76.181.43 (when configured)
```

## Port Map

| Service | Protocol | Port | Bind Address | Accessible From |
|---------|----------|------|--------------|-----------------|
| AdGuard Home DNS | UDP + TCP | 53 | 0.0.0.0 | Restricted to LAN by firewall |
| AdGuard Home UI | TCP | 3000 | 127.0.0.1 | Loopback only |
| Unbound | UDP + TCP | 5335 | 127.0.0.1 | Loopback only |

## DNSSEC Implementation

Unbound performs DNSSEC validation using:
- `auto-trust-anchor-file` — automatically manages the root trust anchor (KSK)
- Validation of RRSIG, DNSKEY, DS records in the chain of trust
- Rejection of responses that fail validation

Domains that do not support DNSSEC are still resolved normally (DNSSEC is not universally deployed). Domains that *are* signed but fail validation are rejected.

## QNAME Minimisation

Unbound implements RFC 7816 QNAME minimisation. This means:
- When querying the root servers for `example.com`, only `.com` is sent
- When querying `.com` TLD servers, only `example.com` is sent
- The full query name is only seen by the authoritative server

This reduces domain leakage to intermediate DNS infrastructure.

## Future Architecture (Stages 3–6)

```
[Stage 3-4] Rust dns-core replaces AdGuard Home + Unbound
[Stage 5]   React/TS dashboard replaces AdGuard Home UI
[Stage 6]   Android app embeds Rust dns-core via JNI

Final:
┌─────────────────────────────────────────────────────┐
│  Android Phone                                       │
│  ┌──────────────────────────────────────────────┐   │
│  │  Kotlin App (VpnService)                     │   │
│  │  ┌──────────────────────────────────────┐   │   │
│  │  │  Rust dns-core (via JNI/UniFFI)      │   │   │
│  │  │  • DNS packet parser                 │   │   │
│  │  │  • Filtering engine                  │   │   │
│  │  │  • Blocklist matcher (trie/hashset)  │   │   │
│  │  │  • LRU cache                         │   │   │
│  │  │  • Upstream resolver                 │   │   │
│  │  │  • Health monitor                    │   │   │
│  │  └──────────────────────────────────────┘   │   │
│  │  ┌──────────────────────────────────────┐   │   │
│  │  │  React/TS Dashboard (WebView)        │   │   │
│  │  └──────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```
