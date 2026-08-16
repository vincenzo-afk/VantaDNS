#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# VantaDNS — One-Command On-Phone Setup (Termux, no root)
#
# What this does:
#   1. Installs Termux packages (git, python, termux-services deps)
#   2. Clones/pulls the VantaDNS repo to $HOME/VantaDNS
#   3. Downloads the pre-built aarch64 Android binary from GitHub Releases
#   4. Pulls the latest AdGuard base filter list
#   5. Installs the vanta VPN wrapper (DNS interception via local TUN)
#   6. Registers Termux:Boot autostart (auto-starts on phone boot)
#
# Prerequisites (installed from F-Droid):
#   - Termux:   https://f-droid.org/packages/com.termux/
#   - Termux:Boot + Termux:API (optional but recommended for boot start)
# ============================================================
set -euo pipefail

VANTA_DIR="$HOME/VantaDNS"
ARCHIVE_URL="https://github.com/vincenzo-afk/VantaDNS/releases/latest/download/vanta-dns-core-aarch64-android"

green()  { echo -e "\033[32m$1\033[0m"; }
red()    { echo -e "\033[31m$1\033[0m"; }
step()   { echo ""; green "== $1"; }

step "Installing Termux packages"
pkg update -y 2>/dev/null
pkg install -y git curl python

step "Cloning VantaDNS (or pulling latest)"
if [ -d "$VANTA_DIR/.git" ]; then
    cd "$VANTA_DIR" && git pull --ff-only || true
else
    rm -rf "$VANTA_DIR"
    git clone --depth 1 https://github.com/vincenzo-afk/VantaDNS.git "$VANTA_DIR"
fi
cd "$VANTA_DIR"

step "Downloading pre-built Android ARM64 binary"
mkdir -p "$VANTA_DIR/bin"
if curl -sSfL "$ARCHIVE_URL" -o "$VANTA_DIR/bin/vanta-dns-core"; then
    chmod +x "$VANTA_DIR/bin/vanta-dns-core"
    green "Binary installed: $(ls -lh $VANTA_DIR/bin/vanta-dns-core | awk '{print $5}')"
else
    red "Release binary unavailable — building from source on the phone (takes 5-15 min)..."
    pkg install -y rust
    cd "$VANTA_DIR/dns-core"
    cargo build --release
    cp target/release/vanta-dns-core "$VANTA_DIR/bin/vanta-dns-core"
    chmod +x "$VANTA_DIR/bin/vanta-dns-core"
fi

step "Fetching the maximum blocklists"
mkdir -p "$VANTA_DIR/config/blocklists"
curl -sSL --retry 3 --retry-all-errors --max-time 180 "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt" \
    -o "$VANTA_DIR/config/blocklists/adguard-base.txt" || \
    red "  AdGuard base fetch failed (offline?) — bundled lists still apply"
curl -sSL --retry 3 --retry-all-errors --max-time 180 "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt" \
    -o "$VANTA_DIR/config/blocklists/adguard-dns-filter.txt" || true
curl -sSL --retry 3 --retry-all-errors --max-time 240 "https://big.oisd.nl/" \
    -o "$VANTA_DIR/config/blocklists/.oisd-big-full.txt" || true
curl -sSL --retry 3 --retry-all-errors --max-time 120 "https://raw.githubusercontent.com/PolishFiltersTeam/KADhosts/master/KADhosts.txt" \
    -o "$VANTA_DIR/config/blocklists/.kadhosts-full.txt" || true
# Split any downloaded big lists into line-safe bundled chunks
python3 - "$VANTA_DIR" << 'PYEOF'
import sys, os
base = sys.argv[1]
bl = f"{base}/config/blocklists"
for name in ["oisd-big", "kadhosts"]:
    src = f"{bl}/.{name}-full.txt"
    if not os.path.isfile(src) or os.path.getsize(src) < 1000:
        continue
    with open(src, "r", encoding="utf-8", errors="replace") as fp:
        lines = fp.readlines()
    chunks, cur, n = [], [], 0
    for line in lines:
        cur.append(line)
        n += len(line.encode("utf-8", "replace"))
        if n >= 500000:
            chunks.append(cur)
            cur, n = [], 0
    if cur:
        chunks.append(cur)
    os.makedirs(f"{bl}/bundled", exist_ok=True)
    for f in os.listdir(f"{bl}/bundled"):
        if f.startswith(f"{name}.part"):
            os.remove(f"{bl}/bundled/{f}")
    for i, chunk in enumerate(chunks):
        with open(f"{bl}/bundled/{name}.part{chr(97 + i % 26)}{chr(97 + i // 26) if i >= 26 else ''}", "w", encoding="utf-8") as fp:
            fp.writelines(chunk)
    os.remove(src)
    print(f"chunked {name}: {len(lines)} lines into {len(chunks)} parts", flush=True)
PYEOF
curl -sSL --retry 3 --retry-all-errors --max-time 180 "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.txt" \
    -o "$VANTA_DIR/config/blocklists/hagezi-pro-wild.txt" || true

step "Installing the local DNS VPN wrapper (always refresh existing copy)"
cp "$VANTA_DIR/phone/vanta-vpn.sh" "$VANTA_DIR/bin/"
cp "$VANTA_DIR/phone/dns-udp-forwarder.py" "$VANTA_DIR/bin/"
cp "$VANTA_DIR/phone/update-blocklists.sh" "$VANTA_DIR/bin/"
chmod +x "$VANTA_DIR/bin/vanta-vpn.sh" "$VANTA_DIR/bin/update-blocklists.sh"

step "Setting up boot autostart (Termux:Boot)"
mkdir -p "$HOME/.termux/boot"
cat > "$HOME/.termux/boot/start-vantadns.sh" << 'BOOTEOF'
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
/data/data/com.termux/files/home/VantaDNS/bin/vanta-vpn.sh start &
BOOTEOF
chmod +x "$HOME/.termux/boot/start-vantadns.sh"

step "Installing one-tap home screen launchers (Termux:Widget)"
cp "$VANTA_DIR/phone/toggle_vantadns" "$VANTA_DIR/phone/start_vantadns" "$VANTA_DIR/phone/stop_vantadns" \
   "$VANTA_DIR/bin/"
chmod +x "$VANTA_DIR/bin/toggle_vantadns" "$VANTA_DIR/bin/start_vantadns" "$VANTA_DIR/bin/stop_vantadns"
for d in "$HOME/.shortcuts" "$HOME/.termux/widget"; do
    mkdir -p "$d"
    cp -f "$VANTA_DIR/bin/toggle_vantadns" "$VANTA_DIR/bin/start_vantadns" "$VANTA_DIR/bin/stop_vantadns" "$d/" 2>/dev/null || true
    chmod +x "$d/"* 2>/dev/null || true
done
green "  Launcher scripts also in ~/VantaDNS/bin/ and ~/.shortcuts/"

green ""
green "============================================================"
green "  VantaDNS installed on your phone!"
green ""
green "  To start blocking ads right now:"
green "    ~/VantaDNS/bin/vanta-vpn.sh start"
green ""
green "  To stop:"
green "    ~/VantaDNS/bin/vanta-vpn.sh stop"
green ""
green "  To verify (should show NXDOMAIN):"
green "    nslookup doubleclick.net 127.0.0.1 -p 8533"
green "============================================================"
