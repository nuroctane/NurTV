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

## Known-risky package

`com.amazon.tv.launcher` — never disable by hand before a working replacement is
installed and confirmed as HOME. CleanTV's `launcher.sh` does it in the safe order.
