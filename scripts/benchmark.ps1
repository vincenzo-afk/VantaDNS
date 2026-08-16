# ============================================================
# VantaDNS — DNS Latency Benchmark Script
# scripts/benchmark.ps1
#
# Measures:
#   1. Cold-cache latency (first query, approximately)
#   2. Warm-cache latency (repeated queries, from cache)
#   3. Blocked domain response time (immediate, no upstream)
#   4. Comparison against public DNS resolvers
#
# Important: This measures DNS lookup latency only.
# It does not measure Internet connection speed or page load time.
# VantaDNS may reduce DNS latency via caching; it does not
# make the underlying ISP connection faster.
# ============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

# ============================================================
# CONFIGURATION
# ============================================================
$VANTA_DNS     = "127.0.0.1"
$VANTA_PORT    = 53

# Public resolvers for comparison (same home network)
$PUBLIC_RESOLVERS = @(
    @{ Name = "VantaDNS (warm)"; Server = "127.0.0.1"; Port = 53 },
    @{ Name = "Google (8.8.8.8)"; Server = "8.8.8.8"; Port = 53 },
    @{ Name = "Cloudflare (1.1.1.1)"; Server = "1.1.1.1"; Port = 53 },
    @{ Name = "Quad9 (9.9.9.9)"; Server = "9.9.9.9"; Port = 53 }
)

$WARM_DOMAINS = @(
    "google.com",
    "github.com",
    "cloudflare.com",
    "wikipedia.org",
    "microsoft.com",
    "youtube.com",
    "reddit.com",
    "amazon.com"
)

$BLOCKED_DOMAINS = @(
    "doubleclick.net",
    "googlesyndication.com",
    "googleadservices.com"
)

$ITERATIONS = 10   # Number of queries per domain for averaging

# ============================================================
# HELPERS
# ============================================================
function Measure-DnsMs { param([string]$domain, [string]$server, [int]$port = 53)
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Resolve-DnsName -Name $domain -Server $server -Port $port -Type A -DnsOnly -ErrorAction Stop | Out-Null
        $sw.Stop()
        return $sw.ElapsedMilliseconds
    } catch {
        $sw.Stop()
        return $sw.ElapsedMilliseconds   # Still count NXDOMAIN response time
    }
}

function Get-AverageMs { param([string]$domain, [string]$server, [int]$port, [int]$count)
    $times = @()
    for ($i = 0; $i -lt $count; $i++) {
        $ms = Measure-DnsMs $domain $server $port
        $times += $ms
        Start-Sleep -Milliseconds 50
    }
    $avg = ($times | Measure-Object -Average).Average
    $min = ($times | Measure-Object -Minimum).Minimum
    $max = ($times | Measure-Object -Maximum).Maximum
    return @{ Avg = [math]::Round($avg, 1); Min = $min; Max = $max }
}

function Write-TableRow {
    param([string]$label, [string]$avg, [string]$min, [string]$max, [string]$color = "White")
    Write-Host ("  {0,-30} {1,8} ms   {2,6} ms   {3,6} ms" -f $label, $avg, $min, $max) -ForegroundColor $color
}

function Get-LatencyColor { param([double]$ms)
    if ($ms -lt 5)   { return "Green" }
    if ($ms -lt 20)  { return "Cyan" }
    if ($ms -lt 50)  { return "Yellow" }
    if ($ms -lt 150) { return "DarkYellow" }
    return "Red"
}

# ============================================================
# MAIN
# ============================================================

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║  VantaDNS — DNS Latency Benchmark                   ║" -ForegroundColor Cyan
Write-Host "  ║  $([System.DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))                              ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ⚠️  Note: This measures DNS lookup latency only." -ForegroundColor DarkYellow
Write-Host "      It does not measure or reflect Internet connection speed." -ForegroundColor DarkGray
Write-Host ""

# ============================================================
# SECTION 1: Cold cache (approximate — first query per domain)
# ============================================================
Write-Host "  ── Cold-Cache Latency (first query per domain) ─────────" -ForegroundColor White
Write-Host ""
Write-Host ("  {0,-30} {1,8}      {2,6}      {3,6}" -f "Domain", "First ms", "", "") -ForegroundColor DarkGray

# Flush Windows DNS cache to simulate cold conditions
ipconfig /flushdns | Out-Null
Write-Host "  (Windows DNS cache flushed)" -ForegroundColor DarkGray
Write-Host ""

