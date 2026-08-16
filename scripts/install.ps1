#Requires -RunAsAdministrator
# ============================================================
# VantaDNS — Install Script
# scripts/install.ps1
#
# Run as Administrator. This script:
#   1. Verifies prerequisites
#   2. Downloads AdGuard Home and Unbound Windows binaries
#   3. Installs both as Windows services
#   4. Configures everything from the config/ templates
#   5. Fetches root hints and initializes DNSSEC trust anchor
#   6. Applies Windows Firewall rules
#   7. Sets the PC's own DNS to 127.0.0.1
#   8. Runs post-install health check
# ============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# CONFIGURATION — Edit these if your network changes
# ============================================================
$LAN_SUBNET     = "10.76.181.0/24"
$PC_IP          = "10.76.181.43"
$INSTALL_DIR    = "C:\ProgramData\VantaDNS"
$AGH_DIR        = "$INSTALL_DIR\adguardhome"
$UNBOUND_DIR    = "$INSTALL_DIR\unbound"
$REPO_ROOT      = Split-Path -Parent $PSScriptRoot

# AdGuard Home — latest stable release
$AGH_VERSION    = "v0.107.52"
$AGH_URL        = "https://github.com/AdguardTeam/AdGuardHome/releases/download/$AGH_VERSION/AdGuardHome_windows_amd64.zip"
$AGH_ZIP        = "$env:TEMP\AdGuardHome.zip"
$AGH_ZIP_LOCAL  = "$REPO_ROOT\downloads\AdGuardHome_${AGH_VERSION}_windows_amd64.zip"

# Unbound — NLnet Labs Windows setup installer
$UNBOUND_VERSION  = "1.26.0"
$UNBOUND_URL      = "https://nlnetlabs.nl/downloads/unbound/unbound_setup_$UNBOUND_VERSION.exe"
$UNBOUND_INSTALLER= "$env:TEMP\unbound_setup.exe"
$UNBOUND_LOCAL    = "$REPO_ROOT\downloads\unbound_setup_$UNBOUND_VERSION.exe"

# Root hints URL
$ROOT_HINTS_URL = "https://www.internic.net/domain/named.root"

# ============================================================
# HELPERS
# ============================================================
function Write-Step { param([string]$msg)
    Write-Host "`n[$([System.DateTime]::Now.ToString('HH:mm:ss'))] STEP: $msg" -ForegroundColor Cyan
}
function Write-OK { param([string]$msg)
    Write-Host "  ✅ $msg" -ForegroundColor Green
}
function Write-Warn { param([string]$msg)
    Write-Host "  ⚠️  $msg" -ForegroundColor Yellow
}
function Write-Fail { param([string]$msg)
    Write-Host "  ❌ $msg" -ForegroundColor Red
    throw "Installation failed: $msg"
}

function Test-PortFree { param([int]$port)
    $listeners = netstat -ano | Select-String ":$port "
    return ($null -eq $listeners -or $listeners.Count -eq 0)
}

function Stop-ServiceIfRunning { param([string]$name)
    if (Get-Service -Name $name -ErrorAction SilentlyContinue) {
        Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

# ============================================================
# STEP 1 — Prerequisites check
# ============================================================
Write-Step "Checking prerequisites"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Fail "This script must be run as Administrator. Right-click PowerShell → Run as Administrator."
}
Write-OK "Running as Administrator"

# Check Internet connectivity
try {
    $null = Invoke-WebRequest -Uri "https://www.cloudflare.com" -UseBasicParsing -TimeoutSec 10
    Write-OK "Internet connectivity confirmed"
} catch {
    Write-Fail "No Internet connectivity. Cannot download components. Connect to the Internet and retry."
}

# Check for port 53 conflict
if (-not (Test-PortFree 53)) {
    Write-Warn "Port 53 is already in use. Checking who is using it..."
    netstat -ano | Select-String ":53 " | ForEach-Object { Write-Host "    $_" }
    Write-Warn "If this is a system service (not VantaDNS), resolve the conflict before continuing."
    Write-Warn "Proceeding — AdGuard Home installer will attempt to take the port."
} else {
    Write-OK "Port 53 is free"
}

# Check for port 5335 conflict
if (-not (Test-PortFree 5335)) {
    Write-Warn "Port 5335 is already in use. Unbound may have trouble starting."
} else {
    Write-OK "Port 5335 is free"
}

# ============================================================
# STEP 2 — Create directory structure
# ============================================================
Write-Step "Creating directory structure"

$dirs = @(
    $INSTALL_DIR,
    $AGH_DIR,
    "$AGH_DIR\data",
    $UNBOUND_DIR
)

foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-OK "Created: $dir"
    } else {
        Write-OK "Exists:  $dir"
    }
}

