# config.plist 变更清单（机器可读）

本文件精确记录 `deploy_sn6140.py` 对 OpenCore `config.plist` 的每一处改动，供审阅/手工核对。

## 变更项总表

| # | 配置路径 | 键 | 原值 | 新值 | 类型 | 校验条件 |
|---|---|---|---|---|---|---|
| 1 | Kernel > Add | `Lilu.kext`.Enabled | true | true（保持） | bool | 必须排在 AppleALC 之前 |
| 2 | Kernel > Add | `AppleALC.kext`.Enabled | true | true（保持） | bool | 存在且启用 |
| 3 | Kernel > Add | `SimpleHDA.kext`.Enabled | true | **false** | bool | 必须为 false |
| 4 | NVRAM > Add > `7C436110-AB2A-4BBB-A880-FE41995C9F82` | `boot-args` | 含 `alcid=11` | `alcid=15 alcdelay=1000 alcapplid=15` | string | 三个 token 都必须存在 |
| 5 | DeviceProperties > Add > `PciRoot(0x0)/Pci(0x1F,0x3)` | `layout-id` | int 11 | **data** `0f000000` | data | = bytes([15,0,0,0]) |
| 6 | DeviceProperties > Add > `PciRoot(0x0)/Pci(0x1F,0x3)` | `alc-layout-id` | int 11 | **data** `0f000000` | data | = bytes([15,0,0,0]) |

## 文件级变更

| 路径 | 原值 | 新值 |
|---|---|---|
| `EFI/OC/Kexts/AppleALC.kext` | 官方 1.9.8 / `REL-198-2026-09-27` | 定制 1.9.9 / `DBG-199-2026-10-26`（含 SN6140） |

## boot-args 处理细节

脚本按前缀去重，移除所有 `alcid=*`、`alcdelay=*` 和 `alcapplid=*` token，再追加：

```
alcid=15 alcdelay=1000 alcapplid=15
```

`alcapplid` 的作用：AppleALC 用 `alc-layout-id`（=15）选择并注入 SN6140 资源，但报给 AppleHDA 的 layout-id 默认由 Lilu 设为 7（`DefaultReportedLayoutId`）。缺 `alcapplid=15` 时 AppleHDA 加载内置 layout 7，只暴露 1 个内建麦克风 + 1 个耳机输出，看不到耳机麦端口。

其余参数（如 `-vi2c-force-polling`、`-ngreentglwithgfx`、`amfi_get_out_of_my_way=1` 等 ngreen EFI 原有参数）全部保留不变。

## 校验逻辑（validate）

部署后脚本会断言：

1. boot-args 含 `alcid=15`、`alcdelay=1000` 和 `alcapplid=15`
2. `Kernel > Add` 里有 `AppleALC.kext` 且 Enabled=True
3. `SimpleHDA.kext` 若存在则必须 Enabled=False
4. 写后重新读取 config + 检查 kext 二进制含 `DBG-199-2026-10-26`

任一不满足 → 报错退出，不会留下半配置状态。
