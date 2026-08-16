# VantaDNS — Privacy Policy

This document describes exactly what information VantaDNS collects, stores, transmits, and retains.  
It is intentionally direct and technical. There is no marketing language.

---

## What VantaDNS Does NOT Do

- ❌ Does not log individual DNS queries to disk
- ❌ Does not build a browsing history
- ❌ Does not send query data to third parties
- ❌ Does not include analytics, telemetry, or crash reporting
- ❌ Does not phone home to AdGuard servers (auto-update and telemetry disabled)
- ❌ Does not retain personally identifiable information
- ❌ Does not associate queries with client IP addresses in stored logs

---

## What VantaDNS Does Retain (In Memory, Resets on Restart)

| Data | Location | Retention | Purpose |
|------|----------|-----------|---------|
| DNS response cache | Unbound RAM | Until TTL expires or restart | Faster repeat lookups |
| Aggregate query count | AdGuard Home RAM | Reset on restart | Dashboard display |
| Aggregate block count | AdGuard Home RAM | Reset on restart | Dashboard display |
| Cache hit rate | Unbound RAM | Reset on restart | Performance monitoring |
| Per-domain block events | AdGuard Home RAM (24h) | 24h rolling, no names retained by default | Block count only |

**Note:** The 24h statistics window in AdGuard Home stores aggregate counts (total queries, total blocked), not individual query records. With query logging disabled, AdGuard Home does NOT store per-query history.

---

## What Leaves Your Network

### During Recursive DNS Resolution

When Unbound resolves a domain recursively, it contacts:
1. **Root name servers** (one of 13 root server clusters, globally distributed)
2. **TLD name servers** (e.g., Verisign for `.com`)
3. **Authoritative name servers** (the DNS servers for the specific domain)

Each of these servers sees:
- The DNS query (domain name + record type)
- Your public IP address (as assigned by your ISP)

### QNAME Minimisation (RFC 7816)

Unbound uses QNAME minimisation to limit leakage:
- Root servers are sent only the TLD (e.g., `.com`)
- TLD servers are sent only the second-level domain (e.g., `example.com`)
- Only the authoritative server sees the full query name

### Blocklist Updates

When AdGuard Home automatically updates blocklists, it makes HTTP/HTTPS GET requests to:
- `https://filters.adtidy.org` (AdGuard DNS filter)
- `https://easylist.to` (EasyList, EasyPrivacy)
- `https://raw.githubusercontent.com` (Steven Black's list)

These requests reveal your public IP address to those servers. The requests contain no query history or personal data. They are simple file downloads.

### What Is NOT Sent Externally

- No DNS query history
- No client IP addresses from your LAN
- No AdGuard Home account or user data (no account is used)
- No Windows telemetry related to VantaDNS (VantaDNS does not inject Windows telemetry)

---

## Enabling Query Logging (Temporary Debugging Only)

Query logging can be temporarily enabled in AdGuard Home for debugging:

1. Open `http://127.0.0.1:3000`
2. Go to Settings → General Settings
3. Enable "Query Log"
4. Debug your issue
5. **Immediately disable and clear the log when done**

When enabled, AdGuard Home writes individual DNS queries (domain, timestamp, response, client IP) to `data/querylog.json`. This file is excluded from version control via `.gitignore`. It should be deleted after debugging.

---

## DNSSEC and Privacy

DNSSEC validation is performed locally by Unbound. DNSSEC signatures are verified against the IANA root trust anchor. No external validation service is contacted. Zones that are signed are validated; zones that are not signed are passed through without validation.

---

## Changes to This Policy

This policy reflects the current VantaDNS configuration. If configuration changes affect privacy (e.g., enabling query logging permanently, adding a logging upstream, enabling AdGuard account sync), this document must be updated to reflect the change and the reason recorded in `ENGINEERING_LOG.md`.
