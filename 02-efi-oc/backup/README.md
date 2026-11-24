# 备份与回滚说明

## 自动备份

`deploy_sn6140.py` 每次实际部署前，会在 EFI 分区创建备份目录：

```
EFI/OC/backups/sn6140-audio-<YYYYMMDD-HHMMSS>/
├── config.plist        # 部署前的原始配置（alcid=11、SimpleHDA 启用、官方 kext）
├── AppleALC.kext/      # 部署前的官方版 AppleALC（REL-198）
└── restore.sh          # 一键恢复脚本
```

本机已存在的备份：`sn6140-audio-20261124-121612`

## 回滚方式

### 方式 A：脚本回滚

```bash
cd 02-efi-oc
python3 deploy_sn6140.py --rollback
```

脚本会自动找到最新的 `sn6140-audio-*` 备份目录并恢复。

### 方式 B：restore.sh

```bash
sh /Volumes/EFI/EFI/OC/backups/sn6140-audio-20261124-121612/restore.sh /Volumes/EFI
```

restore.sh 内容：

```sh
#!/bin/sh
set -e
ESP="${1:-/Volumes/EFI}"
cp "$(dirname "$0")/config.plist" "$ESP/EFI/OC/config.plist"
rm -rf "$ESP/EFI/OC/Kexts/AppleALC.kext"
cp -R "$(dirname "$0")/AppleALC.kext" "$ESP/EFI/OC/Kexts/"
echo "已回滚，重启生效"
```

两种方式都需**重启**后生效。

## 本目录

本目录（`02-efi-oc/backup/`）用于说明备份机制；实际的备份产物位于 EFI 分区的 `EFI/OC/backups/` 下，不在本工程目录内。
