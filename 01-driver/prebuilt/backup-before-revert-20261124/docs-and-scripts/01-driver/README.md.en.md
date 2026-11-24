# 01-driver · Audio Driver Code Project

> English version of [README.md](README.md).

This directory is the SN6140 audio driver code project, containing Linux reference sources, custom AppleALC sources (reproducible build), and the verified build artifact.

## Directory Contents

| Path | Description |
|---|---|
| `linux-reference/senarytech.c` | Linux mainline Senarytech HDA driver (note: mainline is SN6186 `0x1fa86186`, not this machine's SN6140) |
| `linux-reference/conexant.c` | Linux Conexant HDA driver; SN6140/SN6180 were originally registered here |
| `checksums/SHA256SUMS.txt` | SHA256 checksum list from the community release (historical) |
| `checksums/SHA256SUMS-micfix.txt` | SHA256 checksums of the mic-fixed kext / resources |
| `prebuilt/AppleALC.kext` | ★ Verified custom kext (version 1.9.9 / `DBG-199-2026-10-26`), **includes the 2026-11-24 microphone fix; this is what gets deployed** |
| `prebuilt/backup-pre-micfix/` | Pre-fix kext and resource backup for manual rollback |
| `source/` | Complete AppleALC source snapshot + dependencies + build script + compiled object files |

## Core: SN6140 Layout Resources

`source/Resources/SN6140/`:

- `layout15.xml` / `layout15.xml.zlib` — SN6140 layout 15 config (verb/pin/widget); since 2026-11-24 the input endpoints are `Mic` + `ExtMic`
- `Platforms15.xml` / `Platforms15.xml.zlib` — platform node config
- `Info.plist` — codec metadata

During build, these resources are packed by `ResourceConverter` into `AppleALC/kern_resources.cpp`, and finally embedded into the kext binary.

## Building

See [`source/build.sh`](source/build.sh) and [../docs/04-编译指南.md.en.md](../docs/04-编译指南.md.en.md).

```bash
cd source && bash build.sh
```

> ⚠️ This machine only has Command Line Tools (clang 17); the final link failed due to a linker version issue; 9 object files compiled successfully. A full build needs Xcode 16.4. Actual deployment uses `prebuilt/AppleALC.kext` (community-verified artifact).

## Why the Linux Source Is Only a Reference

Linux's ALSA HDA driver has a completely different architecture from macOS AppleHDA and cannot be ported directly into a kext. What this project borrows is its approach to codec identification and configuration; what actually makes the sound card work is AppleALC's layout configuration data. See [../docs/02-技术路线.md.en.md](../docs/02-技术路线.md.en.md).
