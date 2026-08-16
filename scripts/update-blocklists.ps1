# ============================================================
# VantaDNS — Blocklist Update Script
# scripts/update-blocklists.ps1
#
# Triggers AdGuard Home to update all configured blocklists.
# Safe to run at any time when Internet is available.
# AGH updates blocklists automatically on a schedule;
# this script forces an immediate update.
# ============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$AGH_API = "http://127.0.0.1:3000"

Write-Host ""
Write-Host "  VantaDNS — Blocklist Update" -ForegroundColor Cyan
Write-Host "  $([System.DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor DarkGray
Write-Host ""

# Check AGH is running
$aghSvc = Get-Service -Name "AdGuardHome" -ErrorAction SilentlyContinue
if ($aghSvc.Status -ne "Running") {
    Write-Host "  ❌ AdGuardHome service is not running. Start it first." -ForegroundColor Red
    exit 1
}

# Check Internet connectivity
try {
    $null = Invoke-WebRequest -Uri "https://9.9.9.9" -UseBasicParsing -TimeoutSec 5
} catch {
    if ($_.Exception.Message -like "*SSL*" -or $_.Exception.Message -like "*certificate*") {
        # That's fine — just checking reachability
    } else {
        Write-Host "  ⚠️  No Internet connectivity detected." -ForegroundColor Yellow
        Write-Host "      Blocklist update requires Internet access." -ForegroundColor DarkGray
        Write-Host "      The current blocklists will continue to be used." -ForegroundColor DarkGray
        exit 0
    }
}
Write-Host "  ✅ Internet connectivity confirmed" -ForegroundColor Green

# Trigger update via AGH API (requires credentials if set)
# Note: If the AGH admin password is set, this API call requires basic auth.
# For now, we use the unauthenticated endpoint if available.
try {
    Write-Host "  Triggering blocklist update..." -ForegroundColor White
    $resp = Invoke-WebRequest `
        -Uri "$AGH_API/control/filtering/refresh" `
        -Method POST `
        -UseBasicParsing `
        -TimeoutSec 10 `
        -ErrorAction Stop
    
    if ($resp.StatusCode -eq 200) {
        Write-Host "  ✅ Update triggered successfully." -ForegroundColor Green
        Write-Host "     Blocklists will download in the background." -ForegroundColor DarkGreen
        Write-Host "     Check status at: http://127.0.0.1:3000 → Filters" -ForegroundColor DarkGray
    } else {
        Write-Host "  ⚠️  Unexpected response: $($resp.StatusCode)" -ForegroundColor Yellow
        Write-Host "     Try updating manually via http://127.0.0.1:3000 → Filters → Update Now" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  ⚠️  Could not reach AGH API." -ForegroundColor Yellow
    Write-Host "     This is expected if you have set an admin password." -ForegroundColor DarkGray
    Write-Host "     Update manually: http://127.0.0.1:3000 → Filters → Update Now" -ForegroundColor DarkGray
    Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor DarkGray
}

Write-Host ""
