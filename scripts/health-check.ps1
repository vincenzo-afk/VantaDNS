# ============================================================
# VantaDNS — Health Check Script
# scripts/health-check.ps1
# ============================================================

Param(
    [switch]$ForceCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ============================================================
# CONFIGURATION
# ============================================================
$AGH_ADMIN_URL    = 'http://127.0.0.1:3000'
$UNBOUND_PORT     = 5335
$DNS_PORT         = 53
$GATEWAY_IP       = '10.76.181.1'          # Home router
$INTERNET_CHECK   = '9.9.9.9'              # Quad9, used as reachability probe
$TEST_DOMAIN      = 'one.one.one.one'       # Well-known, always resolves
$BLOCKED_DOMAIN   = 'doubleclick.net'       # Should be blocked

# Nightly Sleeping Window Settings (11:00 PM to 08:00 AM)
$SLEEP_START_HOUR = 23
$SLEEP_END_HOUR   = 8

# ============================================================
# HELPERS
# ============================================================
$script:issues = @()
$script:warnings = @()

function Write-Header {
    Clear-Host
    Write-Host ''
    Write-Host '  VantaDNS - Health Check' -ForegroundColor Cyan
    Write-Host '  Your DNS. Your rules. Your privacy.' -ForegroundColor DarkCyan
    Write-Host '  -------------------------------------------------' -ForegroundColor DarkGray
    Write-Host "  Timestamp: [$([System.DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))]" -ForegroundColor DarkGray
    Write-Host ''
}

function Test-NightlyWindow {
    $currentHour = [int](Get-Date -Format 'HH')
    return ($currentHour -ge $SLEEP_START_HOUR -or $currentHour -lt $SLEEP_END_HOUR)
}

function Check-Item {
    param([string]$label, [bool]$ok, [string]$detail = '', [bool]$critical = $true)
    if ($ok) {
        Write-Host "  [OK]  $label" -ForegroundColor Green -NoNewline
        if ($detail) { Write-Host "  ->  $detail" -ForegroundColor DarkGreen } else { Write-Host '' }
    } else {
        if ($critical) {
            Write-Host "  [FAIL] $label" -ForegroundColor Red -NoNewline
            $script:issues += $label
        } else {
            Write-Host "  [WARN] $label" -ForegroundColor Yellow -NoNewline
            $script:warnings += $label
        }
        if ($detail) { Write-Host "  ->  $detail" -ForegroundColor DarkYellow } else { Write-Host '' }
    }
    return $ok
}

function Test-ComponentRunning { param([string]$name)
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc -ne $null -and $svc.Status -eq 'Running') { return $true }
    $proc = Get-Process -Name $name -ErrorAction SilentlyContinue
    return ($proc -ne $null -and @($proc).Count -gt 0)
}

function Test-PortListening { param([int]$port)
    $conn = netstat -ano 2>$null | Select-String ":$port " | Select-String 'LISTENING'
    return ($conn -ne $null -and @($conn).Count -gt 0)
}

function Test-PingReachable { param([string]$ip, [int]$timeoutMs = 1000)
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $result = $ping.Send($ip, $timeoutMs)
        return ($result.Status -eq 'Success')
    } catch { return $false }
}

function Test-DnsResolves { param([string]$domain, [string]$server = '127.0.0.1')
    try {
        $r = Resolve-DnsName -Name $domain -Server $server -Type A -ErrorAction Stop -DnsOnly
        return ($r -ne $null -and @($r).Count -gt 0)
    } catch { return $false }
}

function Test-UnboundHost { param([string]$domain)
    try {
        $scoopUnbound = "$env:USERPROFILE\scoop\shims\unbound-host.exe"
        $confPath = "$env:USERPROFILE\scoop\apps\unbound\current\service.conf"
        if (Test-Path $scoopUnbound) {
            $out = & $scoopUnbound -C $confPath $domain 2>&1
            return ($out -like '*has address*')
        }
        return $false
    } catch { return $false }
}

function Get-DnsLatencyMs { param([string]$domain, [string]$server = '127.0.0.1')
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Resolve-DnsName -Name $domain -Server $server -Type A -ErrorAction Stop -DnsOnly | Out-Null
        $sw.Stop()
        return $sw.ElapsedMilliseconds
    } catch { return -1 }
}

