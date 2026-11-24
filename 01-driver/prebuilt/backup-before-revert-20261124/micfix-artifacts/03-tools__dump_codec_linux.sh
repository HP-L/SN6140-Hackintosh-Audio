#!/bin/bash
# SN6140 codec 信息一键导出脚本（在 Linux 下运行）
# 用法: chmod +x dump_codec_linux.sh && ./dump_codec_linux.sh
# 产出: sn6140-linux-dump-<日期时间>.tar.gz，把它发给助手即可

set +e  # 允许部分命令失败（SoundWire 机器上 HDA codec 文件可能不存在）

OUT="sn6140-linux-dump-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
echo "导出到: $OUT/"

run() {
  # run <文件名> <命令...>
  local f="$1"; shift
  echo "  -> $f"
  { echo "### $*"; echo "### $(date)"; "$@" 2>&1; } > "$OUT/$f" 2>&1
}

echo "[1/7] 系统基本信息"
run 00-system.txt          bash -c 'uname -a; echo ---; cat /etc/os-release; echo ---; date'

echo "[2/7] PCI 设备（声卡 / SoundWire 控制器）"
run 01-lspci.txt           bash -c 'lspci -nn 2>/dev/null | grep -iE "audio|sound|multimedia|1f87|14f1"; echo ===; lspci -nnk 2>/dev/null | grep -iE -A6 "audio device|soundwire|multimedia controller"'

echo "[3/7] ALSA 声卡列表"
run 02-asound-cards.txt    bash -c 'cat /proc/asound/cards 2>/dev/null; echo ===; cat /proc/asound/pcm 2>/dev/null; echo ===; ls -l /dev/snd/ 2>/dev/null'

echo "[4/7] HDA codec dump（关键！每台 card 每个 codec 都要）"
mkdir -p "$OUT/codecs"
codec_count=0
for f in /proc/asound/card*/codec#*; do
  [ -f "$f" ] || continue
  codec_count=$((codec_count+1))
  name=$(echo "$f" | tr '/#' '__')
  echo "  -> codecs/$name"
  cp "$f" "$OUT/codecs/$name" 2>/dev/null
done
if [ "$codec_count" -eq 0 ]; then
  echo "  (未找到 /proc/asound/card*/codec#* — 这是 SoundWire 机器的常见情况，属正常)"
  echo "  没有 HDA codec 节点，说明麦克风很可能走 SoundWire 总线，请务必完成第 5/6 步" > "$OUT/codecs/NONE-SoundWire系统说明.txt"
fi

echo "[5/7] SoundWire sysfs（SN6140 是 SoundWire codec，这一步很重要）"
run 03-soundwire.txt       bash -c '
  echo "=== /sys/bus/soundwire/devices ==="
  find /sys/bus/soundwire/devices -maxdepth 2 -type f 2>/dev/null | while read f; do
    echo "--- $f"; cat "$f" 2>/dev/null
  done
  echo "=== /sys/bus/soundwire/drivers ==="
  ls -R /sys/bus/soundwire/drivers 2>/dev/null
'

echo "[6/7] 内核日志（音频/SoundWire/Conexant 相关）"
run 04-dmesg-audio.txt     bash -c 'dmesg 2>/dev/null | grep -iE "snd|soundwire|sdw|conexant|cortex|cx[0-9]|sn61|alc|codec|audio" | tail -300'

echo "[7/7] 已加载音频模块 / 拓扑"
run 05-modules.txt         bash -c 'lsmod 2>/dev/null | grep -iE "snd|soundwire|sdw"; echo ===; find /lib/firmware -maxdepth 3 -type f 2>/dev/null | grep -iE "sn61|cx[0-9]|conexant|soundwire|sdw" | head -100'

# 打包
tar czf "$OUT.tar.gz" "$OUT" 2>/dev/null
echo ""
echo "============================================"
echo "完成！产出: $(pwd)/$OUT.tar.gz"
echo ""
echo "请把这个 tar.gz 发给助手。里面包含:"
echo "  - 00-system.txt        系统版本"
echo "  - 01-lspci.txt         PCI 声卡/SoundWire 控制器"
echo "  - 02-asound-cards.txt  ALSA 声卡"
echo "  - codecs/*             HDA codec dump（若存在）"
echo "  - 03-soundwire.txt     SoundWire 设备树（关键）"
echo "  - 04-dmesg-audio.txt   内核音频日志"
echo "  - 05-modules.txt       驱动模块与固件"
echo "============================================"
