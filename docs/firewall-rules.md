# VantaDNS — Firewall Rules

All Windows Firewall rules created by VantaDNS are documented here.  
Every rule has a name, direction, protocol, port, source, action, and explicit rationale.

---

## Critical Security Requirement

> **VantaDNS must never become an open recursive DNS resolver.**
>
> An open recursive DNS resolver accepts and answers DNS queries from any source on the Internet.  
> This enables **DNS amplification attacks**: an attacker sends small DNS queries with a spoofed source IP to your resolver, which sends large responses to the victim. Your IP address becomes a weapon in a DDoS attack.
>
> Every firewall rule below is designed to prevent this.

---

## Active Rules

### Rule 1: VantaDNS-DNS-LAN-Inbound

| Field | Value |
|-------|-------|
| **Name** | VantaDNS-DNS-LAN-Inbound |
| **Direction** | Inbound |
| **Protocol** | UDP + TCP |
| **Local Port** | 53 |
| **Remote Address** | 10.76.181.0/24 |
| **Action** | Allow |
| **Profile** | Private |

**Rationale:** LAN client devices (phones, tablets, other computers on the `10.76.181.0/24` subnet) need to reach AdGuard Home's DNS listener on port 53. This rule allows that traffic. The `/24` subnet mask ensures only devices on your home network can use this service.

**PowerShell command used to create:**
```powershell
New-NetFirewallRule `
  -DisplayName "VantaDNS-DNS-LAN-Inbound" `
  -Direction Inbound `
  -Protocol UDP `
  -LocalPort 53 `
  -RemoteAddress "10.76.181.0/24" `
  -Action Allow `
  -Profile Private `
  -Description "Allow DNS from LAN only - VantaDNS"

New-NetFirewallRule `
  -DisplayName "VantaDNS-DNS-LAN-Inbound-TCP" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 53 `
  -RemoteAddress "10.76.181.0/24" `
  -Action Allow `
  -Profile Private `
  -Description "Allow DNS TCP from LAN only - VantaDNS"
```

---

### Rule 2: VantaDNS-AdminUI-Loopback-Inbound

| Field | Value |
|-------|-------|
| **Name** | VantaDNS-AdminUI-Loopback-Inbound |
| **Direction** | Inbound |
| **Protocol** | TCP |
| **Local Port** | 3000 |
| **Remote Address** | 127.0.0.1 |
| **Action** | Allow |
| **Profile** | Any |

**Rationale:** AdGuard Home's admin UI runs on port 3000. It must only be accessible from the PC itself (loopback address `127.0.0.1`). The admin UI provides full configuration access to the DNS resolver, so it must never be reachable from LAN clients or the Internet.

**PowerShell command used to create:**
```powershell
New-NetFirewallRule `
  -DisplayName "VantaDNS-AdminUI-Loopback-Inbound" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 3000 `
  -RemoteAddress "127.0.0.1" `
  -Action Allow `
  -Profile Any `
  -Description "Allow AGH Admin UI from loopback only - VantaDNS"
```

---

### Rule 3: VantaDNS-Unbound-Loopback-Inbound

| Field | Value |
|-------|-------|
| **Name** | VantaDNS-Unbound-Loopback-Inbound |
| **Direction** | Inbound |
| **Protocol** | UDP + TCP |
| **Local Port** | 5335 |
| **Remote Address** | 127.0.0.1 |
| **Action** | Allow |
| **Profile** | Any |

**Rationale:** Unbound listens on port 5335 and should only receive queries from AdGuard Home (which runs on the same machine, loopback). This rule explicitly allows loopback traffic to 5335. The Unbound configuration itself also enforces `access-control: 127.0.0.1/32 allow` — defense in depth.

**PowerShell command used to create:**
```powershell
New-NetFirewallRule `
  -DisplayName "VantaDNS-Unbound-Loopback-Inbound-UDP" `
  -Direction Inbound `
  -Protocol UDP `
  -LocalPort 5335 `
  -RemoteAddress "127.0.0.1" `
  -Action Allow `
  -Profile Any `
  -Description "Allow Unbound from loopback only - VantaDNS"

New-NetFirewallRule `
  -DisplayName "VantaDNS-Unbound-Loopback-Inbound-TCP" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 5335 `
  -RemoteAddress "127.0.0.1" `
  -Action Allow `
  -Profile Any `
  -Description "Allow Unbound TCP from loopback only - VantaDNS"
```

---

### Rule 4: VantaDNS-DNS-Public-Block

| Field | Value |
|-------|-------|
| **Name** | VantaDNS-DNS-Public-Block |
| **Direction** | Inbound |
| **Protocol** | UDP + TCP |
| **Local Port** | 53 |
| **Remote Address** | Any (except 10.76.181.0/24) |
| **Action** | Block |
| **Profile** | Public, Domain |

**Rationale:** This is the most critical security rule. It explicitly blocks DNS queries from any source that is NOT on the local LAN subnet. Combined with Rule 1, this creates an explicit deny for all public-Internet sources on port 53. This prevents VantaDNS from ever acting as an open resolver.

**PowerShell command used to create:**
```powershell
New-NetFirewallRule `
  -DisplayName "VantaDNS-DNS-Public-Block-UDP" `
  -Direction Inbound `
  -Protocol UDP `
  -LocalPort 53 `
  -RemoteAddress "Any" `
  -Action Block `
  -Profile Public, Domain `
  -Description "Block DNS from non-LAN sources - VantaDNS anti-open-resolver"

New-NetFirewallRule `
  -DisplayName "VantaDNS-DNS-Public-Block-TCP" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 53 `
  -RemoteAddress "Any" `
  -Action Block `
  -Profile Public, Domain `
  -Description "Block DNS TCP from non-LAN sources - VantaDNS anti-open-resolver"
```

---

## Verifying Firewall Rules

```powershell
# List all VantaDNS firewall rules
Get-NetFirewallRule -DisplayName "VantaDNS*" | Select-Object DisplayName, Enabled, Action, Direction

# Verify DNS LAN rule
Get-NetFirewallRule -DisplayName "VantaDNS-DNS-LAN-Inbound" | 
  Get-NetFirewallAddressFilter | Select-Object RemoteAddress
```

## Removing All VantaDNS Firewall Rules (cleanup)

```powershell
Get-NetFirewallRule -DisplayName "VantaDNS*" | Remove-NetFirewallRule
```

---

## Windows DNS Client Service (Port 53 Conflict)

Windows 10 runs a built-in DNS Client service (`Dnscache`). This service does NOT listen on port 53 by default (it uses the Windows name resolution stack internally). However, if there are conflicts, AdGuard Home's service installer handles rebinding.

If port 53 is already in use at install time:
```powershell
# Check what is using port 53
netstat -ano | findstr ":53 "
# Look up the PID
Get-Process -Id <PID>
```
