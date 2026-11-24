#!/bin/bash
# SN6140 AppleALC 命令行编译脚本（无完整 Xcode 环境，用 Command Line Tools）
# 基于社区 SN6140 源码快照 + MacKernelSDK + Lilu 1.7.2 开发文件
set -e
cd "$(dirname "$0")"

CF=(-arch x86_64 -target x86_64-apple-macosx10.9 -std=c++14
    -fno-exceptions -fno-rtti -fno-builtin -fapple-kext -nostdinc
    -isystem MacKernelSDK/Headers
    -I Lilu.kext/Contents/Resources -I AppleALC
    -I AppleALC/ALCUserClient -I AppleALC/ALCUserClientProvider
    -DKERNEL=1 -DPRODUCT_NAME=AppleALC -DMODULE_VERSION=1.9.9 -DHAVE_ANALOG_AUDIO=1)

mkdir -p build_objs

echo "[1/10] AppleALC/kern_start.cpp"
clang++ -c "${CF[@]}" AppleALC/kern_start.cpp -o build_objs/kern_start.o
echo "[2/10] AppleALC/kern_alc.cpp"
clang++ -c "${CF[@]}" AppleALC/kern_alc.cpp -o build_objs/kern_alc.o
echo "[3/10] AppleALC/kern_resources.cpp (内嵌 codec 资源, 10MB)"
clang++ -c "${CF[@]}" AppleALC/kern_resources.cpp -o build_objs/kern_resources.o
echo "[4/10] ALCUserClient.cpp"
clang++ -c "${CF[@]}" AppleALC/ALCUserClient/ALCUserClient.cpp -o build_objs/ALCUserClient.o
echo "[5/10] ALCUserClientProvider.cpp"
clang++ -c "${CF[@]}" AppleALC/ALCUserClientProvider/ALCUserClientProvider.cpp -o build_objs/ALCUserClientProvider.o
echo "[6/10] Lilu/plugin_start.cpp"
clang++ -c "${CF[@]}" Lilu.kext/Contents/Resources/Library/plugin_start.cpp -o build_objs/plugin_start.o

for f in kern_devinfo kern_compression kern_mach kern_nvram; do
  echo "[$(date +%S)] lilu_lib/$f.cpp"
  if [ -f "lilu_lib/$f.cpp" ]; then
    clang++ -c "${CF[@]}" "lilu_lib/$f.cpp" -o "build_objs/$f.o" || echo "WARN: $f 编译失败，跳过"
  fi
done

echo "=== 链接 ==="
OBJS=$(ls build_objs/*.o | grep -v kern_start2 | tr '\n' ' ')
clang++ -arch x86_64 -target x86_64-apple-macosx10.9 -fapple-kext \
  -undefined dynamic_lookup \
  -o build_objs/AppleALC_bin $OBJS \
  MacKernelSDK/Library/x86_64/libkmod.a \
  MacKernelSDK/Library/universal/libkmodc++.a

echo "=== 结果 ==="
ls -lh build_objs/AppleALC_bin
file build_objs/AppleALC_bin
