# 02-efi-oc · Hackintosh EFI/OC Configuration Project

> English version of [README.md](README.md).

This directory is the OpenCore configuration project needed to make the SN6140 sound card work; its core is a one-click deploy script with backup/rollback.

## Files

| File | Description |
|---|---|
| `deploy_sn6140.py` | ★ One-click deploy/check/dry-run/rollback script |
| `config/config-changes.md.en.md` | machine-readable list of config.plist changes |
| `backup/README.md.en.md` | backup and rollback mechanism description |
| `../kexts/applealc-sn6140/AppleALC.kext` | deployment source kext (the script reads from here, under project-root kexts/) |

## Quick Use

```bash
cd 02-efi-oc

python3 deploy_sn6140.py --check      # read-only check of current EFI state
python3 deploy_sn6140.py --dry-run    # dry-run the changes
python3 deploy_sn6140.py              # actual deploy (auto backup)
python3 deploy_sn6140.py --rollback   # rollback
python3 deploy_sn6140.py --esp "/Volumes/EFI 1"   # specify EFI mount point
```

## The 5 Things the Script Does

1. Back up config.plist + AppleALC.kext to `EFI/OC/backups/sn6140-audio-<timestamp>/`
2. Replace `EFI/OC/Kexts/AppleALC.kext` with the custom kext
3. boot-args: `alcid=11` → `alcid=15 alcdelay=1000`
4. HDEF (`PciRoot(0x0)/Pci(0x1F,0x3)`) `layout-id`/`alc-layout-id`: int 11 → data 15
5. Disable `SimpleHDA.kext` (conflict)

All changes feature atomic writes, post-write verification, and one-click rollback. For detailed rationale see [../docs/03-OpenCore配置说明.md.en.md](../docs/03-OpenCore配置说明.md.en.md).

## Important Notes

- This machine has two EFI partitions: main disk (disk0s1) and Install macOS USB. Always deploy to the **main disk** one. The script auto-detects, but when multiple points are mounted, using `--esp` explicitly is recommended.
- The EFI partition must be mounted first (Disk Utility / `diskutil mount disk0s1`).
- Changes take effect only after reboot; verification see [../docs/05-部署验证与回滚.md.en.md](../docs/05-部署验证与回滚.md.en.md).