$coldResults = @()
foreach ($domain in $WARM_DOMAINS) {
    $ms = Measure-DnsMs $domain $VANTA_DNS $VANTA_PORT
    $color = Get-LatencyColor $ms
    Write-Host ("  {0,-30} {1,8} ms" -f $domain, $ms) -ForegroundColor $color
    $coldResults += $ms
    Start-Sleep -Milliseconds 100
}
$coldAvg = [math]::Round(($coldResults | Measure-Object -Average).Average, 1)
Write-Host ""
Write-Host "  Average cold latency: $coldAvg ms" -ForegroundColor (Get-LatencyColor $coldAvg)

# ============================================================
# SECTION 2: Warm cache (repeated queries)
# ============================================================
Write-Host ""
Write-Host "  ── Warm-Cache Latency ($ITERATIONS queries each) ──────────" -ForegroundColor White
Write-Host ""
Write-Host ("  {0,-30} {1,8}      {2,6}      {3,6}" -f "Domain", "Avg ms", "Min ms", "Max ms") -ForegroundColor DarkGray

$warmResults = @()
foreach ($domain in $WARM_DOMAINS) {
    $stats = Get-AverageMs $domain $VANTA_DNS $VANTA_PORT $ITERATIONS
    $color = Get-LatencyColor $stats.Avg
    Write-TableRow $domain $stats.Avg $stats.Min $stats.Max $color
    $warmResults += $stats.Avg
}
$warmAvg = [math]::Round(($warmResults | Measure-Object -Average).Average, 1)
Write-Host ""
Write-Host "  Average warm-cache latency: $warmAvg ms" -ForegroundColor (Get-LatencyColor $warmAvg)

# ============================================================
# SECTION 3: Blocked domain response time
# ============================================================
Write-Host ""
Write-Host "  ── Blocked Domain Response Time ─────────────────────────" -ForegroundColor White
Write-Host "  (Should be near-instant — no upstream needed)" -ForegroundColor DarkGray
Write-Host ""
Write-Host ("  {0,-30} {1,8}      {2,6}      {3,6}" -f "Domain", "Avg ms", "Min ms", "Max ms") -ForegroundColor DarkGray

$blockedResults = @()
foreach ($domain in $BLOCKED_DOMAINS) {
    $stats = Get-AverageMs $domain $VANTA_DNS $VANTA_PORT $ITERATIONS
    $color = Get-LatencyColor $stats.Avg
    Write-TableRow "[$domain]" $stats.Avg $stats.Min $stats.Max $color
    $blockedResults += $stats.Avg
}
$blockedAvg = [math]::Round(($blockedResults | Measure-Object -Average).Average, 1)
Write-Host ""
Write-Host "  Average blocked response: $blockedAvg ms" -ForegroundColor (Get-LatencyColor $blockedAvg)

# ============================================================
# SECTION 4: Public resolver comparison
# ============================================================
Write-Host ""
Write-Host "  ── Public Resolver Comparison (from same network) ───────" -ForegroundColor White
Write-Host "  (Comparing warm VantaDNS cache vs cold public resolvers)" -ForegroundColor DarkGray
Write-Host ""
Write-Host ("  {0,-30} {1,8}      {2,6}      {3,6}" -f "Resolver", "Avg ms", "Min ms", "Max ms") -ForegroundColor DarkGray

$TEST_DOMAIN = "example.com"  # Simple, universally resolves

foreach ($resolver in $PUBLIC_RESOLVERS) {
    # Small delay to avoid rate limiting by public resolvers
    Start-Sleep -Milliseconds 200
    $stats = Get-AverageMs $TEST_DOMAIN $resolver.Server $resolver.Port 5
    $color = Get-LatencyColor $stats.Avg
    $label = $resolver.Name
    Write-TableRow $label $stats.Avg $stats.Min $stats.Max $color
}

# ============================================================
# SUMMARY
# ============================================================
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║  SUMMARY                                             ║" -ForegroundColor Cyan
Write-Host "  ╠══════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host ("  ║  Cold-cache avg:    {0,8} ms                        ║" -f $coldAvg) -ForegroundColor White
Write-Host ("  ║  Warm-cache avg:    {0,8} ms                        ║" -f $warmAvg) -ForegroundColor White
Write-Host ("  ║  Blocked domains:   {0,8} ms                        ║" -f $blockedAvg) -ForegroundColor White
$improvement = if ($coldAvg -gt 0) { [math]::Round((1 - $warmAvg / $coldAvg) * 100, 0) } else { 0 }
Write-Host ("  ║  Cache speedup:     {0,7}%                         ║" -f $improvement) -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Disclaimer: DNS cache reduces lookup latency for repeated domains." -ForegroundColor DarkGray
Write-Host "  It does not make your ISP connection faster." -ForegroundColor DarkGray
Write-Host ""
