# 在 Linux 下采集 SN6140 硬件信息

## 为什么需要这一步

到现在为止，我们改的 pin 配置已经被 AppleHDA 正确加载（`ConfigData` 已是完整 72 字节、`layout-id=15`），但系统依然只暴露 `InternalMic` + `Headphones` 两个端点。这说明问题不在 AppleALC 配置，而在**这份社区 layout 资源与本机真实硬件的通路定义不匹配**——它照搬自 CS8409/CX8070，耳麦通路（NID、ADC、Widget 连接）未必对应你这台机器。

要精确重做，必须知道本机 SN6140 的真实引脚定义。Linux 内核驱动会把这些数据完整导出，这是唯一可靠的来源。

另一个重要背景：**SN6140 是 SoundWire 架构的 codec**。如果麦克风实际走 SoundWire 总线而非传统 HDA 引脚，那么 macOS 的 AppleHDA 根本看不到它——这是架构层面的限制，任何 AppleALC 配置都无法绕过。这次采集也会确认这一点。

## 怎么做（约 5 分钟）

### 1. 准备一个 Linux Live U 盘

任意发行版都行（Ubuntu / Fedora / Debian Live），用 Rufus 或 `dd` 做成启动盘。已装 Linux 双系统的可以直接跳过这步。

### 2. 从 U 盘启动

开机按 F12 / F11 / Esc（视主板而定）选 U 盘启动，选择「Try Linux / 试用」进入桌面（**不要安装**）。

### 3. 运行导出脚本

把工程里的 `03-tools/dump_codec_linux.sh` 复制到 Linux 里（U 盘、手机传文件都行），然后打开终端：

```bash
cd <脚本所在目录>
chmod +x dump_codec_linux.sh
./dump_codec_linux.sh
```

脚本会把结果打包成 `sn6140-linux-dump-<日期时间>.tar.gz`。

### 4. 把 tar.gz 传给我

把这个文件放到 U 盘或传到网盘，发给我。我会据此：
- 确认每个 NID 的真实设备类型（耳机 / 耳麦 / 内建麦 / 扬声器）
- 确认耳麦的 ADC 与 Widget 连接路径
- 判断麦克风是否走 SoundWire（若是，则明确告知 macOS 侧能否实现）
- 重做 layout / Platforms / PinConfig，并给出结论

## 脚本会采集什么

| 文件 | 内容 | 用途 |
|------|------|------|
| `00-system.txt` | 内核版本、发行版 | 匹配驱动行为 |
| `01-lspci.txt` | PCI 声卡与 SoundWire 控制器 | 确认 codec 与总线 |
| `02-asound-cards.txt` | ALSA 声卡列表 | 确认驱动是否识别 |
| `codecs/*` | **HDA codec dump（最关键）** | 每个引脚的默认配置、Widget 连接 |
| `03-soundwire.txt` | SoundWire sysfs 设备树 | SN6140 总线拓扑 |
| `04-dmesg-audio.txt` | 内核音频日志 | 驱动初始化过程 |
| `05-modules.txt` | 音频模块与固件 | 确认加载的驱动 |

## 如果脚本报错

- 脚本故意允许部分命令失败（SoundWire 机器上 `codec#*` 文件本就不存在，属正常）
- 只要生成了 `tar.gz`，就是可用的；缺哪部分我都会告诉你
- 若完全没有产出文件，直接把终端报错截图发我

## 英文版

见 `07-Linux采集说明.md.en.md`。
