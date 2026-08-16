# VantaDNS Cloud Deployment Guide

This document explains how to run VantaDNS as a public **DNS-over-TLS (DoT)** server
on a cloud platform, giving you a real public domain with a trusted SSL certificate
so any Android phone can use it as a **Private DNS** server on 4G/5G/Wi-Fi.

## Why a cloud instance solves the CGNAT problem

When VantaDNS runs at home, mobile carriers put you behind CGNAT and often block
unusual ports, so Android Private DNS cannot reach your home server reliably. A
cloud instance has a **real public IP**, is never behind CGNAT, and is reachable
from any carrier network.

## Architecture on Fly.io (recommended)

Fly.io's edge proxy can terminate TLS for **any TCP port** using a managed
Let's Encrypt certificate for your `<app>.fly.dev` hostname. The proxy's
`handlers = ["tls"]` setting on port 853 terminates TLS and forwards plain,
length-framed DNS (RFC 7858) to the app on the same internal port. VantaDNS
only needs its TCP listener — no certificate handling at all.

```
Android (Private DNS)  --TLS:853-->  Fly Proxy (managed cert)  --plain TCP-->  VantaDNS (TCP 853)
```

The VantaDNS binary was extended in this release to:

- Listen on **plain DNS-over-TCP** (RFC 1035 2-byte length framing) — required
  behind the Fly TLS handler.
- Optionally listen with **app-terminated TLS** (`tls_enabled = true` plus
  `TLS_CERT`/`TLS_KEY`) for self-hosted DoT on port 853 without any proxy.
- Forward queries over **TCP or UDP** to configurable upstream resolvers
  (`tcp:1.1.1.1:53`, `udp:9.9.9.9:53`, …) — no local Unbound/AdGuard dependency,
  so the container is fully standalone.
- Load bundled blocklists (mobile ads, Spotify, YouTube) plus any AdGuard-format
  list, with allowlist override support.

## Deploying to Fly.io

Prerequisites: `flyctl` CLI and a Fly.io account (https://fly.io).

```bash
flyctl auth login
flyctl launch --no-deploy      # or: fly launch
# The included fly.toml configures the TLS handler on port 853.
flyctl deploy
```

After deploy your server lives at `vanta-dns.fly.dev`.

## Android setup

1. Settings → Network & internet → Private DNS → **Private DNS provider hostname**
2. Enter `vanta-dns.fly.dev` → Save

Android now sends all DNS over TLS to your server on every connection
(4G/5G and Wi-Fi), and ads tracked by the blocklists return NXDOMAIN.

Verify in a terminal app or with a DoT checker app: blocked domains
(e.g. `doubleclick.net`) must return NXDOMAIN; normal domains resolve.

## Costs and limitations (August 2026)

| Item | Detail |
|------|--------|
| Fly.io free tier | **Discontinued.** New accounts get a free *trial* of 2 total VM-hours over 7 days; trial machines auto-stop after 5 minutes of inactivity — usable for testing only. |
| Hobby plan | $5/month minimum; the VantaDNS machine (shared-cpu-1x, 256MB) costs roughly $2/month. A credit card is required. |
| Render free tier | HTTP-only; cannot expose raw TCP 853, so DoT will **not** work on free Render. Paid Render starts at $7/month. |

**Bottom line:** a permanently-free public DoT server is no longer realistically
possible on mainstream platforms. The cheapest reliable option is Fly.io Hobby
at ~$2/month for this machine.

## Local / self-hosted DoT (no cloud)

```bash
TLS_CERT=certs/tls.crt TLS_KEY=certs/tls.key \
  vanta-dns-core run --config config/docker-vanta-dns.toml
```

The app will listen on TCP 5353 (plain) and TLS port 853 (DoT, RFC 7858).
On Android you can only point Private DNS at a hostname whose certificate
chain is trusted — a self-signed cert won't work on mobile data, which is
exactly why the cloud deployment with a managed certificate is the right path.

## Testing

Unit tests: `cargo test`
DoT integration test (requires server running on 127.0.0.1:5353/853 with test
config): `cargo test --test dot_integration -- --nocapture`

Raw check from any machine with `dig`:

```bash
dig doubleclick.net A @vanta-dns.fly.dev -p 853 +tls +tls-ca=ca.pem
```