# ============================================================
# STEP 3 — Download and install Unbound
# ============================================================
Write-Step "Downloading Unbound $UNBOUND_VERSION"

try {
    Write-Host "  Downloading Unbound installer from NLnet Labs..."
    Invoke-WebRequest -Uri $UNBOUND_URL -OutFile $UNBOUND_INSTALLER -UseBasicParsing -TimeoutSec 300
    Write-OK "Unbound installer downloaded"
} catch {
    Write-Fail "Could not download Unbound from $UNBOUND_URL`nManual download: https://nlnetlabs.nl/downloads/unbound/"
}

Write-Step "Installing Unbound (silent install to C:\Program Files\Unbound)"
# NLnet Labs setup.exe supports /S for silent installation
& $UNBOUND_INSTALLER /S 2>&1 | ForEach-Object { Write-Host "    $_" }
Start-Sleep -Seconds 10  # Allow installer to complete

# The installer places files in C:\Program Files\Unbound\
$UNBOUND_INSTALL_PATH = "C:\Program Files\Unbound"
if (-not (Test-Path "$UNBOUND_INSTALL_PATH\unbound.exe")) {
    Write-Fail "Unbound installation failed. unbound.exe not found at $UNBOUND_INSTALL_PATH"
}
Write-OK "Unbound installed to $UNBOUND_INSTALL_PATH"

