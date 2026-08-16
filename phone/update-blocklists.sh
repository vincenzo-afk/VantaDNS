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

step "Downloading maximum blocklists"
green ""

fetch_robust "adguard-base.txt" \
    "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"

fetch_robust "adguard-dns-filter.txt" \
    "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt" || true

fetch_robust "oisd-big.txt" \
    "https://big.oisd.nl/" \
    "https://raw.githubusercontent.com/sjhgvr/oisd/main/dnsmasq_big.txt" \
    "https://cdn.jsdelivr.net/gh/sjhgvr/oisd@main/dnsmasq_big.txt" || true

fetch_robust "kadhosts.txt" \
    "https://raw.githubusercontent.com/PolishFiltersTeam/KADhosts/master/KADhosts.txt" \
    "https://kadantiscam.netlify.app/kadhosts.txt" || true

fetch_robust "hagezi-pro-wild.txt" \
    "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.txt" \
    "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@main/wildcard/pro.txt" || true

green ""
TOTAL=0
for f in "$LISTS"/*.txt; do
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
