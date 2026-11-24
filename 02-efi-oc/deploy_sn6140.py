#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SN6140 声卡驱动部署工具（本机专属：Macmini8,1 / OpenCore / Intel HDEF）
============================================================================
把社区验证过的 SN6140 定制版 AppleALC.kext 装进本机 EFI，并修正相关配置。

做四件事（每一件都可回滚）：
  1. 备份 config.plist + AppleALC.kext 到 EFI/OC/backups/sn6140-audio-<时间>/
  2. 用定制版替换 EFI/OC/Kexts/AppleALC.kext（内含 SN6140 layout 15 资源）
  3. boot-args: alcid=11 -> alcid=15，并加入 alcdelay=1000
  4. HDEF (PciRoot(0x0)/Pci(0x1F,0x3)) 的 layout-id / alc-layout-id: int 11 -> data 15
  5. 禁用 SimpleHDA.kext（与 AppleALC 抢同一 HDA 控制器，必须关闭）

用法：
  python3 deploy_sn6140.py --check            # 只报告当前状态，不写任何东西
  python3 deploy_sn6140.py --dry-run          # 预演，显示将要做的改动
  python3 deploy_sn6140.py                    # 实际部署
  python3 deploy_sn6140.py --rollback         # 从最新备份回滚

默认 EFI 挂载点 /Volumes/EFI，可用 --esp 指定。
"""
import argparse
import base64
import os
import plistlib
import shutil
import sys
import time

ESP_DEFAULT = "/Volumes/EFI"
OC_REL = "EFI/OC"
NVRAM_GUID = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
LAYOUT = 15
EXPECT_TAG = b"DBG-199-2026-10-26"
EXPECT_ID = "as.vit9696.AppleALC"
HDEF_PATH = "PciRoot(0x0)/Pci(0x1F,0x3)"
KEXT_REL = "Kexts/AppleALC.kext"
HERE = os.path.dirname(os.path.abspath(__file__))
SRC_KEXT = os.path.join(HERE, "..", "kexts", "applealc-sn6140", "AppleALC.kext")


def die(msg):
    sys.exit("✗ " + msg)


def ok(msg):
    print("  ✓ " + msg)


def verify_kext(kext):
    info_p = os.path.join(kext, "Contents/Info.plist")
    exe_p = os.path.join(kext, "Contents/MacOS/AppleALC")
    if not (os.path.isfile(info_p) and os.path.isfile(exe_p)):
        die("源 kext 不完整: " + kext)
    info = plistlib.load(open(info_p, "rb"))
    if info.get("CFBundleIdentifier") != EXPECT_ID:
        die("源 kext BundleID 不符: " + str(info.get("CFBundleIdentifier")))
    blob = open(exe_p, "rb").read()
    if EXPECT_TAG not in blob or b"SN6140" not in blob:
        die("源 kext 缺少 SN6140 定制标记，可能拿错了官方版")
    return info.get("CFBundleVersion"), len(blob)


def load_cfg(path):
    return plistlib.load(open(path, "rb"))


def save_cfg(path, data):
    with open(path, "wb") as f:
        plistlib.dump(data, f, fmt=plistlib.FMT_XML, sort_keys=True)


def current_kext_tag(kext):
    exe = os.path.join(kext, "Contents/MacOS/AppleALC")
    if not os.path.isfile(exe):
        return "（无）"
    blob = open(exe, "rb").read()
    for t in (b"DBG-199-2026-10-26", b"REL-198-2026-09-27", b"REL-199-2026-09-27"):
        if t in blob:
            return t.decode()
    return "未知构建"


def report(esp):
    oc = os.path.join(esp, OC_REL)
    cfg = load_cfg(os.path.join(oc, "config.plist"))
    dst = os.path.join(oc, KEXT_REL)
    print("=== 当前状态 ===")
    print("  EFI 挂载点     :", esp)
    print("  当前 AppleALC  :", current_kext_tag(dst))
    args = cfg["NVRAM"]["Add"][NVRAM_GUID]["boot-args"]
    print("  boot-args      :", args)
    print("  alcid=15       :", "alcid=15" in args.split())
    names = [k.get("BundlePath") for k in cfg["Kernel"]["Add"]]
    for n in ("Lilu.kext", "AppleALC.kext", "SimpleHDA.kext"):
        if n in names:
            k = cfg["Kernel"]["Add"][names.index(n)]
            print(f"  {n:18}: Enabled={k.get('Enabled')} (idx {names.index(n)})")
    dp = cfg.get("DeviceProperties", {}).get("Add", {})
    if HDEF_PATH in dp:
        for key in ("layout-id", "alc-layout-id"):
            if key in dp[HDEF_PATH]:
                v = dp[HDEF_PATH][key]
                desc = f"data {v.hex()}" if isinstance(v, bytes) else f"{type(v).__name__} {v}"
                print(f"  HDEF {key:14}: {desc}")


def apply_changes(cfg, kext_ver):
    changed = []

    # 1) boot-args
    nv = cfg["NVRAM"]["Add"][NVRAM_GUID]
    args = nv["boot-args"]
    tokens = args.split()
    tokens = [t for t in tokens if not t.startswith("alcid=") and not t.startswith("alcdelay=")]
    tokens += [f"alcid={LAYOUT}", "alcdelay=1000"]
    nv["boot-args"] = " ".join(tokens)
    changed.append("boot-args -> alcid=15 alcdelay=1000")

    # 2) DeviceProperties layout-id (int 11 -> data 15)
    dp = cfg.get("DeviceProperties", {}).get("Add", {})
    if HDEF_PATH in dp:
        data15 = bytes([LAYOUT, 0, 0, 0])
        for key in ("layout-id", "alc-layout-id"):
            if key in dp[HDEF_PATH]:
                dp[HDEF_PATH][key] = data15
                changed.append(f"{HDEF_PATH} {key} -> data 15")
    else:
        changed.append("未找到 HDEF 设备路径，仅靠 alcid= 生效（可正常工作）")

    # 3) 禁用 SimpleHDA
    add = cfg["Kernel"]["Add"]
    for k in add:
        if k.get("BundlePath") == "SimpleHDA.kext" and k.get("Enabled"):
            k["Enabled"] = False
            changed.append("SimpleHDA.kext -> 已禁用（避免与 AppleALC 冲突）")

    # 校验 kext 顺序
    names = [k.get("BundlePath") for k in add]
    if names.index("AppleALC.kext") < names.index("Lilu.kext"):
        die("AppleALC 排在 Lilu 之前，需手动调整 Kernel>Add 顺序")

    return changed


def validate(cfg):
    args = cfg["NVRAM"]["Add"][NVRAM_GUID]["boot-args"].split()
    for need in (f"alcid={LAYOUT}", "alcdelay=1000"):
        if need not in args:
            die(f"校验失败：boot-args 缺 {need}")
    add = cfg["Kernel"]["Add"]
    names = [k.get("BundlePath") for k in add]
    if "AppleALC.kext" not in names:
        die("Kernel>Add 里没有 AppleALC.kext")
    alc = add[names.index("AppleALC.kext")]
    if not alc.get("Enabled"):
        die("Kernel>Add 里 AppleALC.kext 未启用")
    if "SimpleHDA.kext" in names and add[names.index("SimpleHDA.kext")].get("Enabled"):
        die("SimpleHDA.kext 仍启用，会与 AppleALC 冲突")


def main():
    global SRC_KEXT
    ap = argparse.ArgumentParser()
    ap.add_argument("--esp", default=ESP_DEFAULT)
    ap.add_argument("--kext", default=SRC_KEXT)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--rollback", action="store_true")
    a = ap.parse_args()

    esp = os.path.abspath(a.esp)
    # 若默认路径未挂载，自动探测所有 /Volumes/EFI* 挂载点中含 OpenCore config 的那个
    if not os.path.isfile(os.path.join(esp, OC_REL, "config.plist")):
        import glob
        cands = [p for p in glob.glob("/Volumes/EFI*")
                 if os.path.isfile(os.path.join(p, OC_REL, "config.plist"))]
        if len(cands) == 1:
            print(f"提示: {esp} 不可用，自动改用 {cands[0]}")
            esp = cands[0]
        elif len(cands) > 1:
            print("检测到多个 EFI 挂载点，默认仍用 " + esp + "：")
            for c in cands:
                print("   " + c)
    oc = os.path.join(esp, OC_REL)
    cfg_p = os.path.join(oc, "config.plist")
    dst = os.path.join(oc, KEXT_REL)
    if not os.path.isfile(cfg_p):
        die(f"找不到 {cfg_p}，请确认 EFI 已挂载且是 OpenCore")

    if a.check:
        report(esp)
        return

    if a.rollback:
        baks = os.path.join(oc, "backups")
        dirs = sorted([d for d in os.listdir(baks) if d.startswith("sn6140-audio-")]) if os.path.isdir(baks) else []
        if not dirs:
            die("找不到备份目录，无法回滚")
        latest = os.path.join(baks, dirs[-1])
        print("从备份回滚:", latest)
        shutil.copy2(os.path.join(latest, "config.plist"), cfg_p)
        if os.path.isdir(os.path.join(latest, "AppleALC.kext")):
            shutil.rmtree(dst, ignore_errors=True)
            shutil.copytree(os.path.join(latest, "AppleALC.kext"), dst, symlinks=True)
        print("✅ 已回滚。重启生效。")
        return

    kext_ver, exe_len = verify_kext(os.path.abspath(a.kext))
    cfg = load_cfg(cfg_p)
    if a.dry_run:
        print("=== 预演（不写入）===")
        print(f"  源 kext: AppleALC {kext_ver} / {EXPECT_TAG.decode()} ({exe_len} B)")
        for c in apply_changes(cfg, kext_ver):
            print("  将改动:", c)
        return

    # 落盘前先算好新配置
    new_cfg = load_cfg(cfg_p)
    changes = apply_changes(new_cfg, kext_ver)
    validate(new_cfg)

    stamp = time.strftime("%Y%m%d-%H%M%S")
    bak = os.path.join(oc, "backups", f"sn6140-audio-{stamp}")
    os.makedirs(bak, exist_ok=False)
    shutil.copy2(cfg_p, os.path.join(bak, "config.plist"))
    if os.path.isdir(dst):
        shutil.copytree(dst, os.path.join(bak, "AppleALC.kext"), symlinks=True)
    with open(os.path.join(bak, "restore.sh"), "w") as f:
        f.write("#!/bin/sh\nset -e\nESP=\"${1:-/Volumes/EFI}\"\n")
        f.write('cp "$(dirname "$0")/config.plist" "$ESP/EFI/OC/config.plist"\n')
        f.write('rm -rf "$ESP/EFI/OC/Kexts/AppleALC.kext"\n')
        f.write('cp -R "$(dirname "$0")/AppleALC.kext" "$ESP/EFI/OC/Kexts/"\n')
        f.write('echo "已回滚，重启生效"\n')
    print("备份目录:", bak)

    # 原子替换 kext
    tmp_kext = dst + ".new"
    prev_kext = dst + ".prev"
    shutil.rmtree(tmp_kext, ignore_errors=True)
    shutil.rmtree(prev_kext, ignore_errors=True)
    shutil.copytree(os.path.abspath(a.kext), tmp_kext, symlinks=True)
    if os.path.isdir(dst):
        os.rename(dst, prev_kext)
    os.rename(tmp_kext, dst)
    shutil.rmtree(prev_kext, ignore_errors=True)

    # 原子替换 config
    tmp_cfg = cfg_p + ".sn6140-new"
    save_cfg(tmp_cfg, new_cfg)
    validate(load_cfg(tmp_cfg))
    shutil.copy2(tmp_cfg, cfg_p)
    os.remove(tmp_cfg)

    # 写后验证
    final = load_cfg(cfg_p)
    validate(final)
    blob = open(os.path.join(dst, "Contents/MacOS/AppleALC"), "rb").read()
    if EXPECT_TAG not in blob:
        die("写后校验失败：kext 内容不对")

    print("\n✅ 部署完成")
    for c in changes:
        print("  -", c)
    print(f"  - AppleALC.kext -> {kext_ver} / {EXPECT_TAG.decode()}")
    print("\n重启后进系统验证：")
    print("  ioreg -r -n AppleALC -l -w0 | grep VersionInfo   # 期望 DBG-199-2026-10-26")
    print("  system_profiler SPAudioDataType                  # 期望出现 内置扬声器/耳机/麦克风")
    print("\n注意：先调低音量再测试，如有刺耳噪声立即静音。")
    print("回滚：python3 " + os.path.basename(__file__) + " --rollback")


if __name__ == "__main__":
    main()