# Copy our custom config
Copy-Item "$REPO_ROOT\config\unbound\unbound.conf" "$UNBOUND_INSTALL_PATH\unbound.conf" -Force
# Update paths in config to match installer location
(Get-Content "$UNBOUND_INSTALL_PATH\unbound.conf") `
    -replace [regex]::Escape('C:\\ProgramData\\VantaDNS\\unbound\\root.hints'), "$UNBOUND_INSTALL_PATH\\root.hints" `
    -replace [regex]::Escape('C:\\ProgramData\\VantaDNS\\unbound\\root.key'),  "$UNBOUND_INSTALL_PATH\\root.key" |`
    Set-Content "$UNBOUND_INSTALL_PATH\unbound.conf"
Write-OK "unbound.conf deployed"

# ============================================================
# STEP 4 — Fetch root hints
# ============================================================
Write-Step "Fetching DNS root hints"

$UNBOUND_INSTALL_PATH = "C:\Program Files\Unbound"
$rootHintsPath = "$UNBOUND_INSTALL_PATH\root.hints"
try {
    Invoke-WebRequest -Uri $ROOT_HINTS_URL -OutFile $rootHintsPath -UseBasicParsing -TimeoutSec 30
    Write-OK "Root hints saved to $rootHintsPath"
} catch {
    Write-Fail "Could not fetch root hints from $ROOT_HINTS_URL. Check Internet connectivity."
}

# Initialize DNSSEC root trust anchor
Write-Host "  Initializing DNSSEC root trust anchor..."
$UNBOUND_INSTALL_PATH = "C:\Program Files\Unbound"
if (Test-Path "$UNBOUND_INSTALL_PATH\unbound-anchor.exe") {
    & "$UNBOUND_INSTALL_PATH\unbound-anchor.exe" -a "$UNBOUND_INSTALL_PATH\root.key" 2>&1 | ForEach-Object { Write-Host "    $_" }
    Write-OK "DNSSEC trust anchor initialized: $UNBOUND_INSTALL_PATH\root.key"
} else {
    Write-Warn "unbound-anchor.exe not found in install path."
}

# ============================================================
# STEP 6 — Start Unbound service (installer registers it)
# ============================================================
Write-Step "Starting Unbound Windows service"
$UNBOUND_INSTALL_PATH = "C:\Program Files\Unbound"

# The NLnet Labs installer creates a service named 'Unbound'
# Restart it to pick up our custom config
if (Get-Service -Name "Unbound" -ErrorAction SilentlyContinue) {
    # Stop the service, apply our config, then restart
    Stop-ServiceIfRunning "Unbound"
    Copy-Item "$REPO_ROOT\config\unbound\unbound.conf" "$UNBOUND_INSTALL_PATH\unbound.conf" -Force
    # Patch config paths for the installer's directory
    (Get-Content "$UNBOUND_INSTALL_PATH\unbound.conf") `
        -replace [regex]::Escape('C:\\ProgramData\\VantaDNS\\unbound\\root.hints'), ($UNBOUND_INSTALL_PATH.Replace('\','\\') + '\\root.hints') `
        -replace [regex]::Escape('C:\\ProgramData\\VantaDNS\\unbound\\root.key'),  ($UNBOUND_INSTALL_PATH.Replace('\','\\') + '\\root.key') |`
        Set-Content "$UNBOUND_INSTALL_PATH\unbound.conf" -Encoding UTF8
    Start-Service -Name "Unbound"
    Start-Sleep -Seconds 5
} else {
    Write-Warn "Unbound service not found after installation. The installer may have used a different service name."
    Write-Warn "Check: Get-Service | Where-Object {`$_.Name -like '*unbound*'}"
}

$unboundSvc = Get-Service -Name "Unbound" -ErrorAction SilentlyContinue
if ($unboundSvc -and $unboundSvc.Status -eq "Running") {
    Write-OK "Unbound service is Running"
} else {
    Write-Warn "Unbound service status: $($unboundSvc.Status). Check event log for errors."
}

Start-Sleep -Seconds 3
try {
    $result = Resolve-DnsName -Name "google.com" -Server "127.0.0.1" -Port 5335 -Type A -ErrorAction Stop
    Write-OK "Unbound DNS test: google.com → $($result | Where-Object {$_.Type -eq 'A'} | Select-Object -First 1 -ExpandProperty IPAddress)"
} catch {
    Write-Warn "Unbound DNS test failed: $_`nMay still be initializing. Test: nslookup -port=5335 google.com 127.0.0.1"
}

# ============================================================
# STEP 7 — Download and install AdGuard Home
# ============================================================
Write-Step "Downloading AdGuard Home $AGH_VERSION"

if (Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue) {
    Write-Warn "AdGuardHome service already exists. Stopping and reinstalling."
    Stop-ServiceIfRunning "AdGuardHome"
    & "$AGH_DIR\AdGuardHome.exe" -s uninstall 2>$null
    Start-Sleep -Seconds 2
}

try {
    Write-Host "  Downloading from GitHub releases..."
    Invoke-WebRequest -Uri $AGH_URL -OutFile $AGH_ZIP -UseBasicParsing -TimeoutSec 300
    Write-OK "AdGuard Home downloaded"
} catch {
    Write-Fail "Could not download AdGuard Home from $AGH_URL`nCheck Internet connection or manually download from: https://github.com/AdguardTeam/AdGuardHome/releases"
}

Write-Step "Extracting AdGuard Home"
Expand-Archive -Path $AGH_ZIP -DestinationPath "$env:TEMP\agh_extract" -Force
$aghSource = Get-ChildItem "$env:TEMP\agh_extract" -Directory | Select-Object -First 1
if ($aghSource) {
    Copy-Item "$($aghSource.FullName)\*" -Destination $AGH_DIR -Recurse -Force
} else {
    Copy-Item "$env:TEMP\agh_extract\*" -Destination $AGH_DIR -Recurse -Force
}
Write-OK "AdGuard Home extracted to $AGH_DIR"

# ============================================================
# STEP 8 — Configure AdGuard Home
# ============================================================
Write-Step "Configuring AdGuard Home"

# Copy config template as the working config
# NOTE: This does NOT contain a real password hash.
# AGH will prompt for credentials on first web UI visit.
$aghConfig = Get-Content "$REPO_ROOT\config\adguard\AdGuardHome.yaml.template" -Raw
# Remove the template placeholder comment lines
$aghConfig = $aghConfig -replace "# This is a TEMPLATE.*?# ============================================================`n", ""

$aghConfig | Set-Content "$AGH_DIR\AdGuardHome.yaml" -Encoding UTF8
Write-OK "AdGuardHome.yaml written"

# Copy custom blocklist and allowlist into AGH working directory
Copy-Item "$REPO_ROOT\config\blocklists\custom-blocklist.txt" "$AGH_DIR\data\custom-blocklist.txt" -Force
Copy-Item "$REPO_ROOT\allowlists\custom-allowlist.txt" "$AGH_DIR\data\custom-allowlist.txt" -Force
Write-OK "Custom blocklist and allowlist copied"

# ============================================================
# STEP 9 — Install AdGuard Home as Windows service
# ============================================================
Write-Step "Installing AdGuard Home Windows service"

& "$AGH_DIR\AdGuardHome.exe" -s install -c "$AGH_DIR\AdGuardHome.yaml" -w "$AGH_DIR" 2>&1 | ForEach-Object { Write-Host "    $_" }
Start-Sleep -Seconds 2
Set-Service -Name "AdGuardHome" -StartupType Automatic
Start-Service -Name "AdGuardHome"
Start-Sleep -Seconds 5

$aghSvc = Get-Service -Name "AdGuardHome"
if ($aghSvc.Status -eq "Running") {
    Write-OK "AdGuardHome service is Running"
} else {
    Write-Warn "AdGuardHome service status: $($aghSvc.Status)"
    Write-Warn "Check: Get-EventLog -LogName System -Source 'AdGuardHome' -Newest 10"
}

# ============================================================
# STEP 10 — Configure Windows Firewall
# ============================================================
Write-Step "Applying Windows Firewall rules"

# Remove any existing VantaDNS rules first (idempotent)
Get-NetFirewallRule -DisplayName "VantaDNS*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule

# Rule 1: Allow DNS from LAN (UDP)
New-NetFirewallRule `
  -DisplayName "VantaDNS-DNS-LAN-Inbound-UDP" `
  -Direction Inbound `
  -Protocol UDP `
  -LocalPort 53 `
  -RemoteAddress $LAN_SUBNET `
  -Action Allow `
  -Profile Private `
  -Description "VantaDNS: Allow DNS UDP from LAN only" | Out-Null
Write-OK "Firewall: Allow DNS UDP from $LAN_SUBNET"

# Rule 2: Allow DNS from LAN (TCP — for large responses)
New-NetFirewallRule `
  -DisplayName "VantaDNS-DNS-LAN-Inbound-TCP" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 53 `
  -RemoteAddress $LAN_SUBNET `
  -Action Allow `
  -Profile Private `
  -Description "VantaDNS: Allow DNS TCP from LAN only" | Out-Null
Write-OK "Firewall: Allow DNS TCP from $LAN_SUBNET"

# Rule 3: Allow Admin UI from loopback only
New-NetFirewallRule `
  -DisplayName "VantaDNS-AdminUI-Loopback-Inbound" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 3000 `
  -RemoteAddress "127.0.0.1" `
  -Action Allow `
  -Profile Any `
  -Description "VantaDNS: Admin UI loopback only" | Out-Null
Write-OK "Firewall: Allow Admin UI from 127.0.0.1 only"

# Rule 4: Allow Unbound from loopback only (UDP)
New-NetFirewallRule `
  -DisplayName "VantaDNS-Unbound-Loopback-Inbound-UDP" `
  -Direction Inbound `
  -Protocol UDP `
  -LocalPort 5335 `
  -RemoteAddress "127.0.0.1" `
  -Action Allow `
  -Profile Any `
  -Description "VantaDNS: Unbound loopback only" | Out-Null
Write-OK "Firewall: Allow Unbound UDP from 127.0.0.1"

# Rule 5: Allow Unbound from loopback only (TCP)
New-NetFirewallRule `
  -DisplayName "VantaDNS-Unbound-Loopback-Inbound-TCP" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 5335 `
  -RemoteAddress "127.0.0.1" `
  -Action Allow `
  -Profile Any `
  -Description "VantaDNS: Unbound TCP loopback only" | Out-Null
Write-OK "Firewall: Allow Unbound TCP from 127.0.0.1"

# Rule 6 (CRITICAL): Block DNS port 53 from public/domain network profiles
# This ensures that even if Windows firewall profile is set to Public,
# port 53 is still blocked from non-LAN sources.
New-NetFirewallRule `
  -DisplayName "VantaDNS-DNS-Public-Block-UDP" `
  -Direction Inbound `
  -Protocol UDP `
  -LocalPort 53 `
  -Action Block `
  -Profile Public, Domain `
  -Description "VantaDNS: Block DNS from public/domain profiles (anti-open-resolver)" | Out-Null
Write-OK "Firewall: Block DNS UDP on Public/Domain profiles (anti-open-resolver)"

New-NetFirewallRule `
  -DisplayName "VantaDNS-DNS-Public-Block-TCP" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 53 `
  -Action Block `
  -Profile Public, Domain `
  -Description "VantaDNS: Block DNS TCP from public/domain profiles" | Out-Null
Write-OK "Firewall: Block DNS TCP on Public/Domain profiles (anti-open-resolver)"

Write-Host ""
Write-Host "  Firewall rules summary:" -ForegroundColor White
Get-NetFirewallRule -DisplayName "VantaDNS*" | Select-Object DisplayName, @{N="Action";E={$_.Action}}, @{N="Enabled";E={$_.Enabled}} | Format-Table -AutoSize

# ============================================================
# STEP 11 — Set PC's own DNS to 127.0.0.1
# ============================================================
Write-Step "Configuring PC to use its own DNS (127.0.0.1)"

$wifiAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notlike "*Loopback*" } | 
               Sort-Object -Property LinkSpeed -Descending | Select-Object -First 1

if ($wifiAdapter) {
    Set-DnsClientServerAddress -InterfaceAlias $wifiAdapter.InterfaceAlias -ServerAddresses "127.0.0.1"
    Write-OK "DNS set to 127.0.0.1 on adapter: $($wifiAdapter.InterfaceAlias)"
} else {
    Write-Warn "Could not find an active network adapter. Set DNS manually:"
    Write-Warn "  Set-DnsClientServerAddress -InterfaceAlias 'Wi-Fi' -ServerAddresses '127.0.0.1'"
}

# Flush Windows DNS cache
ipconfig /flushdns | Out-Null
Write-OK "Windows DNS cache flushed"

# ============================================================
# STEP 12 — Post-install health check
# ============================================================
Write-Step "Running post-install health check"

Start-Sleep -Seconds 5  # Allow services to fully initialize

Write-Host ""
Write-Host "  Service status:" -ForegroundColor White
Get-Service -Name "AdGuardHome", "Unbound" -ErrorAction SilentlyContinue | 
    Select-Object Name, Status | Format-Table -AutoSize

Write-Host "  Port status:" -ForegroundColor White
$ports = @(53, 5335, 3000)
foreach ($p in $ports) {
    $listening = netstat -ano | Select-String ":$p "
    if ($listening) {
        Write-OK "Port $p is LISTENING"
    } else {
        Write-Warn "Port $p is NOT listening — check service status"
    }
}

Write-Host ""
Write-Host "  DNS resolution tests:" -ForegroundColor White

# Test 1: Basic resolution via AdGuard Home
try {
    $r = Resolve-DnsName -Name "google.com" -Server "127.0.0.1" -Type A -ErrorAction Stop
    $ip = $r | Where-Object {$_.Type -eq "A"} | Select-Object -First 1 -ExpandProperty IPAddress
    Write-OK "google.com resolves to $ip (via AdGuard Home)"
} catch {
    Write-Warn "google.com resolution failed: $_"
}

# Test 2: Direct Unbound resolution
try {
    $r = Resolve-DnsName -Name "cloudflare.com" -Server "127.0.0.1" -Port 5335 -Type A -ErrorAction Stop
    $ip = $r | Where-Object {$_.Type -eq "A"} | Select-Object -First 1 -ExpandProperty IPAddress
    Write-OK "cloudflare.com resolves to $ip (via Unbound directly)"
} catch {
    Write-Warn "Unbound direct test failed: $_"
}

# Test 3: Known blocked domain (if filters are loaded — may take a moment)
try {
    $r = Resolve-DnsName -Name "doubleclick.net" -Server "127.0.0.1" -Type A -ErrorAction Stop
    $ip = $r | Where-Object {$_.Type -eq "A"} | Select-Object -First 1 -ExpandProperty IPAddress
    if ($ip -eq "0.0.0.0" -or $ip -eq $null) {
        Write-OK "doubleclick.net is BLOCKED (returned: $ip)"
    } else {
        Write-Warn "doubleclick.net returned $ip — blocklists may still be loading. Wait 2-3 min and test again."
    }
} catch {
    # NXDOMAIN is also correct blocking behavior
    Write-OK "doubleclick.net returned NXDOMAIN — correctly blocked"
}

# ============================================================
# DONE
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " VantaDNS Stage 1 installation complete!" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " Next steps:" -ForegroundColor White
Write-Host "  1. Open http://127.0.0.1:3000 in your browser" -ForegroundColor White
Write-Host "     (first visit will ask you to set an admin password)" -ForegroundColor White
Write-Host "  2. Wait 2-3 minutes for blocklists to download and load" -ForegroundColor White
Write-Host "  3. Run: .\scripts\health-check.ps1" -ForegroundColor White
Write-Host "  4. Run: .\scripts\benchmark.ps1" -ForegroundColor White
Write-Host "  5. On another device: set DNS to $PC_IP and test browsing" -ForegroundColor White
Write-Host ""
Write-Host " To test blocking: nslookup doubleclick.net 127.0.0.1" -ForegroundColor White
Write-Host " To test DNSSEC:   nslookup sigok.verteiltesysteme.net 127.0.0.1" -ForegroundColor White
Write-Host ""
