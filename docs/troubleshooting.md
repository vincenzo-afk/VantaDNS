# VantaDNS — Troubleshooting Guide

A systematic approach to diagnosing and fixing problems with VantaDNS.

---

## Quick Diagnostics

Before diving into specific issues, run:
```powershell
.\scripts\health-check.ps1
```

Then check service status:
```powershell
Get-Service -Name "AdGuardHome", "Unbound" | Select-Object Name, Status, StartType
```

---

## Issue: DNS Queries Not Resolving

### Symptom
`nslookup google.com 127.0.0.1` times out or returns `Request to 127.0.0.1 timed-out`.

### Diagnosis Steps

**Step 1 — Is AdGuard Home running?**
```powershell
Get-Service -Name "AdGuardHome"
# Expected: Status = Running
```
If Stopped: `Start-Service -Name "AdGuardHome"`

**Step 2 — Is AdGuard Home listening on port 53?**
```powershell
netstat -ano | findstr ":53 "
# Expected: A line showing LISTENING with the AGH process PID
```

**Step 3 — Is Unbound running?**
```powershell
Get-Service -Name "Unbound"
# Expected: Status = Running
```
If Stopped: `Start-Service -Name "Unbound"`

**Step 4 — Is Unbound listening on port 5335?**
```powershell
netstat -ano | findstr ":5335"
# Expected: A LISTENING line
```

**Step 5 — Can Unbound be queried directly?**
```powershell
nslookup -port=5335 google.com 127.0.0.1
# Expected: Returns valid IP addresses
```
If this fails but the service is running, check `unbound.conf` for configuration errors.

**Step 6 — Check Windows Event Log**
```powershell
Get-EventLog -LogName System -Source "Service Control Manager" -Newest 30 | 
  Where-Object {$_.Message -like "*Unbound*" -or $_.Message -like "*AdGuard*"}
```

---

## Issue: Port 53 Already in Use

### Symptom
AdGuard Home fails to start with "address already in use" or similar error.

### Diagnosis
```powershell
netstat -ano | findstr ":53 "
# Note the PID on the LISTENING line
Get-Process -Id <PID>
```

### Common causes and fixes

| Process | Fix |
|---------|-----|
| `dns.exe` (Windows DNS Server role) | Disable the DNS Server role in Windows Features |
| `svchost.exe` (Windows DNS Client) | Windows DNS Client doesn't normally bind port 53; restart the service |
| Another DNS resolver | Uninstall or reconfigure the conflicting software |

**If the Windows DNS Client is the issue:**
```powershell
# Restart it
Restart-Service -Name "Dnscache"
```
Note: The Windows DNS Client service (`Dnscache`) caches DNS but typically does NOT bind port 53. If it is binding port 53, something unusual is happening.

---

## Issue: Blocked Domain Still Resolving

### Symptom
`nslookup doubleclick.net 127.0.0.1` returns a real IP instead of `0.0.0.0`.

### Diagnosis Steps

**Step 1 — Are blocklists loaded?**
Open `http://127.0.0.1:3000` → Filters → DNS Blocklists.  
Check that lists show a non-zero rule count and "Last Updated" time.

**Step 2 — Is the domain in the blocklist?**
In the AGH admin UI: Query Log (temporarily enable) → test → check the result.  
Or: Filters → Check Filtering → enter `doubleclick.net`.

**Step 3 — Is there an allowlist override?**
Check `allowlists/custom-allowlist.txt` for an entry matching the domain.

**Step 4 — Is the domain queried from the correct DNS server?**
```powershell
# Make sure you're querying VantaDNS, not your router or ISP
nslookup doubleclick.net 127.0.0.1
# vs
nslookup doubleclick.net 8.8.8.8
# The VantaDNS query should return 0.0.0.0
```

---

## Issue: Legitimate Domain Blocked (False Positive)

### Symptom
A website or application fails to load. Testing reveals the domain is being blocked.

### Fix

**Step 1 — Identify the blocked domain**
```powershell
# Temporarily enable query log in AGH admin UI
# Then access the failing site
# Look for blocked entries in the query log
```

**Step 2 — Add to allowlist**
```
# allowlists/custom-allowlist.txt
# Add one domain per line in AdGuard syntax:
@@||the-blocked-domain.com^
```

**Step 3 — Reload filters in AGH**
Open `http://127.0.0.1:3000` → Filters → Update Now  
Or restart the service:
```powershell
Restart-Service -Name "AdGuardHome"
```

**Step 4 — Disable query log again after debugging**

---

## Issue: Slow DNS Resolution

### Symptom
DNS queries take several seconds. Browsing feels slow.

### Diagnosis Steps

**Step 1 — Measure latency**
```powershell
.\scripts\benchmark.ps1
```

