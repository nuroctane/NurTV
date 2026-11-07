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

## Network

No addresses, host names or adapter details belong in this repo. The TV's
address is local state: keep it in `.tv-ip` at the repo root (gitignored) or in
the `TV_IP` environment variable. `./scripts/connect.sh` reads those; pass an IP
to override for one run.

**Why discovery kept failing.** A neighbour-table scan (`arp -a`,
`Get-NetNeighbor`) only shows hosts that the interface has already talked to, so
it looks nearly empty on a clean run. An ICMP sweep also misses the TV when it is
idle or asleep. And with more than one NIC on the same subnet, the OS may send
the probe out the wrong one.

What works: SSDP. Send an `M-SEARCH` for
`urn:dial-multiscreen-org:service:dial:1` bound to the interface that faces the
TV, and read the replies. Fire OS answers as a TV device with the manufacturer
and model in the `dd.xml`; a Roku on the same LAN answers with its own SSDP
server string and a different DIAL port, so check the model before connecting.

```powershell
# replace with the local address of the NIC that faces the TV
$local = [System.Net.IPAddress]::Parse('192.0.2.10')
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
