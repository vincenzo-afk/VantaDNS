#!/bin/bash
# ============================================================
# VantaDNS — maximum blocklist supercharger for Termux
# Downloads lists in small chunks (resumable, survives flaky mobile data)
# with fallback mirrors. Then reloads the server.
#
#   bash ~/VantaDNS/phone/update-blocklists.sh
# ============================================================
set -euo pipefail

VANTA="$HOME/VantaDNS"
LISTS="$VANTA/config/blocklists"
BIN="$VANTA/bin/vanta-vpn.sh"

green()  { echo -e "\033[32m$1\033[0m"; }
red()    { echo -e "\033[31m$1\033[0m"; }
blue()   { echo -e "\033[36m$1\033[0m"; }

step() { echo ""; green "== $1"; }

step "Stopping VantaDNS server"
"$BIN" stop 2>/dev/null || true

mkdir -p "$LISTS"

# Download a file robustly: retry with resume + fallback mirrors + progress.
# Usage: fetch_robust OUTPUT_NAME URL1 [URL2 ...]
fetch_robust() {
    local out="$1"; shift
    local tmp="$LISTS/$out.dl"
    rm -f "$tmp"

    for url in "$@"; do
        echo -e "  \033[33m  downloading $out from $url ...\033[0m"
        local attempt=1
        while [ "$attempt" -le 6 ]; do
            # -C - resumes a partial download; --max-time limits each attempt
            if curl -sSL -C - --retry 2 --retry-all-errors \
                    --max-time 150 --progress-bar "$url" -o "$tmp"; then
                if [ -s "$tmp" ] && grep -qE "^[a-z0-9*.]" "$tmp" 2>/dev/null; then
                    mv "$tmp" "$LISTS/$out"
                    green "  ✔ fetched: $out ($(wc -l < "$LISTS/$out") lines)"
                    return 0
                fi
            fi
            blue "    retry $attempt — resuming from where it stopped..."
            attempt=$((attempt + 1))
            sleep 3
        done
        rm -f "$tmp"
        echo "    ✘ mirror failed for $out, trying next..."
    done
    red "  ✘ SKIP $out (all sources failed — will retry next run)"
    return 1
}

# Bundled big lists (OISD, KADhosts) ship with the repo in small line-safe
# chunks (config/blocklists/bundled/*) — git pull delivers them reliably.
# The refresh below splits any freshly-downloaded list into those chunks.
split_into_chunks() {
    local src="$1" name="$2" bytes="$3"
    [ -f "$src" ] || return 0
    mkdir -p "$LISTS/bundled"
    rm -f "$LISTS/bundled/${name}.part"*
    python3 - "$src" "$LISTS/bundled/$name" "$bytes" << 'PYEOF'
import sys, os
src, prefix, maxbytes = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(src, "r", encoding="utf-8", errors="replace") as fp:
    lines = fp.readlines()
chunks, cur, n = [], [], 0
for line in lines:
    cur.append(line)
    n += len(line.encode("utf-8", "replace"))
    if n >= maxbytes:
        chunks.append(cur)
        cur, n = [], 0
if cur:
    chunks.append(cur)
for i, chunk in enumerate(chunks):
    out = f"{prefix}.part{chr(97 + i % 26)}{chr(97 + i // 26) if i >= 26 else ''}"
    with open(out, "w", encoding="utf-8") as fp:
        fp.writelines(chunk)
print(f"chunked {len(lines)} lines into {len(chunks)} parts", flush=True)
PYEOF
    green "  ✔ split $name into chunks under bundled/"
}

step "Downloading maximum blocklists"
green ""

fetch_robust "adguard-base.txt" \
    "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"

fetch_robust "adguard-dns-filter.txt" \
    "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt" || true

# Refresh the bundled big lists (shipped in repo chunks) when downloads succeed.
OISD_TMP="$LISTS/.oisd-big.tmp"
if curl -sSL -C - --retry 2 --retry-all-errors --max-time 300 --progress-bar "https://big.oisd.nl/" -o "$OISD_TMP" || \
   curl -sSL --retry 2 --max-time 300 --progress-bar "https://raw.githubusercontent.com/sjhgvr/oisd/main/dnsmasq_big.txt" -o "$OISD_TMP"; then
    if [ -s "$OISD_TMP" ] && grep -qE "^[a-z0-9*.]" "$OISD_TMP" 2>/dev/null; then
        mv "$OISD_TMP" "$LISTS/.oisd-big-full.txt"
        split_into_chunks "$LISTS/.oisd-big-full.txt" "oisd-big" 500000
    else
        rm -f "$OISD_TMP"
        blue "  oisd-big chunks from git pull already in place — keeping those"
    fi
fi

KAD_TMP="$LISTS/.kadhosts.tmp"
if curl -sSL --retry 2 --retry-all-errors --max-time 300 --progress-bar "https://raw.githubusercontent.com/PolishFiltersTeam/KADhosts/master/KADhosts.txt" -o "$KAD_TMP"; then
    if [ -s "$KAD_TMP" ] && grep -qE "^[a-z0-9*.]" "$KAD_TMP" 2>/dev/null; then
        mv "$KAD_TMP" "$LISTS/.kadhosts-full.txt"
        split_into_chunks "$LISTS/.kadhosts-full.txt" "kadhosts" 500000
    else
        rm -f "$KAD_TMP"
        blue "  kadhosts chunks from git pull already in place — keeping those"
    fi
fi

fetch_robust "hagezi-pro-wild.txt" \
    "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.txt" \
    "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@main/wildcard/pro.txt" || true

fetch_robust "hagezi-pro-plus.txt" \
    "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.plus.txt" \
    "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@main/wildcard/pro.plus.txt" || true

fetch_robust "stevenblack-domains.txt" \
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" || true

# Convert StevenBlack hosts format (0.0.0.0 domain) -> bare domains
if [ -f "$LISTS/stevenblack-domains.txt" ] && grep -q "^0\.0\.0\.0" "$LISTS/stevenblack-domains.txt"; then
    grep -E "^0\.0\.0\.0" "$LISTS/stevenblack-domains.txt" | awk '{print $2}' \
        | grep -E '^[a-z0-9]' | sort -u > "$LISTS/.stevenblack.tmp" && \
        mv "$LISTS/.stevenblack.tmp" "$LISTS/stevenblack-domains.txt"
fi

rm -f "$LISTS"/.oisd-big-full.txt "$LISTS"/.kadhosts-full.txt

green ""
TOTAL=0
for f in "$LISTS"/*.txt "$LISTS"/bundled/*.part*; do
    [ -f "$f" ] || continue
    TOTAL=$((TOTAL + $(wc -l < "$f")))
done
green "Total blocking rules loaded: $TOTAL"

step "Restarting VantaDNS server"
"$BIN" start

if [ "$TOTAL" -gt 200000 ]; then
    green ""
    green "SUPERCHARGED! Blocking ~$TOTAL ad/tracker domains."
    green "Test: dig @127.0.0.1 -p 5353 doubleclick.net  (should show NXDOMAIN)"
else
    red ""
    red "Below 200k rules — some big lists failed. Run this script again,"
    red "ideally on Wi-Fi, to finish downloading."
fi
