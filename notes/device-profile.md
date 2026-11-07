# Device profile — captured 2026-10-25 from Settings → About

| Field | Value |
|---|---|
| Model | `TCL_65Q650F` (TCL Q6-series 65" Fire TV) |
| Software Version | **Fire OS 7.7.1.7 (PS7717/5741)** |
| Fire TV Home Version | `7321874.1` |
| Storage | 11.75 GB total / 1.58 GB used |
| Platform | Fire OS 7 = Android 9 = **SDK 28** |
| Verified boot | expected `green`/locked (re-confirm in preflight) |

## What this means

- **Root: not available.** Every public Fire TV root chain (CVE-2026-43499 →
  GhostLock → Kamakiri → TWRP) targets Fire TV **Sticks** by SoC codename
  (karat / mantra / sheldon / sheldonp / mantis / montoya / tank).
  `TCL_65Q650F` is a Fire TV **Edition television** — out of scope, no TWRP,
  no bootloader unlock. Path A (ADB) is the ceiling. That is fine.
- **ADB debloat: fully supported.** Fire OS 7.7 is inside CleanTV's tested range
  (7.7 devices tested: Insignia F30, Onida 43", Hisense 55QD65NF, Stick HD 2024).
- **Launcher replacement: yes** — this is the whole point, and it's what Roku
  could never do.
- Storage is not a constraint (10.1 GB free).

## Network (re-confirmed 2026-11-07)

| Field | Value |
|---|---|
| TV IPv4 | **`192.0.2.10`** (wired, DHCP) |
| ADB target | `192.0.2.10:5555` |
| Gateway | `192.0.2.1` |

`./scripts/connect.sh` now defaults to this address; pass an IP to override.

**Why discovery kept failing.** This PC has two NICs on the same `/24` —
Ethernet `192.0.2.12` (ifMetric 25) and Wi-Fi `192.0.2.13` (ifMetric 35).
Windows routes LAN traffic out Ethernet, but `arp -a` and `Get-NetNeighbor` only
show hosts that NIC has already talked to, so a neighbour-table scan looks almost
empty. And a plain ICMP sweep misses the TV when it is idle/asleep — the first
pass found six hosts and not the TV.

What works: SSDP. Send an `M-SEARCH` for
`urn:dial-multiscreen-org:service:dial:1` from the wired address and read the
replies. The TV answers with `friendlyName Fire TV`, `manufacturer TCL`,
`modelName 65Q650F` on port 60000. Do not confuse it with the Roku at
`192.0.2.14` (SSDP server `Roku/15.3.4`, DIAL on 8060).

```powershell
# bind the probe to the wired NIC, or it may leave via Wi-Fi
$local = [System.Net.IPAddress]::Parse('192.0.2.12')
$udp = New-Object System.Net.Sockets.UdpClient(0, [System.Net.Sockets.AddressFamily]::InterNetwork)
$udp.Client.Bind((New-Object System.Net.IPEndPoint($local, 0)))
$udp.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::IP,
  [System.Net.Sockets.SocketOptionName]::MulticastInterface, $local.GetAddressBytes())
$msg = "M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: `"ssdp:discover`"`r`nMX: 2`r`nST: urn:dial-multiscreen-org:service:dial:1`r`n`r`n"
$b = [Text.Encoding]::ASCII.GetBytes($msg)
$udp.Send($b, $b.Length, (New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse('239.255.255.250'), 1900)))
```

A refused connection on 5555 means the host is up but ADB debugging is off —
that is a TV setting, not a network fault.

## Known-risky package

`com.amazon.tv.launcher` — never disable by hand before a working replacement is
installed and confirmed as HOME. CleanTV's `launcher.sh` does it in the safe order.
