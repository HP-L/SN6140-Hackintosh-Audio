# 01-driver · 声卡驱动代码工程

本目录是 SN6140 声卡的驱动代码工程，包含 Linux 参考源码、AppleALC 定制源码（可复现编译）、已校验的编译产物。

## 目录说明

| 路径 | 说明 |
|---|---|
| `linux-reference/senarytech.c` | Linux 主线 Senarytech HDA 驱动（注意：主线是 SN6186 `0x1fa86186`，非本机 SN6140） |
| `linux-reference/conexant.c` | Linux Conexant HDA 驱动，SN6140/SN6180 早期在此注册 |
| `checksums/SHA256SUMS.txt` | 社区 Release 的 SHA256 校验清单（历史版本） |
| `checksums/SHA256SUMS-micfix.txt` | 麦克风修复版 kext / 资源的 SHA256 校验清单 |
| `prebuilt/AppleALC.kext` | ★ 已校验的定制版 kext（版本 1.9.9 / `DBG-199-2026-10-26`），**含 2026-11-24 麦克风修复，实际部署用这个** |
| `prebuilt/backup-pre-micfix/` | 修复前 kext 与资源备份，可手动回滚 |
| `source/` | 完整 AppleALC 源码快照 + 依赖 + 编译脚本 + 已编译目标文件 |

## 核心：SN6140 layout 资源

`source/Resources/SN6140/`：

- `layout15.xml` / `layout15.xml.zlib` —— SN6140 的 layout 15 配置（verb/pin/widget）；2026-11-24 起输入端点为 `Mic` + `ExtMic`
- `Platforms15.xml` / `Platforms15.xml.zlib` —— 平台节点配置
- `Info.plist` —— codec 元信息

这些资源在编译时被 `ResourceConverter` 打包进 `AppleALC/kern_resources.cpp`，最终内嵌到 kext 二进制中。

## 编译

见 [`source/build.sh`](source/build.sh) 与 [../docs/04-编译指南.md](../docs/04-编译指南.md)。

```bash
cd source && bash build.sh
```

> ⚠️ 本机只有 Command Line Tools（clang 17），最终链接因 linker 版本问题失败；9 个目标文件已成功编译。完整编译需 Xcode 16.4。实际部署使用 `prebuilt/AppleALC.kext`（社区已校验产物）。

## 为什么 Linux 源码只是参考

Linux 的 ALSA HDA 驱动与 macOS AppleHDA 架构完全不同，不能直接移植成 kext。本工程借鉴的是它对 codec 的识别与配置思路，真正让声卡工作的是 AppleALC 的 layout 配置数据。详见 [../docs/02-技术路线.md](../docs/02-技术路线.md)。