function Test-DnsBlocked { param([string]$domain)
    try {
        $r = Resolve-DnsName -Name $domain -Server '127.0.0.1' -Type A -ErrorAction Stop -DnsOnly
        $ip = $r | Where-Object {$_.Type -eq 'A'} | Select-Object -First 1 -ExpandProperty IPAddress
        return ($ip -eq '0.0.0.0' -or $ip -eq $null)
    } catch {
        if ($_.Exception.Message -like '*DNS name does not exist*' -or 
            $_.Exception.Message -like '*NXDOMAIN*' -or
            $_.Exception.Message -like '*No such host*') {
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

# Check Nightly Sleeping Window
if (Test-NightlyWindow -and -not $ForceCheck) {
    Write-Host '  SYSTEM STATE: [ STANDBY / NIGHTLY WINDOW ]' -ForegroundColor DarkYellow
    Write-Host '  Scheduled low-power window (11:00 PM - 08:00 AM).' -ForegroundColor DarkYellow
    Write-Host '  Health checks and active probes are paused to conserve power and reduce logging.' -ForegroundColor DarkYellow
    Write-Host ''
    Write-Host '  Tip: Run .\scripts\health-check.ps1 -ForceCheck to override sleep window.' -ForegroundColor Gray
    Write-Host ''
    exit 0
}

Write-Host '  [ Services ]' -ForegroundColor White
$aghRunning     = Check-Item 'AdGuard Home engine' (Test-ComponentRunning 'AdGuardHome')
$unboundRunning = Check-Item 'Unbound resolver engine' (Test-ComponentRunning 'unbound')

Write-Host ''
Write-Host '  [ Ports ]' -ForegroundColor White
$dns53    = Check-Item 'DNS port 53 listening' (Test-PortListening 53)
$unb5335  = Check-Item 'Unbound port 5335 listening' (Test-PortListening 5335)
$aghApi   = Check-Item 'AdGuard Home API (127.0.0.1:3000)' (Test-AghApiReachable) -critical $false

Write-Host ''
Write-Host '  [ Network ]' -ForegroundColor White
$lanOk    = Check-Item "LAN gateway reachable ($GATEWAY_IP)" (Test-PingReachable $GATEWAY_IP) -critical $false
$inetOk   = Check-Item "Internet reachable ($INTERNET_CHECK)" (Test-PingReachable $INTERNET_CHECK) -critical $false

Write-Host ''
Write-Host '  [ DNS Resolution ]' -ForegroundColor White

# Test via Unbound directly
$unboundDns  = Check-Item 'Unbound resolves (port 5335)' (Test-UnboundHost 'cloudflare.com')
# Test via AdGuard Home
$aghDns      = Check-Item 'AdGuard Home resolves (port 53)' (Test-DnsResolves 'google.com' '127.0.0.1')

# Blocking test (only meaningful if AGH is running and filters are loaded)
if ($aghRunning) {
    $blocked = Check-Item 'Blocking works (doubleclick.net)' (Test-DnsBlocked $BLOCKED_DOMAIN) -critical $false
}

Write-Host ''
Write-Host '  [ Latency ]' -ForegroundColor White

if ($aghRunning -and $inetOk) {
    # Warm cache test (query twice, measure second)
    Test-DnsResolves 'example.com' '127.0.0.1' | Out-Null
    $warmMs = Get-DnsLatencyMs 'example.com' '127.0.0.1'
    
    if ($warmMs -ge 0) {
        $latencyColor = if ($warmMs -lt 5) { 'Green' } elseif ($warmMs -lt 20) { 'Yellow' } else { 'Red' }
        Write-Host "  [METRIC] Warm cache latency (example.com): $warmMs ms" -ForegroundColor $latencyColor
    }
}

# ============================================================
# DETERMINE OVERALL STATE
# ============================================================
Write-Host ''
Write-Host '  -------------------------------------------------' -ForegroundColor DarkGray

$state = 'UNKNOWN'
$stateColor = 'White'

if (-not $aghRunning -and -not $unboundRunning) {
    $state = 'STOPPED'
    $stateColor = 'Red'
} elseif ($aghRunning -and -not $unboundRunning) {
    $state = 'DEGRADED'
    $stateColor = 'Yellow'
    Write-Host '  [!] Unbound is not running. Resolution depends on fallback.' -ForegroundColor Yellow
} elseif (-not $aghRunning -and $unboundRunning) {
    $state = 'DEGRADED'
    $stateColor = 'Yellow'
    Write-Host '  [!] AdGuard Home is not running. No DNS filtering active.' -ForegroundColor Yellow
} elseif ($aghRunning -and $unboundRunning) {
    if (-not $inetOk) {
        $state = 'OFFLINE'
        $stateColor = 'Yellow'
        Write-Host '  [*] No Internet - serving from cache only. LAN DNS still active.' -ForegroundColor Yellow
    } elseif ($script:issues.Count -gt 0) {
        $state = 'DEGRADED'
        $stateColor = 'Yellow'
    } else {
        $state = 'ONLINE'
        $stateColor = 'Green'
    }
}

Write-Host ''
Write-Host "  SYSTEM STATE: [ $state ]" -ForegroundColor $stateColor
Write-Host ''

if ($script:issues.Count -gt 0) {
    Write-Host '  Issues:' -ForegroundColor Red
    $script:issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    Write-Host ''
}

if ($script:warnings.Count -gt 0) {
    Write-Host '  Warnings:' -ForegroundColor Yellow
    $script:warnings | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
    Write-Host ''
}

Write-Host '  Admin UI:     http://127.0.0.1:3000' -ForegroundColor DarkGray
Write-Host '  Troubleshoot: docs/troubleshooting.md' -ForegroundColor DarkGray
Write-Host ''
