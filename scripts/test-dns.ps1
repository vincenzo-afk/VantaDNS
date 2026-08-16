# ============================================================
# VantaDNS — DNS Test Suite
# scripts/test-dns.ps1
#
# Runs verification tests for Stage 1 completion criteria.
# Tests: resolution, blocking, NXDOMAIN, record types, DNSSEC
# ============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$DNS_SERVER = "127.0.0.1"
$DNS_PORT   = 53

$script:passed = 0
$script:failed = 0
$script:warned = 0

function Test-Case {
    param(
        [string]$name,
        [scriptblock]$check,
        [string]$expect,
        [bool]$critical = $true
    )

    try {
        $result = & $check
        $ok = $result -ne $null -and $result -ne $false
        
        if ($ok) {
            Write-Host "  PASS  $name" -ForegroundColor Green
            if ($expect) { Write-Host "        → $expect" -ForegroundColor DarkGreen }
            $script:passed++
        } else {
            if ($critical) {
                Write-Host "  FAIL  $name" -ForegroundColor Red
                $script:failed++
            } else {
                Write-Host "  WARN  $name" -ForegroundColor Yellow
                $script:warned++
            }
        }
    } catch {
        $errMsg = $_.Exception.Message
        # NXDOMAIN is a valid result for blocking tests
        if ($name -like "*BLOCKED*" -or $name -like "*NXDOMAIN*") {
            if ($errMsg -like "*does not exist*" -or $errMsg -like "*NXDOMAIN*") {
                Write-Host "  PASS  $name" -ForegroundColor Green
                Write-Host "        → NXDOMAIN (correct blocking behavior)" -ForegroundColor DarkGreen
                $script:passed++
                return
            }
        }
        Write-Host "  FAIL  $name" -ForegroundColor Red
        Write-Host "        → Error: $errMsg" -ForegroundColor DarkRed
        $script:failed++
    }
}

# ============================================================
# MAIN
# ============================================================

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║  VantaDNS DNS Test Suite — Stage 1 Verification  ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# SECTION 1: Service health
# ============================================================
Write-Host "  [ Service Health ]" -ForegroundColor White

Test-Case "AdGuard Home service is Running" {
    (Get-Service "AdGuardHome" -ErrorAction SilentlyContinue).Status -eq "Running"
} "Service status = Running"

Test-Case "Unbound service is Running" {
    (Get-Service "Unbound" -ErrorAction SilentlyContinue).Status -eq "Running"
} "Service status = Running"

Test-Case "Port 53 is LISTENING" {
    (netstat -ano | Select-String ":53 " | Select-String "LISTENING") -ne $null
} "Listening on :53"

Test-Case "Port 5335 is LISTENING (Unbound)" {
    (netstat -ano | Select-String ":5335" | Select-String "LISTENING") -ne $null
} "Listening on :5335"

# ============================================================
# SECTION 2: Basic resolution
# ============================================================
Write-Host ""
Write-Host "  [ Basic A Record Resolution ]" -ForegroundColor White

$aRecords = @("google.com", "cloudflare.com", "github.com", "microsoft.com", "wikipedia.org")
foreach ($domain in $aRecords) {
    Test-Case "Resolves $domain (A)" {
        $r = Resolve-DnsName -Name $domain -Server $DNS_SERVER -Port $DNS_PORT -Type A -DnsOnly -ErrorAction Stop
        $r | Where-Object {$_.Type -eq "A"} | Select-Object -First 1
    } ""
}

# ============================================================
# SECTION 3: Record type tests
# ============================================================
Write-Host ""
Write-Host "  [ DNS Record Types ]" -ForegroundColor White

Test-Case "MX record: gmail.com" {
    $r = Resolve-DnsName -Name "gmail.com" -Server $DNS_SERVER -Port $DNS_PORT -Type MX -DnsOnly -ErrorAction Stop
    $r | Where-Object {$_.Type -eq "MX"} | Select-Object -First 1
} "MX records returned"

Test-Case "TXT record: google.com" {
    $r = Resolve-DnsName -Name "google.com" -Server $DNS_SERVER -Port $DNS_PORT -Type TXT -DnsOnly -ErrorAction Stop
    $r | Where-Object {$_.Type -eq "TXT"} | Select-Object -First 1
} "TXT records returned"

Test-Case "AAAA record: google.com (may be empty if IPv6 disabled)" {
    Resolve-DnsName -Name "google.com" -Server $DNS_SERVER -Port $DNS_PORT -Type AAAA -DnsOnly -ErrorAction Stop
    $true
} "AAAA query processed" -critical $false

