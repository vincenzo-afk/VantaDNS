# VantaDNS Supercharged — Maximum Ad & Tracker Blocking

This update turns your on-phone VantaDNS server into a maximum-blocking
machine, verified with a live test run.

## What changed

| Item | Before | After |
|------|--------|-------|
| Total blocking rules | ~120 rules | **435,000+ rules** |
| Blocklists | local/custom only | OISD Big + Hagezi Pro + KADhosts + AdGuard DNS Filter + AdGuard base + mobile-app ads |
| Rule parser | hosts/raw domains/AdGuard `||x^` | Now also Adblock Plus `$` options, DNS `*.wildcard` syntax |
| Memory usage | minimal | ~65 MB (verified) |
| Update process | manual | one command |

## Blocklists now loaded

- **OISD Big** (268,958 rules) — the "Block. Don't break." list: ads,
  trackers, phishing, malvertising, spyware. Curated for zero false positives.
- **Hagezi Pro** (216,432 rules) — ads, affiliate links, tracking, telemetry,
  phishing, malware, scam, fake sites, cryptojacking.
- **KADhosts** (62,470 rules) — fraud, SMS-scam, malware, fake-shop domains.
- **AdGuard DNS Filter** (10,500+ rules) — ads, trackers, malware.
- **AdGuard base** + mobile-app ad lists (Spotify/YouTube/Instagram trackers)

## Verified results (live test)

- 435,266 rules loaded, server uses ~65 MB RAM — safe for any 4 GB+ phone
- `doubleclick.net`, `ads.yahoo.com`, `cdn.mxpnl.com` (Mixpanel),
  `analytics.tiktok.com` → **NXDOMAIN** (blocked)
- Deep subdomains under wildcard rules (e.g., `some.random.thing.007moms.com`)
  → also blocked ✅
- `google.com`, `github.com`, `wikipedia.org`, `reddit.com`, `instagram.com`
  → resolve normally ✅

## Update your phone (copy-paste)

```bash
cd ~/VantaDNS && git pull
bash ~/VantaDNS/phone/update-blocklists.sh
```

That's it. The script downloads the latest maximum lists, reloads the
server, and prints the total rule count when done.

To update lists again anytime in the future, just run:

```bash
bash ~/VantaDNS/phone/update-blocklists.sh
```

## One honest caveat

A DNS blocker can only kill domains it can see. A few things remain
outside any DNS filter's reach, and it's not a bug — it's physics:

1. **YouTube video ads** — served from the same `googlevideo.com`
   infrastructure as the videos themselves. Still needs ReVanced (see
   `docs/youtube-revanced-combo.md`).
2. **Ads baked into image/video streams** — the image itself contains the
   ad (e.g., YouTube banner images, sponsored posts in feeds). DNS can't
   distinguish them.
3. **IP-hardcoded ad calls** — apps that talk to ad servers by raw IP
   instead of a domain. Very rare.

For everything else — banners, trackers, analytics, overlay ads, malware
domains — you now have one of the largest combined blocklists running
locally on your phone.
