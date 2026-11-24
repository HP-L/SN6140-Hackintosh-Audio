# SN6140 黑苹果声卡驱动工程

> 让 Senarytech **SN6140**（`0x14f1:1f87`）HD Audio Codec 在黑苹果（OpenCore / macOS 15 Sequoia）上正常出声的完整解决方案。
> 包含：硬件诊断结论、AppleALC 定制 kext 源码与编译工程、OpenCore 配置与一键部署脚本、完整文档。

---

## 〇、极简配置（拿来就用，4 步搞定）

> 只想让声卡出声？按下面 4 步做，重启即可。原理和其他细节往下看。

**第 1 步 · 挂载 EFI**
打开「磁盘工具」，挂载主硬盘上的 **EFI** 分区（通常是 `disk0s1`，挂载后路径 `/Volumes/EFI`）。

**第 2 步 · 部署（两种方式任选其一）**

**方式 A｜脚本一键部署（推荐，自带备份，出问题可回滚）**

打开「终端」，粘贴执行：

```bash
cd /Users/doro/WorkBuddy/2026-11-24-11-32-31/SN6140-Hackintosh-Audio/02-efi-oc
python3 deploy_sn6140.py
```

看到 `✅ 部署完成` 即成功。

**方式 B｜手动配置（不用脚本）**

用 Finder 和任意 plist 编辑器（如 PlistEdit Pro / Xcode / OpenCore Configurator）完成两件事：

1. **替换 kext**：把工程里 `kexts/applealc-sn6140/AppleALC.kext` 复制到 EFI 分区的 `EFI/OC/Kexts/`，覆盖原文件。（建议先把原 kext 复制一份留作备份）
2. **改 `EFI/OC/config.plist`**，共 4 处：
   - `NVRAM → Add → 7C436110-AB2A-4BBB-A880-FE41995C9F82 → boot-args`：把 `alcid=11` 改成 `alcid=15`，并在末尾加 `alcdelay=1000` 和 `alcapplid=15`（`alcapplid` 让报给 AppleHDA 的 layout-id 也是 15，**否则只会显示内建麦克风、看不到耳机端口**）
   - `DeviceProperties → Add → PciRoot(0x0)/Pci(0x1F,0x3)` 下的 `layout-id` 和 `alc-layout-id`：类型改为 **Data**，值填 `0F000000`（即 15）
   - `Kernel → Add` 中的 `SimpleHDA.kext`：把 `Enabled` 改为 `false`
   - 确认 `Lilu.kext` 排在 `AppleALC.kext` **前面**

   详细原理和每一项的路径见 [02-efi-oc/config/config-changes.md](02-efi-oc/config/config-changes.md)。

> 两种方式效果完全相同，改完都直接进第 3 步重启。手动方式请务必自己备份原 config.plist。

**第 3 步 · 重启电脑**
关机重启，OpenCore 会自动加载定制声卡驱动。

**第 4 步 · 验证出声**
重启后进系统，打开「系统设置 → 声音」应看到输出/输入设备；或终端执行：

```bash
bash /Users/doro/WorkBuddy/2026-11-24-11-32-31/SN6140-Hackintosh-Audio/03-tools/verify_audio.sh
```

> ⚠️ 第一次播放先把**音量调到最低**，确认无刺耳噪声再调高。
> 出问题回滚：`python3 deploy_sn6140.py --rollback`（在 `02-efi-oc` 目录下执行），重启即可还原。

---

## 一、工程一句话说明

本机实测声卡是 **SN6140**，不是最初以为的 SN6180。官方 AppleALC 不支持这颗 codec，导致 AppleHDA 已加载但驱动不匹配、系统无声。
解决方案是采用社区验证过的 **SN6140 定制版 AppleALC（layout 15）**，通过 OpenCore 注入 kext + 修正 boot-args / layout-id 让原生 AppleHDA 驱动它——扬声器、耳机、麦克风、热插拔均可用。

> 📌 **2026-11-24 更新**：已修复麦克风端点。原资源把耳麦插孔引脚 NID `0x19` 配成非麦克风（Default Device `0x8`），且输入端点标成 Line In；现已改为 `0x00A11030`（Mic）并命名为 `ExtMic`。详见 [06-麦克风修复说明](docs/06-麦克风修复说明.md)。重新运行一键部署脚本并重启即可获得修复版。

---

## 二、目录结构

