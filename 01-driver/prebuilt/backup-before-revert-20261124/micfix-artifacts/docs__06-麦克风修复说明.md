# 06 · 麦克风支持修复（2026-11-24）

## 1. 现象与定位

原版定制 AppleALC（layout 15）能让**扬声器和耳机出声**，但 macOS 的声音输入里通常只有一条无效的线路输入，耳机麦克风或内置麦克风无法录音。

根因有两处，都在资源配置里，不在内核代码：

| 位置 | 修复前 | 问题 |
|---|---|---|
| `PinConfigs.kext` → SN6140 / layout 15 的 `ConfigData` | NID `0x19` 引脚配置 = `0x00811030` | Default Device 字段是 `0x8`（Other/未定义），不是麦克风；这颗引脚就是耳机/耳麦插孔的麦克风脚 |
| `Resources/SN6140/layout15.xml` → `Inputs` | `Mic`, `LineIn` | 第二条输入路径（NID `0x19` → ADC `0x13`）被暴露成 Line In，而不是外接麦克风 |

Linux 主线 `sound/hda/codecs/conexant.c` 对 SN6140 有明确注释：

> In cx11880 and sn6140, the node 16 can only be configured to headphone or disabled, the node 19 can only be configured to microphone or disabled.

coreboot 的 SN6140 verb 表（`vendor_id=0x14f11f87`）同样把 **Port D / NID `0x19`** 配成 `0x04A19020 Headset Microphone`。因此本机把 `0x19` 配成 non-mic 是明确的资源错误。

本机 codec 身份复核：

```
IOHDACodecVendorID           = 351346567  (0x14F11F87  SN6140)
IOHDACodecFunctionSubsystemID = 351339323  (0x14F1033B)
```

## 2. 改了什么

### 2.1 引脚配置（关键修复）

`ConfigData` 中 NID `0x19` 的四个 verb：

```
修复前：01 97 1c 30  01 97 1d 10  01 97 1e 81  01 97 1f 00   → 0x00811030
修复后：01 97 1c 30  01 97 1d 10  01 97 1e A1  01 97 1f 00   → 0x00A11030
```

只把 Default Device 从 `0x8` 改成 `0xA`（Mic），其余字段保持不变：

- Jack / External
- 1/8" 连接、color 1
- Association 3、Sequence 0（与原配置一致，避免影响已有分组）

这是最小改动，不改已经验证可用的扬声器/耳机通路。

### 2.2 输入端点命名

`layout15.xml`：

```diff
 <key>Inputs</key>
 <array>
     <string>Mic</string>
-    <string>LineIn</string>
+    <string>ExtMic</string>
 </array>
```

对应的端点字典键也由 `<key>LineIn</key>` 改为 `<key>ExtMic</key>`；同时移除了该端点上非必需的 `DspNoiseReduction` 块，使压缩后的内嵌资源仍能放进原来的 322 字节槽位。内置麦克风（NID `0x1A` → ADC `0x14`）及其 DSP 设置保持不变。

### 2.3 同步更新的文件

- `01-driver/source/Resources/PinConfigs.kext/Contents/Info.plist`
- `01-driver/source/Resources/SN6140/layout15.xml`
- `01-driver/source/Resources/SN6140/layout15.xml.zlib` 与 `.zlib.md5`
- `01-driver/source/AppleALC/kern_resources.cpp`（内嵌 `file85` 数组）
- `kexts/applealc-sn6140/AppleALC.kext`（部署源）
- `01-driver/prebuilt/AppleALC.kext`（预编译产物）
- `01-driver/checksums/SHA256SUMS-micfix.txt`
- `01-driver/prebuilt/backup-pre-micfix/`（修复前备份，可手动回滚）

驱动版本标识仍是 `DBG-199-2026-10-26`，OpenCore 配置不需要改动。

## 3. 部署

EFI 未挂载时先在「磁盘工具」挂载主盘的 EFI 分区，然后执行：

```bash
cd /Users/doro/WorkBuddy/2026-11-24-11-32-31/SN6140-Hackintosh-Audio/02-efi-oc
python3 deploy_sn6140.py
```

脚本会自动备份 EFI 上当前的 `config.plist` 和 `AppleALC.kext`，再覆盖为麦克风修复版。重启后生效。

手动部署也可以：把 `kexts/applealc-sn6140/AppleALC.kext` 复制到 `EFI/OC/Kexts/` 覆盖原文件即可，`config.plist` 无需变化。

## 4. 验证

