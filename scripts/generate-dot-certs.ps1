# VantaDNS — DNS-over-TLS (DoT) Certificate Generator
# Generates PEM-encoded TLS certificate (tls.crt) and private key (tls.key) for Port 853

$ErrorActionPreference = "Stop"

$certsDir = "c:\Users\S K\Desktop\VantaDNS\certs"
if (-not (Test-Path $certsDir)) {
    New-Item -Path $certsDir -ItemType Directory | Out-Null
}

$certPath = Join-Path $certsDir "tls.crt"
$keyPath  = Join-Path $certsDir "tls.key"

Write-Host "Generating self-signed TLS certificate for DNS-over-TLS (Port 853)..." -ForegroundColor Cyan

# Generate certificate using New-SelfSignedCertificate
$cert = New-SelfSignedCertificate `
    -DnsName "dns.vantadns.net", "dns.vantadns.local", "localhost", "127.0.0.1" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -KeyLength 2048 `
    -KeyAlgorithm RSA `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(5)

# Export Certificate (PEM)
$certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
$certBase64 = [System.Convert]::ToBase64String($certBytes, [System.Base64FormattingOptions]::InsertLineBreaks)
$certPem = "-----BEGIN CERTIFICATE-----`n$certBase64`n-----END CERTIFICATE-----`n"
[System.IO.File]::WriteAllText($certPath, $certPem, (New-Object System.Text.UTF8Encoding $false))

# Export Private Key (PEM)
$rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
$params = $rsa.ExportParameters($true)

# Convert RSA parameters to RSAPrivateKey DER format
$stream = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter($stream)

function Write-Length($len) {
    if ($len -lt 128) {
        $writer.Write([byte]$len)
    } else {
        $bytes = @()
        while ($len -gt 0) {
            $bytes = @([byte]($len -band 0xFF)) + $bytes
            $len = $len -shr 8
        }
        $writer.Write([byte](0x80 -bor $bytes.Length))
        foreach ($b in $bytes) { $writer.Write([byte]$b) }
    }
}

function Write-Integer($bytes) {
    $idx = 0
    while ($idx -lt $bytes.Length - 1 -and $bytes[$idx] -eq 0) { $idx++ }
    $slice = $bytes[$idx..($bytes.Length - 1)]
    if (($slice[0] -band 0x80) -ne 0) {
        $slice = @([byte]0) + $slice
    }
    $writer.Write([byte]0x02)
    Write-Length $slice.Length
    $writer.Write([byte[]]$slice, 0, $slice.Length)
}

$oldWriter = $writer
$innerStream = New-Object System.IO.MemoryStream
$innerWriter = New-Object System.IO.BinaryWriter($innerStream)
$writer = $innerWriter

$writer.Write([byte]0x02); $writer.Write([byte]0x01); $writer.Write([byte]0x00) # version 0
Write-Integer $params.Modulus
Write-Integer $params.Exponent
Write-Integer $params.D
Write-Integer $params.P
Write-Integer $params.Q
Write-Integer $params.DP
Write-Integer $params.DQ
Write-Integer $params.InverseQ

$writer = $oldWriter
$innerBytes = $innerStream.ToArray()
$writer.Write([byte]0x30)
Write-Length $innerBytes.Length
$writer.Write([byte[]]$innerBytes, 0, $innerBytes.Length)

$keyBytes = $stream.ToArray()
$keyBase64 = [System.Convert]::ToBase64String($keyBytes, [System.Base64FormattingOptions]::InsertLineBreaks)
$keyPem = "-----BEGIN RSA PRIVATE KEY-----`n$keyBase64`n-----END RSA PRIVATE KEY-----`n"
[System.IO.File]::WriteAllText($keyPath, $keyPem, (New-Object System.Text.UTF8Encoding $false))

Write-Host "✅ Certificates successfully generated!" -ForegroundColor Green
Write-Host "   Certificate: $certPath" -ForegroundColor DarkGray
Write-Host "   Private Key: $keyPath" -ForegroundColor DarkGray
