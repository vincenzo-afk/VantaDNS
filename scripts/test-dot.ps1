# VantaDNS — DNS-over-TLS (DoT Port 853) Verification Script
# Verifies encrypted TLS DNS queries on Port 853

Param(
    [string]$Server = "127.0.0.1",
    [int]$Port = 853
)

$ErrorActionPreference = "Continue"

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " VantaDNS DNS-over-TLS (DoT Port 853) Verification" -ForegroundColor Cyan
Write-Host " Server: ${Server}:${Port}" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

function Query-DoTDns {
    Param(
        [string]$Domain,
        [string]$ServerIp,
        [int]$ServerPort
    )

    $id = [byte[]](0xAB, 0xCD)
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

    $dnsMsg = New-Object System.Collections.Generic.List[byte]
    $dnsMsg.AddRange($id)
    $dnsMsg.AddRange($flags)
    $dnsMsg.AddRange($qdcount)
    $dnsMsg.AddRange($ancount)
    $dnsMsg.AddRange($nscount)
    $dnsMsg.AddRange($arcount)
    $dnsMsg.AddRange($qname.ToArray())
    $dnsMsg.AddRange($qtype)
    $dnsMsg.AddRange($qclass)

    # DoT TCP framing: 2-byte prefix length (RFC 7858)
    $len = $dnsMsg.Count
    $lengthPrefix = [byte[]]([byte]($len -shr 8), [byte]($len -band 0xFF))

    $tcpPayload = New-Object System.Collections.Generic.List[byte]
    $tcpPayload.AddRange($lengthPrefix)
    $tcpPayload.AddRange($dnsMsg.ToArray())

    # Establish TCP TLS Connection
    $tcpClient = New-Object System.Net.Sockets.TcpClient($ServerIp, $ServerPort)
    $sslStream = New-Object System.Net.Security.SslStream(
        $tcpClient.GetStream(),
        $false,
        { param($sender, $certificate, $chain, $sslPolicyErrors) return $true }
    )

    $sslStream.AuthenticateAsClient("dns.vantadns.net")

    $payloadBytes = $tcpPayload.ToArray()
    $sslStream.Write($payloadBytes, 0, $payloadBytes.Length)
    $sslStream.Flush()

    # Read 2-byte TCP length prefix response
    $lenBuf = New-Object byte[] 2
    [void]$sslStream.Read($lenBuf, 0, 2)
    $respLen = ($lenBuf[0] -shl 8) -bor $lenBuf[1]

    # Read DNS response packet bytes
    $respBuf = New-Object byte[] $respLen
    $totalRead = 0
    while ($totalRead -lt $respLen) {
        $read = $sslStream.Read($respBuf, $totalRead, $respLen - $totalRead)
        if ($read -le 0) { break }
        $totalRead += $read
    }

    $sslStream.Close()
    $tcpClient.Close()

    return $respBuf
}

function Test-DoTQuery {
    Param(
        [string]$Name,
        [string]$Domain,
        [bool]$ExpectBlocked = $false
    )

    Write-Host "[TEST DoT :853] $Name ($Domain)... " -NoNewline

    try {
        $resp = Query-DoTDns -Domain $Domain -ServerIp $Server -ServerPort $Port
        $rcode = $resp[3] -band 0x0F
        $ancount = ($resp[6] -shl 8) -bor $resp[7]
        
        # Check for 0.0.0.0 in answer section (last 4 bytes of standard A record answer)
        $isZeroIp = $false
        if ($ancount -gt 0 -and $resp.Length -ge 16) {
            $last4 = $resp[($resp.Length - 4)..($resp.Length - 1)]
            if ($last4[0] -eq 0 -and $last4[1] -eq 0 -and $last4[2] -eq 0 -and $last4[3] -eq 0) {
                $isZeroIp = $true
            }
        }

        if ($ExpectBlocked) {
            if ($rcode -eq 3 -or $isZeroIp) {
                Write-Host "PASSED (Encrypted TLS Blocked: rcode=$rcode, zeroIp=$isZeroIp)" -ForegroundColor Green
            } else {
                Write-Host "FAILED (Expected block/NXDOMAIN/0.0.0.0, got rcode=$rcode)" -ForegroundColor Red
            }
        } else {
            if ($rcode -eq 0 -and -not $isZeroIp -and $resp.Length -gt 12) {
                Write-Host "PASSED (Encrypted TLS Resolved, RCODE=0, Bytes=$($resp.Length))" -ForegroundColor Green
            } else {
                Write-Host "FAILED (RCODE=$rcode, zeroIp=$isZeroIp)" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "FAILED ($($_.Exception.Message))" -ForegroundColor Red
    }
}

Test-DoTQuery -Name "Encrypted DoT Resolution" -Domain "google.com"
Test-DoTQuery -Name "Encrypted DoT Resolution" -Domain "wikipedia.org"
Test-DoTQuery -Name "Encrypted DoT Spotify Block" -Domain "spclient.wg.spotify.com" -ExpectBlocked $true
Test-DoTQuery -Name "Encrypted DoT YouTube Block" -Domain "s.youtube.com" -ExpectBlocked $true
Test-DoTQuery -Name "Encrypted DoT Mobile App Block" -Domain "unityads.unity3d.com" -ExpectBlocked $true
