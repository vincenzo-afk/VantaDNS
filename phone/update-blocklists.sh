#!/bin/bash
# ============================================================
# VantaDNS — one-command blocklist supercharger for Termux
# Downloads the latest maximum blocklists, reloads the server.
#
#   bash ~/VantaDNS/phone/update-blocklists.sh
# ============================================================
set -euo pipefail

VANTA="$HOME/VantaDNS"
LISTS="$VANTA/config/blocklists"
BIN="$VANTA/bin/vanta-vpn.sh"

green() { echo -e "\033[32m$1\033[0m"; }
step() { echo ""; green "== $1"; }

step "Stopping VantaDNS server"
"$BIN" stop 2>/dev/null || true

mkdir -p "$LISTS"

fetch() {
    local url="$1" out="$2"
    local tmp="$out.tmp"
    # Retry with backoff + keep partially-downloaded file for resume
    local attempt=1
    local max_attempts=5
    while [ "$attempt" -le "$max_attempts" ]; do
        if curl -sSL -C - --retry 3 --retry-all-errors --max-time 120 "$url" -o "$tmp" 2>/dev/null; then
            if grep -qE "^[a-z0-9*.]" "$tmp" 2>/dev/null; then
                mv "$tmp" "$out"
                green "  fetched: $out ($(wc -l < "$out") lines)"
                return 0
            fi
        fi
        echo "  retrying $out ($attempt/$max_attempts)..."
        attempt=$((attempt + 1))
        sleep 3
    done
    rm -f "$tmp"
    echo "  skip $out (network error — will retry next time)"
}

step "Downloading maximum blocklists"
fetch "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt" "adguard-base.txt"
fetch "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt" "adguard-dns-filter.txt"
fetch "https://big.oisd.nl/" "oisd-big.txt"
fetch "https://kadantiscam.netlify.app/kadhosts.txt" "kadhosts.txt" || \
    fetch "https://raw.githubusercontent.com/PolishFiltersTeam/KADhosts/master/KADhosts.txt" "kadhosts.txt"
fetch "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.txt" "hagezi-pro-wild.txt"

TOTAL=0
for f in "$LISTS"/*.txt; do
    TOTAL=$((TOTAL + $(wc -l < "$f")))
done
green "Total blocking rules loaded: $TOTAL"

step "Restarting VantaDNS server"
"$BIN" start
green ""
green "All ads & trackers supercharged! Run: dig @127.0.0.1 -p 5353 doubleclick.net"
