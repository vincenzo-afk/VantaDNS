# ============================================================
# VantaDNS — Health Check Script
# scripts/health-check.ps1
#
# Checks the health of all VantaDNS components and reports
# the overall system state.
#
# States:
#   ONLINE        - All services healthy, Internet reachable, DNS resolving
#   DEGRADED      - Services running but something is impaired
#   OFFLINE       - No Internet connectivity (DNS cache-only mode)
#   RECONNECTING  - Internet was lost, waiting for recovery
#   ERROR         - A critical service has crashed or failed
#   STARTING      - Services are still starting up
#   STOPPED       - Services are not running
# ============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

# ============================================================
# CONFIGURATION
# ============================================================
$AGH_ADMIN_URL    = "http://127.0.0.1:3000"
$UNBOUND_PORT     = 5335
$DNS_PORT         = 53
$GATEWAY_IP       = "10.76.181.1"          # Home router
$INTERNET_CHECK   = "9.9.9.9"              # Quad9, used as reachability probe
$TEST_DOMAIN      = "one.one.one.one"       # Well-known, always resolves
$BLOCKED_DOMAIN   = "doubleclick.net"       # Should be blocked

# ============================================================
# HELPERS
# ============================================================
$script:issues = @()
$script:warnings = @()

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ██╗   ██╗ █████╗ ███╗   ██╗████████╗ █████╗ " -ForegroundColor Cyan
    Write-Host "  ██║   ██║██╔══██╗████╗  ██║╚══██╔══╝██╔══██╗" -ForegroundColor Cyan
    Write-Host "  ██║   ██║███████║██╔██╗ ██║   ██║   ███████║" -ForegroundColor Cyan
    Write-Host "  ╚██╗ ██╔╝██╔══██║██║╚██╗██║   ██║   ██╔══██║" -ForegroundColor Cyan
    Write-Host "   ╚████╔╝ ██║  ██║██║ ╚████║   ██║   ██║  ██║" -ForegroundColor Cyan
    Write-Host "    ╚═══╝  ╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝" -ForegroundColor Cyan
    Write-Host "  DNS       ·    Your DNS. Your rules. Your privacy." -ForegroundColor DarkCyan
    Write-Host "  ─────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  Health Check  [$([System.DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))]" -ForegroundColor DarkGray
    Write-Host ""
}

function Check-Item {
    param([string]$label, [bool]$ok, [string]$detail = "", [bool]$critical = $true)
    if ($ok) {
        Write-Host "  ✅  $label" -ForegroundColor Green -NoNewline
        if ($detail) { Write-Host "  →  $detail" -ForegroundColor DarkGreen } else { Write-Host "" }
    } else {
        if ($critical) {
            Write-Host "  ❌  $label" -ForegroundColor Red -NoNewline
            $script:issues += $label
        } else {
            Write-Host "  ⚠️   $label" -ForegroundColor Yellow -NoNewline
            $script:warnings += $label
        }
        if ($detail) { Write-Host "  →  $detail" -ForegroundColor DarkYellow } else { Write-Host "" }
    }
    return $ok
}

function Test-ServiceRunning { param([string]$name)
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    return ($svc -ne $null -and $svc.Status -eq "Running")
}

function Test-PortListening { param([int]$port)
    $conn = netstat -ano 2>$null | Select-String ":$port " | Select-String "LISTENING"
    return ($conn -ne $null -and $conn.Count -gt 0)
}

function Test-PingReachable { param([string]$ip, [int]$timeoutMs = 1000)
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $result = $ping.Send($ip, $timeoutMs)
        return ($result.Status -eq "Success")
    } catch { return $false }
}

function Test-DnsResolves { param([string]$domain, [string]$server = "127.0.0.1", [int]$port = 53)
    try {
        $r = Resolve-DnsName -Name $domain -Server $server -Port $port -Type A -ErrorAction Stop -DnsOnly
        return ($r -ne $null -and $r.Count -gt 0)
    } catch { return $false }
}

function Get-DnsLatencyMs { param([string]$domain, [string]$server = "127.0.0.1", [int]$port = 53)
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Resolve-DnsName -Name $domain -Server $server -Port $port -Type A -ErrorAction Stop -DnsOnly | Out-Null
        $sw.Stop()
        return $sw.ElapsedMilliseconds
    } catch { return -1 }
}

function Test-DnsBlocked { param([string]$domain)
    try {
        # Blocked domains should return NXDOMAIN or 0.0.0.0
        $r = Resolve-DnsName -Name $domain -Server "127.0.0.1" -Type A -ErrorAction Stop -DnsOnly
        $ip = $r | Where-Object {$_.Type -eq "A"} | Select-Object -First 1 -ExpandProperty IPAddress
        return ($ip -eq "0.0.0.0" -or $ip -eq $null)
    } catch {
        # NXDOMAIN exception = blocked correctly
        if ($_.Exception.Message -like "*DNS name does not exist*" -or 
            $_.Exception.Message -like "*NXDOMAIN*" -or
            $_.Exception.Message -like "*No such host*") {
            return $true
        }
        return $false
    }
}

function Test-AghApiReachable {
    try {
        $resp = Invoke-WebRequest -Uri "$AGH_ADMIN_URL/control/status" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        return ($resp.StatusCode -eq 200)
    } catch { return $false }
}

