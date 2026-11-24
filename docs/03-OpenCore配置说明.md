# 03 · OpenCore 配置说明

本工程的 OC 配置由脚本自动修改，全部集中在 `EFI/OC/config.plist` 与 `EFI/OC/Kexts/`。以下逐项说明每处改动的位置、值和原理。

## 0. 路径约定

- `config.plist` 为 XML 格式。
- ESP 挂载点默认 `/Volumes/EFI`，本机实际路径 `EFI/OC/`。
- 本机主板是 Intel HDA 控制器，设备路径 `PciRoot(0x0)/Pci(0x1F,0x3)`（HDEF@1F,3）。

## 1. kext 替换

| 项 | 原值 | 新值 |
|---|---|---|
| `EFI/OC/Kexts/AppleALC.kext` | 官方 `REL-198-2026-09-27`（1.9.8，不含 SN6140） | 定制 `DBG-199-2026-10-26`（1.9.9，含 SN6140） |

验证身份：

```bash
strings -a EFI/OC/Kexts/AppleALC.kext/Contents/MacOS/AppleALC | grep -E 'DBG-199|SN6140'
```

## 2. Kernel > Add（kext 注入顺序与启用状态）

| BundlePath | 要求 | 原因 |
|---|---|---|
| `Lilu.kext` | Enabled=True，排在 AppleALC **之前** | AppleALC 是 Lilu 插件，依赖 Lilu 先加载 |
| `AppleALC.kext` | Enabled=True | 注入定制驱动 |
| `SimpleHDA.kext` | **Enabled=False** | 与 AppleALC 抢同一 HDA 控制器，会冲突，必须禁用 |

> `SimpleHDA.kext` 文件仍保留在 Kexts 目录，仅在 config 里禁用（不删文件，便于回滚）。

## 3. NVRAM > Add > 7C436110-AB2A-4BBB-A880-FE41995C9F82

### boot-args

```
原: ... alcid=11
新: ... alcid=15 alcdelay=1000
```

- `alcid=15`：告诉 AppleALC 用 layout 15（SN6140 的验证配置）。
- `alcdelay=1000`：延迟 1000ms，给 codec 上电/初始化留时间，避免部分机器注入过早失效。
- 脚本按前缀去重，重复的 `alcid=` / `alcdelay=` 会被清理后追加新值。

## 4. DeviceProperties > Add > PciRoot(0x0)/Pci(0x1F,0x3)

| 键 | 原值 | 新值 | 类型 |
|---|---|---|---|
| `layout-id` | 11 | 15 | int → **data** `0f000000` |
| `alc-layout-id` | 11 | 15 | int → **data** `0f000000` |

- 必须是 **data 类型**（4 字节小端 `0f 00 00 00`），不是 integer——这是社区验证过的细节。
- `alcid=` boot-arg 优先级最高，即使这里的属性没改对，`alcid=15` 也能覆盖生效；两者都改是为了稳妥。

## 5. 变更清单（机器可读版）

见 [../02-efi-oc/config/config-changes.md](../02-efi-oc/config/config-changes.md)，含每项的路径、原值、新值、类型、校验条件。

## 6. 安全机制

部署脚本 `deploy_sn6140.py` 内置：

1. **前置校验**：检查源 kext 的 BundleID、版本标记、SN6140 字符串，防止拿错官方版。
2. **自动备份**：写入前把 config.plist 和 AppleALC.kext 备份到 `EFI/OC/backups/sn6140-audio-<时间戳>/`，并生成 restore.sh。
3. **原子写入**：kext 先写 `.new` 再 rename 替换；config 先写临时文件、校验通过才覆盖。
4. **写后验证**：重新加载 config 校验 `alcid=15`/`alcdelay=1000`/kext 启用/SimpleHDA 禁用，并确认 kext 二进制标记。
5. **一键回滚**：`--rollback` 从最新备份恢复。

## 7. 双 EFI 分区注意

本机曾有**两块 EFI 分区**：主硬盘 `disk0s1`（开机真正读取）和 Install macOS U 盘的 EFI。务必部署到**主硬盘**那块。脚本会在默认路径不可用时自动探测 `/Volumes/EFI*`，但多挂载点时仍建议用 `--esp` 明确指定。