**Step 2 — Is the cache working?**
- Cold query (first time) should be 50–300ms (recursive resolution)
- Warm query (second time, same domain) should be < 5ms
- If warm queries are also slow, the cache may not be working

**Step 3 — Check Unbound cache size**
```powershell
# Check Unbound's cache statistics via control
# (if unbound-control is configured)
unbound-control stats_noreset | findstr "cache"
```

**Step 4 — Check if Unbound is doing recursive resolution**
If Unbound can't reach root servers (e.g., Internet outage, firewall blocking outbound DNS), all non-cached queries will fail or time out.

```powershell
# Test connectivity to a root server
Test-NetConnection -ComputerName "198.41.0.4" -Port 53
# 198.41.0.4 is a.root-servers.net
```

---

## Issue: Internet Connectivity Lost, DNS Breaks Completely

### Symptom
When Internet goes down, ALL DNS queries fail instead of returning cached results.

### Expected Behavior
- Cached domains: Unbound returns the cached response (fast, works offline)
- Uncached domains: Unbound returns SERVFAIL (correct — cannot resolve without Internet)
- Blocked domains: AdGuard Home still returns 0.0.0.0 (works offline)

### Fix
If the cache is empty or too small, increase Unbound's cache size in `unbound.conf`:
```
msg-cache-size: 128m
rrset-cache-size: 256m
```

---

## Issue: AdGuard Home Admin UI Not Accessible

### Symptom
`http://127.0.0.1:3000` returns connection refused.

### Fix
```powershell
# Check if AGH is running
Get-Service -Name "AdGuardHome"

# Check if port 3000 is listening
netstat -ano | findstr ":3000"

# Check AGH config for bind address
# Should be: bind_host: 127.0.0.1  bind_port: 3000
```

---

## Issue: DNSSEC Validation Failures

### Symptom
Some domains fail to resolve with SERVFAIL even when the Internet is available.

### Diagnosis
```powershell
# Test with DNSSEC disabled to isolate
nslookup -type=A -set=norec example.com 127.0.0.1

# Test DNSSEC validation (this domain is specifically signed and valid)
nslookup sigok.verteiltesysteme.net 127.0.0.1
# Should return valid IP

# Test with a domain known to have broken DNSSEC (should fail)
nslookup sigfail.verteiltesysteme.net 127.0.0.1
# Should return SERVFAIL - this is correct behavior
```

If valid domains are failing DNSSEC:
1. Check that `unbound.conf` has `auto-trust-anchor-file` pointing to a valid path
2. Check that the root trust anchor is current: `unbound-anchor -v`
3. Check Unbound logs for `BOGUS` messages

---

## Issue: Network Recovery Not Automatic

### Symptom
After Internet reconnects, DNS still fails and a service restart is required.

### Expected Behavior
Unbound should automatically resume recursive resolution when Internet returns.  
No manual restart should be required.

### Fix
If restarts are required:
- Check `unbound.conf` for `do-not-query-localhost: no` (needed for loopback forwarding tests)
- Check Windows Firewall — sometimes Windows briefly blocks outbound after reconnect
- Run: `Restart-Service -Name "Unbound"` as a workaround while investigating

---

## Issue: DNS Queries Leaking to Router

### Symptom
`nslookup google.com` (without specifying server) uses the router's DNS instead of VantaDNS.

### Diagnosis
```powershell
# Check what DNS servers Windows is using
Get-DnsClientServerAddress -AddressFamily IPv4

# If it shows the router IP (e.g., 10.76.181.1), VantaDNS is not set as the system DNS
```

### Fix
Set the PC's own DNS to `127.0.0.1` so the PC itself uses VantaDNS:
```powershell
# Find your Wi-Fi interface name
Get-NetAdapter | Where-Object {$_.Status -eq "Up"}

# Set DNS to loopback
Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses "127.0.0.1"
```

---

## Useful Diagnostic Commands

```powershell
# All VantaDNS firewall rules
Get-NetFirewallRule -DisplayName "VantaDNS*"

# What's listening on key ports
netstat -ano | findstr ":53 "
netstat -ano | findstr ":5335"
netstat -ano | findstr ":3000"

# DNS server assigned to each interface
Get-DnsClientServerAddress -AddressFamily IPv4

# Flush Windows DNS cache (does not flush Unbound cache)
ipconfig /flushdns

# Test MX record
nslookup -type=MX gmail.com 127.0.0.1

# Test TXT record
nslookup -type=TXT google.com 127.0.0.1

# Test AAAA record
nslookup -type=AAAA google.com 127.0.0.1

# Resolve with specific server without using system config
Resolve-DnsName -Name google.com -Server 127.0.0.1 -Type A
```
