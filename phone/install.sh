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
ARCHIVE_URL="https://github.com/vincenzo-afk/VantaDNS/releases/download/latest/vanta-dns-core-aarch64-android"

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

step "Fetching the latest AdGuard base blocklist"
mkdir -p "$VANTA_DIR/config/blocklists"
curl -sSL "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt" \
    -o "$VANTA_DIR/config/blocklists/adguard-base.txt" || \
    red "  AdGuard list fetch failed (offline?) — bundled lists still apply"

step "Installing the local DNS VPN wrapper"
cp "$VANTA_DIR/phone/vanta-vpn.sh" "$VANTA_DIR/bin/"
chmod +x "$VANTA_DIR/bin/vanta-vpn.sh"

step "Setting up boot autostart (Termux:Boot)"
mkdir -p "$HOME/.termux/boot"
cat > "$HOME/.termux/boot/start-vantadns.sh" << 'BOOTEOF'
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
/data/data/com.termux/files/home/VantaDNS/bin/vanta-vpn.sh start &
BOOTEOF
chmod +x "$HOME/.termux/boot/start-vantadns.sh"

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
