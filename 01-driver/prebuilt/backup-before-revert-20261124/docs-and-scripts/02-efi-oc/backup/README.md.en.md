# Backup and Rollback

> English version of [README.md](README.md).

## Automatic Backup

Before each actual deployment, `deploy_sn6140.py` creates a backup directory on the EFI partition:

```
EFI/OC/backups/sn6140-audio-<YYYYMMDD-HHMMSS>/
├── config.plist        # original config before deploy (alcid=11, SimpleHDA enabled, official kext)
├── AppleALC.kext/      # official AppleALC before deploy (REL-198)
└── restore.sh          # one-click restore script
```

Existing backup on this machine: `sn6140-audio-20261124-121612`

## Rollback Methods

### Method A: Script rollback

```bash
cd 02-efi-oc
python3 deploy_sn6140.py --rollback
```

The script automatically finds the latest `sn6140-audio-*` backup directory and restores it.

### Method B: restore.sh

```bash
sh /Volumes/EFI/EFI/OC/backups/sn6140-audio-20261124-121612/restore.sh /Volumes/EFI
```

restore.sh contents:

```sh
#!/bin/sh
set -e
ESP="${1:-/Volumes/EFI}"
cp "$(dirname "$0")/config.plist" "$ESP/EFI/OC/config.plist"
rm -rf "$ESP/EFI/OC/Kexts/AppleALC.kext"
cp -R "$(dirname "$0")/AppleALC.kext" "$ESP/EFI/OC/Kexts/"
echo "Rolled back, effective after reboot"
```

Both methods require a **reboot** to take effect.

## This Directory

This directory (`02-efi-oc/backup/`) documents the backup mechanism; the actual backup artifacts live under the EFI partition's `EFI/OC/backups/`, not inside this project directory.
