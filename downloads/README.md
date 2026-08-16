# VantaDNS Downloads Directory

This directory holds installer binaries downloaded during setup.

Binaries are excluded from Git by `.gitignore` (they are large and change with versions).

## Contents (after running install.ps1 or downloading manually)

| File | Source |
|------|--------|
| `unbound_setup_1.26.0.exe` | https://nlnetlabs.nl/downloads/unbound/ |
| `AdGuardHome_v0.107.52_windows_amd64.zip` | https://github.com/AdguardTeam/AdGuardHome/releases |
| `root.hints` | https://www.internic.net/domain/named.root |

`install.ps1` will check this directory first before downloading from the Internet.
