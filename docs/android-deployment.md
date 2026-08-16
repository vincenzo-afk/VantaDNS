# VantaDNS — Android Deployment Guide

This guide details how to transition your working VantaDNS platform from the PC reference server to an old Android smartphone (`aarch64` / `ARM64` architecture) to serve as a low-power (3-5W), dedicated 24/7 personal DNS appliance.

---

## 1. Hardware & System Requirements

- **Device:** Old Android phone (Android 7.0+ recommended)
- **Architecture:** `aarch64` (64-bit ARM) or `armv7` (32-bit ARM)
- **RAM:** Minimum 1 GB RAM (VantaDNS + Unbound use < 150 MB total)
- **Storage:** Minimum 500 MB free internal storage
- **Network:** Wi-Fi or USB tethering connected to your local network with a static DHCP reservation (e.g., `10.76.181.50`).

---

## 2. Approach Overview

| Approach | Root Required? | Advantages | Deployment Steps |
|----------|----------------|------------|------------------|
| **Termux + Native Build** | ❌ No | Easiest setup, full package manager (`pkg install unbound rust`), no cross-compiler setup required | Section 3 |
| **Android NDK Cross-Compilation** | ❌ No | Compact static ELF binary built directly on PC | Section 4 |
| **Rooted Android (Port 53)** | ✅ Yes | Binds directly to port `53` without VPN wrapper | Section 5 |

---

## 3. Termux Deployment (No Root Required)

Termux is a terminal emulator and Linux environment app for Android.

### Step 1: Install Termux
1. Download and install **Termux** from **F-Droid** (do NOT use Google Play Store version as it is deprecated).
2. Open Termux and update base packages:
   ```bash
   pkg update && pkg upgrade -y
   ```

### Step 2: Install Unbound & Rust Engine
```bash
# Install dependencies
pkg install -y unbound rust git clang make

# Verify Unbound installation
unbound -v
```

### Step 3: Clone & Build VantaDNS Core on Android
```bash
# Clone repository
git clone https://github.com/vincenzo-afk/VantaDNS.git
cd VantaDNS/dns-core

# Build release binary
cargo build --release

# Test in-memory benchmark on phone
./target/release/vanta-dns-core benchmark
```

---

## 4. Cross-Compiling from PC (`aarch64-linux-android`)

If you prefer to compile on your PC and transfer the binary to your phone:

### Step 1: Install Target in Rustup (on PC)
```powershell
rustup target add aarch64-linux-android
```

### Step 2: Build Release Binary for Android ARM64
```powershell
cd dns-core
cargo build --target aarch64-linux-android --release
```
The compiled binary will be generated at `dns-core/target/aarch64-linux-android/release/vanta-dns-core`.

### Step 3: Push to Phone via ADB
```powershell
adb push target/aarch64-linux-android/release/vanta-dns-core /data/local/tmp/
adb shell "chmod +x /data/local/tmp/vanta-dns-core"
```

---

## 5. Auto-Start Service on Boot

To ensure VantaDNS runs continuously even if the phone reboots:

### Termux Boot Setup
1. Install **Termux:Boot** app from F-Droid.
2. Create startup directory in Termux:
   ```bash
   mkdir -p ~/.termux/boot/
   ```
3. Create auto-start script `~/.termux/boot/start-vantadns.sh`:
   ```bash
   #!/usr/bin/env sh
   termux-wake-lock
   unbound -c ~/VantaDNS/config/unbound/service.conf &
   ~/VantaDNS/dns-core/target/release/vanta-dns-core run --config ~/VantaDNS/config/vanta-dns.toml &
   ```
4. Make script executable: `chmod +x ~/.termux/boot/start-vantadns.sh`

### Power Management Tuning
- Disable **Battery Optimization** for Termux and Termux:Boot in Android **Settings** > **Battery** > **Battery Optimization** -> **Don't Optimize**.
- Enable **Keep screen off while running** in Termux settings.
- Keep the phone connected to a standard USB charger.