# ============================================================
# MAIN CHECKS
# ============================================================
Write-Header

Write-Host "  [ Services ]" -ForegroundColor White
$aghRunning     = Check-Item "AdGuard Home service" (Test-ServiceRunning "AdGuardHome")
$unboundRunning = Check-Item "Unbound service" (Test-ServiceRunning "Unbound")

Write-Host ""
Write-Host "  [ Ports ]" -ForegroundColor White
$dns53    = Check-Item "DNS port 53 listening" (Test-PortListening 53)
$unb5335  = Check-Item "Unbound port 5335 listening" (Test-PortListening 5335)
$aghApi   = Check-Item "AdGuard Home API (127.0.0.1:3000)" (Test-AghApiReachable) -critical $false

Write-Host ""
Write-Host "  [ Network ]" -ForegroundColor White
$lanOk    = Check-Item "LAN gateway reachable ($GATEWAY_IP)" (Test-PingReachable $GATEWAY_IP)
$inetOk   = Check-Item "Internet reachable ($INTERNET_CHECK)" (Test-PingReachable $INTERNET_CHECK) -critical $false

Write-Host ""
Write-Host "  [ DNS Resolution ]" -ForegroundColor White

# Test via Unbound directly
$unboundDns  = Check-Item "Unbound resolves (port 5335)" (Test-DnsResolves "cloudflare.com" "127.0.0.1" 5335)
# Test via AdGuard Home
$aghDns      = Check-Item "AdGuard Home resolves (port 53)" (Test-DnsResolves "google.com" "127.0.0.1" 53)

# Blocking test (only meaningful if AGH is running and filters are loaded)
if ($aghRunning) {
    $blocked = Check-Item "Blocking works (doubleclick.net)" (Test-DnsBlocked $BLOCKED_DOMAIN) -critical $false
}

Write-Host ""
Write-Host "  [ Latency ]" -ForegroundColor White

if ($aghRunning -and $inetOk) {
    # Warm cache test (query twice, measure second)
    Test-DnsResolves "example.com" "127.0.0.1" 53 | Out-Null  # warm up
    $warmMs = Get-DnsLatencyMs "example.com" "127.0.0.1" 53
    
    $coldDomain = "test-cold-$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).com"
    $coldMs = Get-DnsLatencyMs $coldDomain "127.0.0.1" 53
    
    if ($warmMs -ge 0) {
        $latencyColor = if ($warmMs -lt 5) { "Green" } elseif ($warmMs -lt 20) { "Yellow" } else { "Red" }
        Write-Host "  📊  Warm cache latency (example.com):  " -NoNewline
        Write-Host "$warmMs ms" -ForegroundColor $latencyColor
    }
    if ($coldMs -ge 0) {
        Write-Host "  📊  Cold cache attempt (random domain): $coldMs ms (NXDOMAIN expected)" -ForegroundColor DarkGray
    }
}

# ============================================================
# DETERMINE OVERALL STATE
# ============================================================
Write-Host ""
Write-Host "  ─────────────────────────────────────────────────" -ForegroundColor DarkGray

$state = "UNKNOWN"

if (-not $aghRunning -and -not $unboundRunning) {
    $state = "STOPPED"
    $stateColor = "Red"
} elseif ($aghRunning -and -not $unboundRunning) {
    $state = "DEGRADED"
    $stateColor = "Yellow"
    Write-Host "  ⚠️  Unbound is not running. Resolution depends on fallback." -ForegroundColor Yellow
} elseif (-not $aghRunning -and $unboundRunning) {
    $state = "DEGRADED"
    $stateColor = "Yellow"
    Write-Host "  ⚠️  AdGuard Home is not running. No DNS filtering active." -ForegroundColor Yellow
} elseif ($aghRunning -and $unboundRunning) {
    if (-not $inetOk -and $lanOk) {
        $state = "OFFLINE"
        $stateColor = "Yellow"
        Write-Host "  ℹ️  No Internet — serving from cache only. LAN DNS still active." -ForegroundColor Yellow
    } elseif (-not $lanOk) {
        $state = "ERROR"
        $stateColor = "Red"
        Write-Host "  ❌  No LAN connectivity." -ForegroundColor Red
    } elseif ($script:issues.Count -gt 0) {
        $state = "DEGRADED"
        $stateColor = "Yellow"
    } else {
        $state = "ONLINE"
        $stateColor = "Green"
    }
}

Write-Host ""
Write-Host "  SYSTEM STATE:" -ForegroundColor White -NoNewline
Write-Host "  [ $state ]" -ForegroundColor $stateColor
Write-Host ""

if ($script:issues.Count -gt 0) {
    Write-Host "  Issues:" -ForegroundColor Red
    $script:issues | ForEach-Object { Write-Host "    · $_" -ForegroundColor Red }
    Write-Host ""
}

if ($script:warnings.Count -gt 0) {
    Write-Host "  Warnings:" -ForegroundColor Yellow
    $script:warnings | ForEach-Object { Write-Host "    · $_" -ForegroundColor Yellow }
    Write-Host ""
}

Write-Host "  Admin UI:     http://127.0.0.1:3000" -ForegroundColor DarkGray
Write-Host "  Troubleshoot: docs\troubleshooting.md" -ForegroundColor DarkGray
Write-Host ""
