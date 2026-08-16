# VantaDNS + ReVanced — The Complete Ad-Free Combo

Your phone runs VantaDNS as a local DNS ad blocker, which kills ad
**tracking, banners, and overlay ads** across every app. But YouTube video
ads (pre-roll, mid-roll) are served from `googlevideo.com` — the exact same
domain that delivers the actual videos — so no DNS blocker can remove them
without breaking playback.

**ReVanced** patches the YouTube app itself, so video ads are removed inside
the app. Together they cover everything:

| Layer | What it blocks | Coverage |
|-------|----------------|----------|
| VantaDNS (DNS) | Tracking, banners, overlay ads, analytics | Every app, system-wide DNS |
| ReVanced (app patch) | Video pre-roll/mid-roll ads, shorts ads, sponsors | YouTube / YT Music only |

---

## Part 1 — Install ReVanced (patched YouTube, no video ads)

### ⚠️ Safety first — only use the official site

The **only official ReVanced website is [revanced.app](https://revanced.app)**.
Many fake sites (vanced.to clones, "revanced.io", Telegram APKs) bundle
malware. Never download ReVanced Manager from anywhere except revanced.app
or its official GitHub ([github.com/revanced](https://github.com/revanced)).

### Step-by-step

1. **Uninstall stock YouTube** (Settings → Apps → YouTube → Uninstall).
   The patched version replaces it.

2. **Download ReVanced Manager** from [revanced.app/download](https://revanced.app/download)
   (Manager v2, patched with Patcher v22). Allow "Install unknown apps" for
   your browser when Android asks.

3. **Open ReVanced Manager → Patcher tab → Select an application**.
   - If "YouTube" appears in the list (downloaded/stored), choose it and
     Manager fetches a compatible official APK automatically.
   - Otherwise, download the matching official YouTube APK from
     [APKMirror](https://www.apkmirror.com/apk/google-inc/youtube/) and
     select it from storage. Use the **latest release version** (not a beta).

4. **Select patches.** For ads, ensure these are checked (they are enabled
   by default):
   - `Hide ads` — removes video, banner, and Shorts ads
   - `Video ads / General ads` removal patches
   - Optionally: `Background playback`, `Remember playback position`,
     `SponsorBlock` (skips in-video sponsor segments)

5. **Tap Patch → install.** Manager compiles the patched APK and installs
   it. Sign in with your Google account if you want subscriptions/history
   (sign-in is supported in the patched app).

6. **Open YouTube.** Pre-roll ads are gone. If an occasional ad slips
   through (YouTube rotates ad delivery), update patches in Manager and
   repatch — this happens rarely after patch releases.

### Troubleshooting ReVanced

- **"Patching failed / incompatible version"** → the stored APK is too old
  or a beta. Delete it in Manager → Apps tab, and let Manager download a
  fresh official APK.
- **Ads still showing** → make sure the `Hide ads` patch is selected, and
  check Settings → the app you patched uses the revanced-microg or
  revanced-integrations as configured by Manager. Repatch with the latest
  patches.
- **Shorts ads** → occasionally regressed in YouTube's backend; repatch to
  the newest patch set (see the [open Shorts-ads issue](https://github.com/ReVanced/revanced-manager/issues/3228)
  for status).

---

## Part 2 — VantaDNS (already running on your phone ✅)

Keep `~/VantaDNS/bin/vanta-vpn.sh` running. It blocks ad **trackers and
banners** in Instagram, Spotify, browsers, and every other app. No changes
needed.

### Optional: strengthen the blocklists

Add heavy-hitter lists so more trackers get blocked at the DNS level:

```bash
cd ~/VantaDNS/config/blocklists
curl -sSL "https://oisd.nl/big" -o oisd-big.txt
curl -sSL "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/pro.txt" -o hagezi-pro.txt
# Add them to the filter list in ~/VantaDNS/phone/phone-vanta-dns.toml:
nano ~/VantaDNS/phone/phone-vanta-dns.toml
#   ...add to blocklist_paths:
#     "$HOME/VantaDNS/config/blocklists/oisd-big.txt",
#     "$HOME/VantaDNS/config/blocklists/hagezi-pro.txt"
# Then restart:
~/VantaDNS/bin/vanta-vpn.sh stop
~/VantaDNS/bin/vanta-vpn.sh start
```

(Heavy lists raise memory usage a bit; on a 4 GB+ phone it's fine. If you
see memory pressure, drop oisd-big and keep hagezi-pro.)

---

## Result

YouTube: zero video ads (ReVanced). Everything else: zero tracking/banner
ads (VantaDNS). Phone battery/RAM impact stays minimal — both layers are
lightweight.