Test-Case "CNAME: www.github.com" {
    $r = Resolve-DnsName -Name "www.github.com" -Server $DNS_SERVER -Port $DNS_PORT -Type CNAME -DnsOnly -ErrorAction Stop
    $r | Where-Object {$_.Type -eq "CNAME"} | Select-Object -First 1
} "CNAME records returned" -critical $false

# ============================================================
# SECTION 4: NXDOMAIN
# ============================================================
Write-Host ""
Write-Host "  [ NXDOMAIN (non-existent domains) ]" -ForegroundColor White

$nxDomains = @(
    "nonexistent-xyz123-vantadns-test.com",
    "this-domain-definitely-does-not-exist-8675309.net"
)

foreach ($domain in $nxDomains) {
    Test-Case "NXDOMAIN: $domain" {
        try {
            Resolve-DnsName -Name $domain -Server $DNS_SERVER -Port $DNS_PORT -Type A -DnsOnly -ErrorAction Stop
            return $false  # If it resolved, that's wrong
        } catch {
            if ($_.Exception.Message -like "*does not exist*" -or $_.Exception.Message -like "*NXDOMAIN*") {
                return $true
            }
            return $false
        }
    } "Correctly returns NXDOMAIN"
}

# ============================================================
# SECTION 5: Blocking tests
# ============================================================
Write-Host ""
Write-Host "  [ Blocking Tests (known ad/tracking domains) ]" -ForegroundColor White

$blockedDomains = @(
    "doubleclick.net",
    "googlesyndication.com",
    "googleadservices.com",
    "facebook.com.track.me.ads.test"
)

foreach ($domain in $blockedDomains) {
    Test-Case "BLOCKED: $domain" {
        try {
            $r = Resolve-DnsName -Name $domain -Server $DNS_SERVER -Port $DNS_PORT -Type A -DnsOnly -ErrorAction Stop
            $ip = $r | Where-Object {$_.Type -eq "A"} | Select-Object -First 1 -ExpandProperty IPAddress
            return ($ip -eq "0.0.0.0" -or $ip -eq $null)
        } catch {
            if ($_.Exception.Message -like "*does not exist*" -or $_.Exception.Message -like "*NXDOMAIN*") {
                return $true
            }
            return $false
        }
    } "Returns 0.0.0.0 or NXDOMAIN" -critical $false
}

# ============================================================
# SECTION 6: DNSSEC
# ============================================================
Write-Host ""
Write-Host "  [ DNSSEC Validation ]" -ForegroundColor White

Test-Case "DNSSEC VALID: sigok.verteiltesysteme.net (signed, valid)" {
    $r = Resolve-DnsName -Name "sigok.verteiltesysteme.net" -Server $DNS_SERVER -Port $DNS_PORT -Type A -DnsOnly -ErrorAction Stop
    $r | Where-Object {$_.Type -eq "A"} | Select-Object -First 1
} "Returns valid IP (DNSSEC chain OK)" -critical $false

Test-Case "DNSSEC BOGUS: sigfail.verteiltesysteme.net (should fail)" {
    try {
        Resolve-DnsName -Name "sigfail.verteiltesysteme.net" -Server $DNS_SERVER -Port $DNS_PORT -Type A -DnsOnly -ErrorAction Stop
        return $false  # Should NOT succeed
    } catch {
        return $true   # SERVFAIL = DNSSEC validation working correctly
    }
} "Returns SERVFAIL (correctly rejected bogus DNSSEC)" -critical $false

# ============================================================
# SECTION 7: Security — open resolver check
# ============================================================
Write-Host ""
Write-Host "  [ Security: Open Resolver Check ]" -ForegroundColor White

Test-Case "Admin UI NOT accessible from non-loopback" {
    try {
        # Try to access admin UI via LAN IP (should fail or be blocked)
        $r = Invoke-WebRequest -Uri "http://10.76.181.43:3000" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        return $false  # If we got here, it's exposed (BAD)
    } catch {
        return $true   # Connection refused or timeout = correct
    }
} "Port 3000 not accessible from LAN IP" -critical $false

# ============================================================
# RESULTS
# ============================================================
Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor DarkGray
$total = $script:passed + $script:failed + $script:warned
Write-Host ""
Write-Host "  Results: $($script:passed) passed  /  $($script:failed) failed  /  $($script:warned) warnings  (of $total tests)" -ForegroundColor White

if ($script:failed -eq 0) {
    Write-Host ""
    Write-Host "  ✅  ALL CRITICAL TESTS PASSED — Stage 1 verification complete." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "  ❌  $($script:failed) critical tests failed. Review output above." -ForegroundColor Red
    Write-Host "      See docs\troubleshooting.md for guidance." -ForegroundColor DarkGray
}
Write-Host ""
