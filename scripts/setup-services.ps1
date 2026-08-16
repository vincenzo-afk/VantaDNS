#Requires -RunAsAdministrator
# ============================================================
# VantaDNS — Service Setup (run ONCE in elevated PowerShell)
# This script:
#   1. Installs Unbound 1.26.0 silently
#   2. Applies our custom unbound.conf
#   3. Registers AdGuard Home as a Windows service
#   4. Applies all firewall rules
#   5. Sets PC DNS to 127.0.0.1
# ============================================================
param(
    [string]$RepoRoot = "c:\Users\S K\Desktop\VantaDNS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Log  { param([string]$m) Write-Host "  $m" -ForegroundColor Cyan }
function OK   { param([string]$m) Write-Host "  OK  $m" -ForegroundColor Green }
function WARN { param([string]$m) Write-Host "  !!  $m" -ForegroundColor Yellow }
function FAIL { param([string]$m) Write-Host "  XX  $m" -ForegroundColor Red; throw $m }

Write-Host ""
Write-Host "  VantaDNS — Service Setup" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host ""

# ── 1. Install Unbound ─────────────────────────────────────
Log "Installing Unbound 1.26.0..."
$setup = "$env:TEMP\unbound_setup.exe"
if (-not (Test-Path $setup)) {
    Log "Downloading Unbound installer..."
    Invoke-WebRequest "https://nlnetlabs.nl/downloads/unbound/unbound_setup_1.26.0.exe" `
        -OutFile $setup -UseBasicParsing -TimeoutSec 120
}
# NSIS /S = silent, /D sets install dir
& $setup /S | Out-Null
Start-Sleep -Seconds 12   # NSIS needs time to finish

$unboundBin = "C:\Program Files\Unbound\unbound.exe"
if (-not (Test-Path $unboundBin)) { FAIL "Unbound install failed — unbound.exe not found" }
OK "Unbound installed at C:\Program Files\Unbound\"

# ── 2. Configure Unbound ───────────────────────────────────
Log "Deploying unbound.conf..."
$unboundDir = "C:\Program Files\Unbound"

# Copy root hints
Copy-Item "$RepoRoot\downloads\root.hints" "$unboundDir\root.hints" -Force

# Write our config directly (path-correct version)
@"
server:
    interface: 127.0.0.1
    port: 5335
    do-not-query-localhost: no
    access-control: 0.0.0.0/0 refuse
    access-control: 127.0.0.1/32 allow
    do-ip4: yes
    do-ip6: no
    do-udp: yes
    do-tcp: yes
    root-hints: "$unboundDir\root.hints"
    auto-trust-anchor-file: "$unboundDir\root.key"
    val-clean-additional: yes
    qname-minimisation: yes
    qname-minimisation-strict: no
    prefetch: yes
    prefetch-key: yes
    msg-cache-size: 64m
    rrset-cache-size: 128m
    cache-min-ttl: 300
    cache-max-ttl: 86400
    cache-max-negative-ttl: 3600
    hide-version: yes
    hide-identity: yes
    harden-dnssec-stripped: yes
    private-address: 10.0.0.0/8
    private-address: 172.16.0.0/12
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    harden-glue: yes
    harden-algo-downgrade: yes
    harden-short-bufsize: yes
    harden-large-queries: yes
    harden-below-nxdomain: yes
    aggressive-nsec: yes
    num-threads: 1
    outgoing-range: 512
    num-queries-per-thread: 1024
    verbosity: 0
    logfile: ""
    statistics-interval: 0
    statistics-cumulative: no
    extended-statistics: no
remote-control:
    control-enable: no
"@ | Set-Content "$unboundDir\service.conf" -Encoding UTF8

OK "unbound.conf written"

# Initialize DNSSEC trust anchor
Log "Initializing DNSSEC trust anchor..."
if (Test-Path "$unboundDir\unbound-anchor.exe") {
    & "$unboundDir\unbound-anchor.exe" -a "$unboundDir\root.key" 2>&1 | Out-Null
    OK "DNSSEC trust anchor ready"
}

# ── 3. Restart Unbound with our config ─────────────────────
Log "Restarting Unbound service..."
Stop-Service "Unbound" -Force -ErrorAction SilentlyContinue
Start-Sleep 2
# Update the service to use our config file
& sc.exe config Unbound binPath= "`"$unboundDir\unbound.exe`" -c `"$unboundDir\service.conf`" -s" | Out-Null
Set-Service "Unbound" -StartupType Automatic
Start-Service "Unbound"
Start-Sleep 5

$svc = Get-Service "Unbound" -ErrorAction SilentlyContinue
if ($svc.Status -eq "Running") { OK "Unbound service Running" }
else { WARN "Unbound service status: $($svc.Status)" }

# Quick DNS test
try {
    $r = Resolve-DnsName "cloudflare.com" -Server "127.0.0.1" -Port 5335 -Type A -ErrorAction Stop -DnsOnly
    $ip = ($r | Where-Object {$_.Type -eq "A"} | Select-Object -First 1).IPAddress
    OK "Unbound DNS test: cloudflare.com -> $ip"
} catch { WARN "Unbound DNS test failed: $_ (may still be initializing)" }

# ── 4. Register AdGuard Home as service ───────────────────
Log "Installing AdGuard Home service..."
$aghDir = "C:\ProgramData\VantaDNS\adguardhome"
$aghExe = "$aghDir\AdGuardHome.exe"

# Stop+uninstall if already registered
$aghSvc = Get-Service "AdGuardHome" -ErrorAction SilentlyContinue
if ($aghSvc) {
    Stop-Service "AdGuardHome" -Force -ErrorAction SilentlyContinue
    & $aghExe -s uninstall 2>&1 | Out-Null
    Start-Sleep 2
}

& $aghExe -s install -c "$aghDir\AdGuardHome.yaml" -w "$aghDir" 2>&1 | Out-Null
Set-Service "AdGuardHome" -StartupType Automatic
Start-Service "AdGuardHome"
Start-Sleep 5

$aghSvc2 = Get-Service "AdGuardHome" -ErrorAction SilentlyContinue
if ($aghSvc2.Status -eq "Running") { OK "AdGuardHome service Running" }
else { WARN "AdGuardHome service status: $($aghSvc2.Status)" }

# ── 5. Firewall Rules ──────────────────────────────────────
Log "Applying firewall rules..."
$LAN = "10.76.181.0/24"

# Remove existing VantaDNS rules (idempotent)
Get-NetFirewallRule -DisplayName "VantaDNS*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule

New-NetFirewallRule -DisplayName "VantaDNS-DNS-LAN-UDP"         -Direction Inbound -Protocol UDP -LocalPort 53   -RemoteAddress $LAN         -Action Allow -Profile Private -Description "VantaDNS: LAN DNS UDP"      | Out-Null
New-NetFirewallRule -DisplayName "VantaDNS-DNS-LAN-TCP"         -Direction Inbound -Protocol TCP -LocalPort 53   -RemoteAddress $LAN         -Action Allow -Profile Private -Description "VantaDNS: LAN DNS TCP"      | Out-Null
New-NetFirewallRule -DisplayName "VantaDNS-AdminUI-Loopback"    -Direction Inbound -Protocol TCP -LocalPort 3000 -RemoteAddress "127.0.0.1"  -Action Allow -Profile Any     -Description "VantaDNS: Admin loopback"  | Out-Null
New-NetFirewallRule -DisplayName "VantaDNS-Unbound-Loop-UDP"    -Direction Inbound -Protocol UDP -LocalPort 5335 -RemoteAddress "127.0.0.1"  -Action Allow -Profile Any     -Description "VantaDNS: Unbound UDP"     | Out-Null
New-NetFirewallRule -DisplayName "VantaDNS-Unbound-Loop-TCP"    -Direction Inbound -Protocol TCP -LocalPort 5335 -RemoteAddress "127.0.0.1"  -Action Allow -Profile Any     -Description "VantaDNS: Unbound TCP"     | Out-Null
New-NetFirewallRule -DisplayName "VantaDNS-Block-Public-DNS-UDP" -Direction Inbound -Protocol UDP -LocalPort 53  -Action Block  -Profile Public,Domain  -Description "VantaDNS: Block public DNS UDP" | Out-Null
New-NetFirewallRule -DisplayName "VantaDNS-Block-Public-DNS-TCP" -Direction Inbound -Protocol TCP -LocalPort 53  -Action Block  -Profile Public,Domain  -Description "VantaDNS: Block public DNS TCP" | Out-Null
OK "7 firewall rules applied"

# ── 6. Set PC DNS to 127.0.0.1 ────────────────────────────
Log "Setting PC DNS to 127.0.0.1..."
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.InterfaceDescription -notlike "*Loopback*"} |
           Sort-Object LinkSpeed -Descending | Select-Object -First 1
if ($adapter) {
    Set-DnsClientServerAddress -InterfaceAlias $adapter.InterfaceAlias -ServerAddresses "127.0.0.1"
    ipconfig /flushdns | Out-Null
    OK "DNS set to 127.0.0.1 on $($adapter.InterfaceAlias)"
}

# ── 7. Final health summary ────────────────────────────────
Write-Host ""
Write-Host "  ── Final Status ──────────────────────────────────────" -ForegroundColor DarkGray
Get-Service "AdGuardHome","Unbound" -ErrorAction SilentlyContinue | 
    Select-Object Name,Status | Format-Table -AutoSize
netstat -ano | Select-String "(:53 |:5335|:3000)" | Where-Object {$_ -match "LISTEN"}

Write-Host ""
Write-Host "  DONE. Next steps:" -ForegroundColor Green
Write-Host "    1. Open http://127.0.0.1:3000 and set admin password" -ForegroundColor White
Write-Host "    2. Wait ~3 min for blocklists to download" -ForegroundColor White
Write-Host "    3. Run: .\scripts\health-check.ps1" -ForegroundColor White
Write-Host "    4. Run: .\scripts\test-dns.ps1" -ForegroundColor White
Write-Host ""
