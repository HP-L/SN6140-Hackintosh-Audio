#!/bin/bash
# SN6140 声卡重启后一键验证脚本
# 用法: bash verify_audio.sh

echo "============================================"
echo " SN6140 声卡驱动验证（含麦克风修复检查）"
echo "============================================"

echo ""
echo "[1/7] AppleALC 版本（期望 DBG-199-2026-10-26）"
ioreg -r -n AppleALC -l -w0 2>/dev/null | grep -i VersionInfo || echo "  ✗ 未找到 AppleALC（可能未加载 kext 或引导参数未生效）"

echo ""
echo "[2/7] 系统音频设备（期望出现扬声器/耳机/麦克风）"
system_profiler SPAudioDataType 2>/dev/null | grep -E '^[ ]{4}[^ ]|Devices:|Built-in|Headphone|Microphone|Speaker|ExtMic' | head -20 || echo "  ✗ 无音频设备"

echo ""
echo "[3/7] AppleHDADriver 匹配状态（期望 matched，不再是 !matched）"
ioreg -r -c AppleHDADriver -l 2>/dev/null | grep -i -E 'matched|codec|vendor' | head -10 || echo "  ✗ 未找到 AppleHDADriver"

echo ""
echo "[4/7] 当前加载的音频相关 kext"
kextstat 2>/dev/null | grep -i -E 'applealc|lilu|applehda' | awk '{print "  "$6}'

echo ""
echo "[5/7] 实际生效的 ConfigData（关键：必须 72 字节且含 01971ea1）"
cfg=$(ioreg -r -c IOHDACodecDevice -l -w0 2>/dev/null | grep -o '"ConfigData"=<[0-9a-fA-F]*>' | head -1 | sed 's/.*<\([0-9a-fA-F]*\)>.*/\1/')
if [ -z "$cfg" ]; then
  echo "  ✗ 未读取到 ConfigData"
else
  len=$(( ${#cfg} / 2 ))
  echo "  ConfigData 长度: ${len} 字节"
  if [ "$len" -eq 72 ] && echo "$cfg" | grep -qi '01971ea1'; then
    echo "  ✓ 完整 72 字节且含麦克风修复标记（WakeConfigData 修复已生效）"
  else
    echo "  ✗ 仍是短版或无修复标记 → WakeConfigData 覆盖了启动配置，重新部署 kext 并重启（见 docs/06 第 8 节）"
  fi
fi

echo ""
echo "[6/7] layout-id 一致性（期望 layout-id 与 alc-layout-id 都是 <0f000000>=15）"
ioreg -p IOService -r -l -w0 2>/dev/null | grep -iE '"(alc-)?layout-id" = <' | head -4 || echo "  ✗ 未找到 layout-id 属性"

echo ""
echo "[7/7] AppleHDA 实际暴露的输入/输出端（关键：不应只有 InternalMic/Headphones）"
sel=$(ioreg -r -l -w0 2>/dev/null | grep 'IOAudioSelectorControlSelectionDescriptionKey' | sed -E 's/.*DescriptionKey" ?= ?"([^"]*)".*/\1/' | sort -u)
if [ -n "$sel" ]; then
  echo "$sel" | sed 's/^/  - /'
  if echo "$sel" | grep -qiE 'ExtMic|External|Line In|IntSpeaker|Internal Speaker'; then
    echo "  ✓ 已暴露多个/正确的音频端口（AppleHDA 正在使用 SN6140 layout15）"
  else
    echo "  ✗ 仍只有 InternalMic/Headphones → 检查 [5] ConfigData 是否短版，或 AppleHDA 未采用注入资源（见 docs/06 第 7/8 节）"
  fi
else
  echo "  ✗ 未读取到 selector 端点"
fi

echo ""
echo "============================================"
echo "若 [1] 显示 REL-198 而非 DBG-199 → 部署未生效，检查是否重启/EFI 挂载点是否正确"
echo "若 [2] 无设备 → 检查 boot-args alcid=15 是否生效"
echo "若 [5] 显示 8 字节 → WakeConfigData 短版覆盖了启动配置，重新部署并重启（见 docs/06 第 8 节）"
echo "若 [6] layout-id=7 → boot-args 缺 alcapplid=15（见 docs/06 第 7 节）"
echo "若 [5][6] 都通过但 [7] 仍只有 InternalMic → 需导出 AppleALC DBG 日志进一步分析"
echo "麦克风逐项录音测试见 docs/06-麦克风修复说明.md"
echo "详细排错见 docs/05-部署验证与回滚.md"
echo "============================================"
