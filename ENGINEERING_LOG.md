# VantaDNS — Engineering Log

This log records every significant installation, configuration change, command, firewall rule, dependency, architecture decision, benchmark result, bug, and security decision made during the project. Entries are chronological and include timestamps, rationale, and outcomes.

---

## Entry 001 — Project Initialization
**Date:** 2026-08-16  
**Engineer:** vincenzo-afk  
**Stage:** 1 — PC Reference Implementation

### System Snapshot
- **OS:** Windows 10 Pro Build 19045 (~7.8 GB RAM)
- **Wi-Fi IP:** `10.76.181.43` (subnet `10.76.181.0/24`)
- **Gateway:** `10.76.181.1` (assumed)
- **Git:** 2.55.0.windows.4 ✅
- **Node.js:** v24.18.1 ✅
- **Rust:** Not installed — being installed via winget

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
*Rationale:* Too many blocklists cause high false-positive rates, high memory usage, and slow blocklist loads. Start conservative and add lists based on observed need.

### PowerShell Execution Policy Change
- **Changed from:** Undefined (defaults to Restricted on Windows 10)
- **Changed to:** RemoteSigned (CurrentUser scope)
- **Rationale:** Required for npm and custom PowerShell scripts to run without being blocked. RemoteSigned requires that scripts downloaded from the Internet be signed, while locally-created scripts can run freely.

### Rust Installation
- **Method:** `winget install Rustlang.Rustup`
- **Expected outcome:** Installs `rustup`, which installs `rustc` + `cargo` with the `stable-x86_64-pc-windows-msvc` toolchain

---

## Entry 002 — [To be filled during Unbound installation]

---

## Entry 003 — [To be filled during AdGuard Home installation]

---

## Entry 004 — [To be filled during firewall rule creation]

---

## Entry 005 — [To be filled after first successful DNS test]

---

## Bug Log

*No bugs yet. Bugs will be recorded here with: date, symptom, root cause, fix, prevention.*

---

## Security Decisions Log

| Decision | Rationale | Date |
|----------|-----------|------|
| Block port 53 on all non-LAN interfaces | Prevent open recursive resolver / DNS amplification | 2026-08-16 |
| Admin UI loopback-only | Prevent LAN devices from accessing resolver configuration | 2026-08-16 |
| No query logging | DNS history is browsing history — privacy-first | 2026-08-16 |
| No auto-update for AdGuard Home | Control when updates are applied, avoid surprise behavior changes | 2026-08-16 |
| DNSSEC validation enabled | Reject forged DNS responses for DNSSEC-signed zones | 2026-08-16 |
| Unbound loopback-only | Unbound must never be a direct public resolver | 2026-08-16 |

---

## Benchmark Log

*Benchmarks will be recorded here after Stage 2.*

| Date | Metric | Value | Notes |
|------|--------|-------|-------|
| — | Cold-cache latency | — | First lookup, empty cache |
| — | Warm-cache latency | — | Same domain, from cache |
| — | Blocked domain response | — | Immediate, no upstream |
| — | vs 8.8.8.8 | — | Same network, same domain |
| — | vs 1.1.1.1 | — | Same network, same domain |
| — | vs 9.9.9.9 | — | Same network, same domain |
