# config.plist Change List (Machine-Readable)

> English version of [config-changes.md](config-changes.md).

This file precisely records every change `deploy_sn6140.py` makes to the OpenCore `config.plist`, for review/manual cross-checking.

## Summary of Changes

| # | Config path | Key | Old value | New value | Type | Validation condition |
|---|---|---|---|---|---|---|
| 1 | Kernel > Add | `Lilu.kext`.Enabled | true | true (kept) | bool | must come before AppleALC |
| 2 | Kernel > Add | `AppleALC.kext`.Enabled | true | true (kept) | bool | present and enabled |
| 3 | Kernel > Add | `SimpleHDA.kext`.Enabled | true | **false** | bool | must be false |
| 4 | NVRAM > Add > `7C436110-AB2A-4BBB-A880-FE41995C9F82` | `boot-args` | contains `alcid=11` | `alcid=15 alcdelay=1000 alcapplid=15` | string | all three tokens must be present |
| 5 | DeviceProperties > Add > `PciRoot(0x0)/Pci(0x1F,0x3)` | `layout-id` | int 11 | **data** `0f000000` | data | = bytes([15,0,0,0]) |
| 6 | DeviceProperties > Add > `PciRoot(0x0)/Pci(0x1F,0x3)` | `alc-layout-id` | int 11 | **data** `0f000000` | data | = bytes([15,0,0,0]) |

## File-Level Changes

| Path | Old value | New value |
|---|---|---|
| `EFI/OC/Kexts/AppleALC.kext` | official 1.9.8 / `REL-198-2026-09-27` | custom 1.9.9 / `DBG-199-2026-10-26` (with SN6140) |

## boot-args Handling Details

The script de-duplicates by prefix, removes all `alcid=*`, `alcdelay=*` and `alcapplid=*` tokens, then appends:

```
alcid=15 alcdelay=1000 alcapplid=15
```

`alcapplid` purpose: AppleALC uses `alc-layout-id` (=15) to select and inject the SN6140 resources, but the layout-id reported to AppleHDA defaults to 7 in Lilu (`DefaultReportedLayoutId`). Without `alcapplid=15`, AppleHDA loads the built-in layout 7 and exposes only 1 internal mic + 1 headphone, with no headset-mic port.

All other parameters (such as ngreen EFI originals `-vi2c-force-polling`, `-ngreentglwithgfx`, `amfi_get_out_of_my_way=1`, etc.) are preserved unchanged.

## Validation Logic (validate)

After deployment the script asserts:

1. boot-args contain `alcid=15`, `alcdelay=1000` and `alcapplid=15`
2. `Kernel > Add` contains `AppleALC.kext` with Enabled=True
3. `SimpleHDA.kext`, if present, must have Enabled=False
4. post-write reload of config + check that kext binary contains `DBG-199-2026-10-26`

If any fails → error exit, no half-configured state is left behind.