```
SN6140-Hackintosh-Audio/
├── README.md                        ← 你正在看（工程总入口）
├── docs/                            ← 完整文档
│   ├── 01-硬件诊断与结论.md           实测 codec ID、为何不是 SN6180、故障根因
│   ├── 02-技术路线.md                 为何选 AppleALC 注入而非移植 ALSA 代码
│   ├── 03-OpenCore配置说明.md         每一处 config 改动的原理与位置
│   ├── 04-编译指南.md                 源码结构、编译步骤、已知限制
│   ├── 05-部署验证与回滚.md           部署脚本用法、验证命令、回滚
│   └── 06-麦克风修复说明.md           NID 0x19 引脚配置 + ExtMic 端点修复
├── 01-driver/                       ← 声卡驱动代码工程
│   ├── linux-reference/              Linux 内核参考驱动（senarytech.c / conexant.c）
│   ├── source/                       完整 AppleALC 源码快照（可复现编译）
│   │   ├── Resources/SN6140/         ★ 核心：layout15.xml / Platforms15.xml（zlib 压缩）
│   │   ├── AppleALC/                 AppleALC 源码（含生成的 kern_resources.cpp）
│   │   ├── build.sh                  命令行编译脚本
│   │   ├── build_objs/               已编译目标文件（.o）
│   │   ├── MacKernelSDK/             编译依赖：内核头文件与库
│   │   ├── Lilu.kext/                编译依赖：Lilu 开发头文件
│   │   └── ResourceConverter/        资源打包工具（XML→zlib→内嵌数组）
│   ├── prebuilt/AppleALC.kext        ★ 已校验的定制版 kext 产物（可直接部署，含麦克风修复）
│   ├── prebuilt/backup-pre-micfix/   修复前 kext / 资源备份（手动回滚用）
│   └── checksums/SHA256SUMS-micfix.txt  麦克风修复版 SHA256 校验值
├── kexts/                           ← 部署源（脚本读取此处）
│   └── applealc-sn6140/AppleALC.kext  （与 prebuilt 同源，供 deploy 脚本使用）
├── 02-efi-oc/                       ← 黑苹果 EFI/OC 配置工程
│   ├── deploy_sn6140.py             ★ 一键部署/回滚脚本（--check/--dry-run/--rollback）
│   ├── config/config-changes.md      config.plist 逐项变更清单
│   └── backup/                       回滚脚本模板说明
├── 03-tools/                        ← 辅助工具
│   └── verify_audio.sh              重启后一键验证脚本
└── (工作记录见工作区 .workbuddy/memory/)
```

---

## 三、快速开始

### 1. 部署（EFI 已挂载时）

```bash
cd SN6140-Hackintosh-Audio/02-efi-oc

python3 deploy_sn6140.py --check      # 先看当前状态（只读）
python3 deploy_sn6140.py --dry-run    # 预演改动（只读）
python3 deploy_sn6140.py              # 实际部署（自动备份）
```

脚本默认 EFI 挂载点 `/Volumes/EFI`，若未挂载会自动探测其他 `/Volumes/EFI*`；也可用 `--esp /路径` 指定。

### 2. 重启后验证

```bash
bash ../03-tools/verify_audio.sh
```

或手动：

```bash
ioreg -r -n AppleALC -l -w0 | grep VersionInfo   # 期望 DBG-199-2026-10-26
system_profiler SPAudioDataType                  # 期望出现 内置扬声器/耳机/麦克风
```

### 3. 出问题回滚

```bash
python3 deploy_sn6140.py --rollback
```

---

## 四、关键事实速查

| 项目 | 值 |
|---|---|
| 机型 | Macmini8,1 / x86_64 黑苹果 |
| 系统 | macOS 15.8.1 (Sequoia) / Darwin 24.6.0 |
| 引导器 | OpenCore（ngreen EFI） |
| 声卡芯片 | **SN6140** = `0x14F11F87`（revision `0x100100`） |
| （对比）SN6180 | `0x14F120D1` —— 非本机芯片 |
| HDA 控制器路径 | `PciRoot(0x0)/Pci(0x1F,0x3)`（Intel HDEF） |
| 采用 layout-id | **15** |
| AppleALC 版本 | 定制版 1.9.9（`DBG-199-2026-10-26`） |
| 原版 AppleALC | 1.9.8（`REL-198-2026-09-27`）—— 不含 SN6140，无声 |
| 上游支持 | AppleALC 官方不支持 SN6140，需定制 |

---

## 五、来源与致谢

- SN6140 定制 AppleALC 源码与编译产物：`chenhggu6475/Senary-SN6140-AppleALC-Hackintosh`
- 同款硬件验证记录：`gqm321/macos15-rtx5070-jiaolong`
- Linux 内核 HDA 参考驱动：`torvalds/linux`（`sound/hda/codecs/senarytech.c`、`conexant.c`）
- AppleALC / Lilu / MacKernelSDK：acidanthera

编译产物 SHA256 已校验通过；社区已在同款 codec + 同款 macOS 上验证扬声器/麦克风/耳机热插拔全部工作。

---

## 六、文档导航

- 想了解**为什么这么做** → [02-技术路线](docs/02-技术路线.md)
- 想知道**芯片怎么识别的** → [01-硬件诊断与结论](docs/01-硬件诊断与结论.md)
- 想改 **OpenCore 配置** → [03-OpenCore配置说明](docs/03-OpenCore配置说明.md)
- 想自己**编译驱动** → [04-编译指南](docs/04-编译指南.md)
- 想**部署/验证/回滚** → [05-部署验证与回滚](docs/05-部署验证与回滚.md)
- 麦克风无效 / 想知道这次修了什么 → [06-麦克风修复说明](docs/06-麦克风修复说明.md)