```bash
# 1) 驱动仍为预期版本
ioreg -r -n AppleALC -l -w0 | grep VersionInfo      # DBG-199-2026-10-26

# 2) 注入的引脚配置已更新
ioreg -r -c IOHDACodecDevice -l -w0 | grep -o '01971ea1'   # 有输出即修复版

# 3) 系统是否识别到麦克风输入
system_profiler SPAudioDataType | grep -i -E 'microphone|input|ExtMic|线路输入|麦克风'

# 4) 用 ffmpeg 列出并录制 5 秒（设备序号按实际改）
ffmpeg -f avfoundation -list_devices true -i ""
ffmpeg -f avfoundation -i ":1" -t 5 mic-test.wav
afinfo mic-test.wav | grep -i channels
```

也可以用「系统设置 → 声音 → 输入」或 QuickTime 录音做主观确认。首次测试请保持低音量。

一键脚本也可运行：

```bash
bash /Users/doro/WorkBuddy/2026-11-24-11-32-31/SN6140-Hackintosh-Audio/03-tools/verify_audio.sh
```

## 5. 回滚

```bash
cd /Users/doro/WorkBuddy/2026-11-24-11-32-31/SN6140-Hackintosh-Audio/02-efi-oc
python3 deploy_sn6140.py --rollback
```

或手动把 `01-driver/prebuilt/backup-pre-micfix/AppleALC.kext` 复制回 `EFI/OC/Kexts/`，重启。

## 6. 边界与后续

- 本修复基于 Linux/coreboot 对 SN6140 的公开 pin 定义，结合本机 IORegistry 实测身份推导；属于**最小安全改动**，未在 Windows 下逐针脚实测本机主板走线。
- 内置麦克风 NID `0x1A` 仍沿用 CX8070 的 `0x90A60020`（Mic / internal / conn type 6）。若内置麦克风仍无声，请提供 Linux 下的 `/proc/asound/card*/codec#*` dump 再决定是否改为 `0x90A70020` 或走 ADC `0x13`。
- 耳麦插孔的 CTIA/OMTP 识别在 Linux 里还依赖 vendor verb `0x3B0` 与插拔时动态 VREF；AppleALC 没有实现这一步。若耳机麦克风仍不稳定，可继续在 `ConfigData` 中追加 vendor verb，但需要实机录音验证。

## 7. 二次修复：alcapplid（2026-11-24，端口显示问题）

### 现象

第 1~5 节的资源修复部署后，重启仍只在「系统设置 → 声音 → 输入」看到 **内建麦克风**，没有耳机 / 耳机麦端口。

### 根因（IORegistry 实测）

```
IOAudioDeviceModelID      = "AppleHDA:7"
HDEF layout-id            = <07000000>   (7)
HDEF alc-layout-id        = <0f000000>   (15)
AppleHDAEngineInput 描述   = {"num-internal-mics"=1, "layout-id"=7}
输入 selector 可选值       = InternalMic（仅 1 个）
输出 selector 可选值       = Headphones（仅 1 个）
```

关键：AppleALC 自 1.2.8 起使用**两个** layout id：

| 参数 | 作用 | 当前值 |
|---|---|---|
| `alcid=15` / `alc-layout-id` | AppleALC **内部**用它选择并注入 SN6140 的 layout15 资源 | 15 ✓ |
| `alcapplid` / `apple-layout-id` | 报给 **AppleHDA** 的 layout-id，决定 AppleHDA 加载哪份资源 | 未设置 → **Lilu 默认 7** ✗ |

Lilu 源码 `kern_devinfo.hpp` 中 `DefaultReportedLayoutId = 7`。因为 boot-args 缺 `alcapplid`，AppleHDA 收到 layout-id=7，加载的是它**内置**的通用 layout 7（只有 1 个内建麦 + 1 个耳机输出），而不是我们注入的 SN6140 layout15（2 输入 + 2 输出）。这解释了为什么第 1~5 节改的 layout15 资源始终不生效。

注：`WakeConfigData`（8 字节短 verb）+ `WakeVerbReinit` 是 AppleALC 451 个条目共用的标准设计（供睡眠唤醒重初始化），**不是**本问题原因，无需修改。

### 修复

在 `NVRAM > Add > 7C4361... > boot-args` 追加：

```
alcapplid=15
```

现为 `alcid=15 alcdelay=1000 alcapplid=15`。`deploy_sn6140.py` 已更新：会自动写入并在 `--check` / `validate` 中校验 `alcapplid=15`，重复运行不会丢失。手动配置的用户需自行在 boot-args 加这一项。

