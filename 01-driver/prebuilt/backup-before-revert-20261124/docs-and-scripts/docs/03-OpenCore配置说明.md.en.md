# 03 · OpenCore Configuration Guide

> English version of [03-OpenCore配置说明.md](03-OpenCore配置说明.md).

The OC configuration in this project is modified automatically by the script, all concentrated in `EFI/OC/config.plist` and `EFI/OC/Kexts/`. Below is each change's location, value, and rationale.

## 0. Path Conventions

- `config.plist` is in XML format.
- ESP mount point defaults to `/Volumes/EFI`; on this machine the actual path is `EFI/OC/`.
- This machine's motherboard uses an Intel HDA controller, device path `PciRoot(0x0)/Pci(0x1F,0x3)` (HDEF@1F,3).

## 1. Kext Replacement

| Item | Old value | New value |
|---|---|---|
| `EFI/OC/Kexts/AppleALC.kext` | Official `REL-198-2026-09-27` (1.9.8, no SN6140) | Custom `DBG-199-2026-10-26` (1.9.9, with SN6140) |

Verify identity:

```bash
strings -a EFI/OC/Kexts/AppleALC.kext/Contents/MacOS/AppleALC | grep -E 'DBG-199|SN6140'
```

## 2. Kernel > Add (kext injection order and enable state)

| BundlePath | Requirement | Reason |
|---|---|---|
| `Lilu.kext` | Enabled=True, **before** AppleALC | AppleALC is a Lilu plugin and depends on Lilu loading first |
| `AppleALC.kext` | Enabled=True | Inject the custom driver |
| `SimpleHDA.kext` | **Enabled=False** | Competes with AppleALC for the same HDA controller; conflicts, must be disabled |

> The `SimpleHDA.kext` file remains in Kexts; it is only disabled in config (file not deleted, for easy rollback).

## 3. NVRAM > Add > 7C436110-AB2A-4BBB-A880-FE41995C9F82

### boot-args

```
old: ... alcid=11
new: ... alcid=15 alcdelay=1000
```

- `alcid=15`: tells AppleALC to use layout 15 (the verified config for SN6140).
- `alcdelay=1000`: delays 1000 ms to give the codec power-up/initialization time, avoiding too-early injection failures on some machines.
- The script de-duplicates by prefix; repeated `alcid=` / `alcdelay=` are cleaned then the new values appended.

## 4. DeviceProperties > Add > PciRoot(0x0)/Pci(0x1F,0x3)

| Key | Old value | New value | Type |
|---|---|---|---|
| `layout-id` | 11 | 15 | int → **data** `0f000000` |
| `alc-layout-id` | 11 | 15 | int → **data** `0f000000` |

- Must be **data type** (4-byte little-endian `0f 00 00 00`), not integer — a community-verified detail.
- The `alcid=` boot-arg has highest priority; even if these properties are wrong, `alcid=15` still overrides. Both are changed for safety.

## 5. Change List (machine-readable)

See [../02-efi-oc/config/config-changes.md.en.md](../02-efi-oc/config/config-changes.md.en.md), containing each item's path, old value, new value, type, and validation condition.

## 6. Safety Mechanisms

The deploy script `deploy_sn6140.py` has built in:

1. **Pre-check**: verifies source kext BundleID, version tag, SN6140 string, preventing picking the wrong official version.
2. **Automatic backup**: before writing, backs up config.plist and AppleALC.kext to `EFI/OC/backups/sn6140-audio-<timestamp>/` and generates restore.sh.
3. **Atomic writes**: kext written to `.new` then renamed into place; config written to a temp file and only overwritten after validation.
4. **Post-write verification**: reloads config and validates `alcid=15`/`alcdelay=1000`/kext enabled/SimpleHDA disabled, and confirms kext binary tag.
5. **One-click rollback**: `--rollback` restores from the latest backup.

## 7. Note on Dual EFI Partitions

This machine once had **two EFI partitions**: the main disk `disk0s1` (what actually boots) and the Install macOS USB EFI. Always deploy to the **main disk** one. The script auto-detects `/Volumes/EFI*` when the default path is unavailable, but when multiple points are mounted, using `--esp` explicitly is still recommended.
