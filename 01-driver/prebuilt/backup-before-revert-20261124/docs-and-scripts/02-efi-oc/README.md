# 02-efi-oc · 黑苹果 EFI/OC 配置工程

本目录是让 SN6140 声卡工作所需的 OpenCore 配置工程，核心是一个带备份/回滚的一键部署脚本。

## 文件说明

| 文件 | 说明 |
|---|---|
| `deploy_sn6140.py` | ★ 一键部署/检查/预演/回滚脚本 |
| `config/config-changes.md` | config.plist 逐项变更清单（机器可读） |
| `backup/README.md` | 备份与回滚机制说明 |
| `../kexts/applealc-sn6140/AppleALC.kext` | 部署源 kext（脚本从这里读取，位于工程根 kexts/ 下） |

## 快速使用

```bash
cd 02-efi-oc

python3 deploy_sn6140.py --check      # 只读检查当前 EFI 状态
python3 deploy_sn6140.py --dry-run    # 预演改动
python3 deploy_sn6140.py              # 实际部署（自动备份）
python3 deploy_sn6140.py --rollback   # 回滚
python3 deploy_sn6140.py --esp "/Volumes/EFI 1"   # 指定 EFI 挂载点
```

## 脚本做的 5 件事

1. 备份 config.plist + AppleALC.kext 到 `EFI/OC/backups/sn6140-audio-<时间戳>/`
2. 用定制版 kext 替换 `EFI/OC/Kexts/AppleALC.kext`
3. boot-args：`alcid=11` → `alcid=15 alcdelay=1000`
4. HDEF (`PciRoot(0x0)/Pci(0x1F,0x3)`) 的 `layout-id`/`alc-layout-id`：int 11 → data 15
5. 禁用 `SimpleHDA.kext`（冲突）

全部改动带原子写入、写后验证、一键回滚。详细原理见 [../docs/03-OpenCore配置说明.md](../docs/03-OpenCore配置说明.md)。

## 重要提醒

- 本机有主盘 EFI（disk0s1）和安装U盘 EFI 两块，务必部署到**主盘**那块。脚本会自动探测，但多挂载点时建议用 `--esp` 明确指定。
- EFI 分区需先挂载（磁盘工具 / `diskutil mount disk0s1`）。
- 部署后重启才生效，验证见 [../docs/05-部署验证与回滚.md](../docs/05-部署验证与回滚.md)。