### 诊断辅助（本次临时）

本次 boot-args 另加了 `-alcdbg -liludbg liludump=90`（kext 为 DBG 版），重启 90 秒后会把 AppleALC/Lilu 日志写到 `/var/log/`，用于确认资源注入路径。确认问题后应移除这三个调试参数。

### 验证

重启后执行：

```bash
# layout-id 应与 alc-layout-id 一致，都是 15
ioreg -r -c AppleHDAController -l -w0 | grep -i layout-id    # layout-id = <0f000000>

# 输入/输出 selector 应出现多个端点（Mic/ExtMic、IntSpeaker/Headphone）
ioreg -r -l -w0 | grep IOAudioSelectorControlSelectionDescriptionKey
```

### 回滚

```bash
# 恢复加 alcapplid 之前的 config
sudo cp /Volumes/EFI/EFI/OC/config.plist.bak-pre-alcapplid /Volumes/EFI/EFI/OC/config.plist
```

（备份路径以实际为准；`--rollback` 会回滚到上一次完整部署备份。）

## 8. 第二次重启后的真根因：WakeConfigData 短版覆盖了引脚配置

加 `alcapplid=15` 后 `layout-id` 已正确变成 15（`IOAudioDeviceModelID = AppleHDA:15`），但系统仍只有 `InternalMic` + `Headphones`。这说明第 7 节的判断也不完整。

### 实测证据

重启后从 IORegistry 读到的 `HDAConfigDefault`：

```
ConfigData     = <01770c0201670c02>          ← 只有 8 字节 / 2 个 verb
BootConfigData = <01771c10...01670c02>       ← 完整 72 字节 / 18 个 verb
alc-pinconfig-status = Yes
```

关键：短版只有 `0x0c`（Set Pin Control）verb，**没有任何 `0x1c`（Set Configuration Default）verb**。没有 `0x1c` 就等于没有给任何引脚写入默认设备类型，AppleHDA 只能沿用 BIOS/硬件默认值，于是只看到内建麦克风和耳机。

### 为什么会交换

AppleALC 源码 `kern_alc.cpp:803-808`：

```cpp
if (wakeConfigData != nullptr) {
    if (configData != nullptr)
        newConfig->setObject("BootConfigData", configData);
    newConfig->setObject("ConfigData", wakeConfigData);   // 短版变成实际生效配置
    newConfig->removeObject("WakeConfigData");
}
```

SN6140 条目原本带 `WakeConfigData=<01770c0201670c02>` + `WakeVerbReinit=True`，开机时 `patchPinConfig()` 执行了上述交换。第 6 节"WakeConfigData 是标准设计、不用改"的结论是**误判**：标准设计本身没错，但这**份社区资源的短版内容写得太少**，只够唤醒时重设引脚电源，不能作为启动配置使用。

### 修复

把 SN6140 条目的 `WakeConfigData` 改成与完整 `ConfigData` 相同的 72 字节。这样无论开机还是睡眠唤醒，`ConfigData` 都包含全部 18 个 verb（含 4 个引脚的 `0x1c` 默认值，其中 NID `0x19 = 0x00A11030` 为耳麦）。

已同步修改：
- `01-driver/source/Resources/PinConfigs.kext/Contents/Info.plist`
- `kexts/applealc-sn6140/AppleALC.kext/Contents/Info.plist`
- `01-driver/prebuilt/AppleALC.kext/Contents/Info.plist`

修复前备份在 `01-driver/prebuilt/backup-pre-wakefix/`，EFI 部署备份在 `EFI/OC/backups/sn6140-audio-20261124-155850/`。Mach-O 二进制未改动（SHA256 仍为 `3f37195b...`），只改了 `Info.plist` 里的引脚配置表。

### 验证

重启后运行：

```bash
ioreg -r -c IOHDACodecDevice -l -w0 | grep -A2 HDAConfigDefault
```

期望 `ConfigData` 和 `BootConfigData` **都是 72 字节**且包含 `01971ea1`。再检查 selector 是否出现 `ExtMic` / `IntSpeaker` 等端点。

### 如果仍然只有内建麦克风

那说明 AppleHDA 没有采用注入的 layout15 资源，需要拿到启动日志才能继续。当前环境 `log show` 不可用、`liludump` 也未生成文件，届时需要用物理机上的 Console.app 或 `sudo log show --last boot` 手动导出 AppleALC DBG 日志。
