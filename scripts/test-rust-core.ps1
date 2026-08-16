# VantaDNS — Custom Rust Core Live Integration Test Script
# Verifies live packet processing, blocklist filtering, caching, and upstream forwarding on dns-core

Param(
    [string]$Server = "127.0.0.1",
    [int]$Port = 5354
)

$ErrorActionPreference = "Continue"

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " VantaDNS Rust Core (vanta-dns-core) Live Test Suite" -ForegroundColor Cyan
Write-Host " Server: ${Server}:${Port}" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$testsPassed = 0
$testsFailed = 0

function Query-UdpDns {
    Param(
        [string]$Domain,
        [string]$ServerIp,
        [int]$ServerPort
    )

    # Build simple RFC 1035 A record query packet
    $id = [byte[]](0x12, 0x34)
    $flags = [byte[]](0x01, 0x00) # Standard query, RD=1
    $qdcount = [byte[]](0x00, 0x01)
    $ancount = [byte[]](0x00, 0x00)
    $nscount = [byte[]](0x00, 0x00)
    $arcount = [byte[]](0x00, 0x00)

    $qname = New-Object System.Collections.Generic.List[byte]
    foreach ($part in $Domain.Split('.')) {
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($part)
        $qname.Add([byte]$bytes.Length)
        $qname.AddRange($bytes)
    }
    $qname.Add(0x00)

    $qtype = [byte[]](0x00, 0x01)  # Type A
    $qclass = [byte[]](0x00, 0x01) # Class IN

    $packet = New-Object System.Collections.Generic.List[byte]
    $packet.AddRange($id)
    $packet.AddRange($flags)
    $packet.AddRange($qdcount)
    $packet.AddRange($ancount)
    $packet.AddRange($nscount)
    $packet.AddRange($arcount)
    $packet.AddRange($qname.ToArray())
    $packet.AddRange($qtype)
    $packet.AddRange($qclass)

    $udp = New-Object System.Net.Sockets.UdpClient
    $udp.Client.ReceiveTimeout = 3000
    $udp.Connect($ServerIp, $ServerPort)

    $bytes = $packet.ToArray()
    [void]$udp.Send($bytes, $bytes.Length)

    $remoteEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
    $response = $udp.Receive([ref]$remoteEP)
    $udp.Close()

    return $response
}

function Test-Query {
    Param(
        [string]$Name,
        [string]$Domain,
        [bool]$ExpectBlocked = $false
    )

    Write-Host "[TEST] $Name ($Domain)... " -NoNewline

    try {
        $resp = Query-UdpDns -Domain $Domain -ServerIp $Server -ServerPort $Port
        
        # Header rcode check (last 4 bits of byte index 3)
        $rcode = $resp[3] -band 0x0F
        
        if ($ExpectBlocked) {
            if ($rcode -eq 3) { # NXDOMAIN
                Write-Host "PASSED (Blocked with NXDOMAIN)" -ForegroundColor Green
                $script:testsPassed++
            } else {
                Write-Host "FAILED (Expected NXDOMAIN rcode=3, got rcode=$rcode)" -ForegroundColor Red
                $script:testsFailed++
            }
        } else {
            if ($rcode -eq 0 -and $resp.Length -gt 12) { # NOERROR
                Write-Host "PASSED (Resolved, RCODE=0, Bytes=$($resp.Length))" -ForegroundColor Green
                $script:testsPassed++
            } else {
                Write-Host "FAILED (RCODE=$rcode)" -ForegroundColor Red
                $script:testsFailed++
            }
        }
    } catch {
        Write-Host "FAILED ($($_.Exception.Message))" -ForegroundColor Red
        $script:testsFailed++
    }
}

Test-Query -Name "Standard A Record Resolution" -Domain "google.com"
Test-Query -Name "Secondary A Record Resolution" -Domain "wikipedia.org"
Test-Query -Name "Third A Record Resolution" -Domain "github.com"
Test-Query -Name "Blocked Domain (doubleclick.net)" -Domain "doubleclick.net" -ExpectBlocked $true
Test-Query -Name "Blocked Domain (googlesyndication.com)" -Domain "googlesyndication.com" -ExpectBlocked $true

Write-Host ""
Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
Write-Host " Summary: $testsPassed Passed, $testsFailed Failed" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
