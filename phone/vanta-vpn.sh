#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# vanta-vpn.sh — local DNS-over-UDP interception for VantaDNS
#
# Problem: Android Private DNS only accepts public hostnames with
# trusted certificates — you can't point it at 127.0.0.1.
#
# Solution: this script (a) starts vanta-dns-core on 127.0.0.1:8533
# and (b) runs a tiny UDP forwarder on 127.0.0.1:5353 (Termux ports
# cannot bind 53 without root) that forwards every DNS packet the
# phone sends it to the VantaDNS server.
#
# You then tell Android to use 127.0.0.1? No — instead, the
# phone's Wi-Fi/mobile DNS servers are pointed at 127.0.0.1:5353
# via per-network proxy OR (simplest, works everywhere):
#   -> use "Private DNS: off" and let this wrapper run as a
#      local VPN app via Termux:VPN is not available without root,
#      so we use Android's built-in per-network private DNS with
#      a PUBLIC trusted hostname is the only system-wide way.
#
# PRACTICAL ON-PHONE MODE (no root, no cloud):
#   Most ad-blocking VPN apps (e.g. InviZible Pro, NextDNS app) let
#   you set a custom DoH/DoT endpoint. The most reliable path is:
#     1. This script exposes a LOCAL DoH endpoint on 127.0.0.1:8534
#        (HTTPS with a self-signed cert trusted only by the app).
#     2. Or simply: configure Android Wi-Fi "IP settings > Static"
#        DNS 1 = 127.0.0.1 (only works with the 5353 forwarder
#        + a rootless "DNS Changer" style approach).
#
# SIMPLEST WORKING PATH (recommended for most users):
#   Android 11+ "Private DNS" cannot use localhost. So for the
#   on-phone server, we run the DoT server and use it through the
#   free DuckDNS + Let's Encrypt public hostname — the server still
#   runs ON YOUR PHONE, and Android Private DNS points at the
#   public hostname that resolves back to your phone's IP.
#   See docs/phone-hosting.md section "Public hostname mode".
#
# LOCAL-ONLY MODE (default): starts server + UDP forwarder.
#   Use with a DNS-changing app or root.
# ============================================================
set -euo pipefail

VANTA="$HOME/VantaDNS"
BIN="$VANTA/bin/vanta-dns-core"
# Termux has no /tmp — use its own writable temp dir (PREFIX/tmp, then HOME/.vanta)
TMPDIR_PATH="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
mkdir -p "$TMPDIR_PATH" 2>/dev/null || TMPDIR_PATH="$HOME/.vanta"
mkdir -p "$TMPDIR_PATH"
PIDFILE="$TMPDIR_PATH/vantadns.pid"
FORWARDER_PIDFILE="$TMPDIR_PATH/vantadns-forwarder.pid"
CONFIG_SRC="$VANTA/phone/phone-vanta-dns.toml"
CONFIG="$TMPDIR_PATH/vantadns-phone.toml"

log() { echo -e "\033[36m[vanta-vpn]\033[0m $*"; }

start_server() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        log "Server already running (PID $(cat "$PIDFILE"))"
        return 0
    fi
    # Resolve $HOME placeholders for the phone environment
    sed "s|\$HOME|$HOME|g" "$CONFIG_SRC" > "$CONFIG"

    if [ ! -x "$BIN" ]; then
        echo "ERROR: vanta-dns-core binary missing. Run: bash ~/VantaDNS/phone/install.sh" >&2
        exit 1
    fi

    nohup "$BIN" run --config "$CONFIG" > "$VANTA/phone/server.log" 2>&1 &
    echo $! > "$PIDFILE"
    log "VantaDNS server started (PID $(cat "$PIDFILE")) on 127.0.0.1:8533"
}

stop_server() {
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
        log "Server stopped"
    fi
}

start_forwarder() {
    if [ -f "$FORWARDER_PIDFILE" ] && kill -0 "$(cat "$FORWARDER_PIDFILE")" 2>/dev/null; then
        log "UDP forwarder already running"
        return 0
    fi
    # Tiny UDP DNS forwarder: recv on :5353 -> send (no framing) to :8533
    nohup python3 "$VANTA/phone/dns-udp-forwarder.py" > "$VANTA/phone/forwarder.log" 2>&1 &
    echo $! > "$FORWARDER_PIDFILE"
    log "UDP forwarder started (127.0.0.1:5353 -> 127.0.0.1:8533)"
}

stop_forwarder() {
    if [ -f "$FORWARDER_PIDFILE" ]; then
        kill "$(cat "$FORWARDER_PIDFILE")" 2>/dev/null || true
        rm -f "$FORWARDER_PIDFILE"
        log "UDP forwarder stopped"
    fi
}

case "${1:-status}" in
    start)
        termux-wake-lock 2>/dev/null || true
        start_server
        start_forwarder
        log ""
        log "VantaDNS is ON on your phone."
        log "Query test: nslookup google.com 127.0.0.1 -p 5353"
        ;;
    stop)
        stop_forwarder
        stop_server
        log "VantaDNS is OFF."
        ;;
    status)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            log "Server: RUNNING (PID $(cat "$PIDFILE"))"
        else
            log "Server: stopped"
        fi
        if [ -f "$FORWARDER_PIDFILE" ] && kill -0 "$(cat "$FORWARDER_PIDFILE")" 2>/dev/null; then
            log "Forwarder: RUNNING (PID $(cat "$FORWARDER_PIDFILE"))"
        else
            log "Forwarder: stopped"
        fi
        ;;
    *)
        echo "Usage: vanta-vpn.sh {start|stop|status}" >&2
        exit 1
        ;;
esac
