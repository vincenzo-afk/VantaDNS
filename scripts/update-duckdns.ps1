# VantaDNS — DuckDNS Auto-Updater Script
# Keeps user-vanta.duckdns.org updated with current public IP address

Param(
    [string]$Domain = "user-vanta",
    [string]$Token = "60dafe7b-4059-469b-abae-36ca31a146de"
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host "Updating DuckDNS domain: ${Domain}.duckdns.org..." -ForegroundColor Cyan

$url = "https://www.duckdns.org/update?domains=${Domain}&token=${Token}&ip="

try {
    $response = Invoke-RestMethod -Uri $url -UseBasicParsing -TimeoutSec 10
    if ($response -like "*OK*") {
        Write-Host "✅ DuckDNS successfully updated! (${Domain}.duckdns.org)" -ForegroundColor Green
    } else {
        Write-Host "❌ DuckDNS update response: $response" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ DuckDNS update error: $($_.Exception.Message)" -ForegroundColor Red
}
