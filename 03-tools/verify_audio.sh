#!/bin/bash
# SN6140 声卡重启后一键验证脚本
# 用法: bash verify_audio.sh

echo "============================================"
echo " SN6140 声卡驱动验证"
echo "============================================"

echo ""
echo "[1/4] AppleALC 版本（期望 DBG-199-2026-10-26）"
ioreg -r -n AppleALC -l -w0 2>/dev/null | grep -i VersionInfo || echo "  ✗ 未找到 AppleALC（可能未加载 kext 或引导参数未生效）"

echo ""
echo "[2/4] 系统音频设备（期望出现扬声器/耳机等输出设备）"
system_profiler SPAudioDataType 2>/dev/null | grep -E '^[ ]{4}[^ ]|Devices:|Built-in|Headphone|Microphone|Speaker' | head -20 || echo "  ✗ 无音频设备"

echo ""
echo "[3/4] AppleHDADriver 匹配状态（期望 matched，不再是 !matched）"
ioreg -r -c AppleHDADriver -l 2>/dev/null | grep -i -E 'matched|codec|vendor' | head -10 || echo "  ✗ 未找到 AppleHDADriver"

echo ""
echo "[4/4] 当前加载的音频相关 kext"
kextstat 2>/dev/null | grep -i -E 'applealc|lilu|applehda' | awk '{print "  "$6}'

echo ""
echo "============================================"
echo "若 [1] 显示 REL-198 而非 DBG-199 → 部署未生效，检查是否重启/EFI 挂载点是否正确"
echo "若 [2] 无设备 → 检查 boot-args alcid=15 是否生效"
echo "详细排错见 docs/05-部署验证与回滚.md"
echo "============================================"
