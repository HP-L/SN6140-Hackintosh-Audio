# SN6140 Hackintosh Audio Driver Project

> Complete solution to make the Senarytech **SN6140** (`0x14f1:1f87`) HD Audio Codec work on a Hackintosh (OpenCore / macOS 15 Sequoia).
> Includes: hardware diagnosis, custom AppleALC kext source and build project, OpenCore configuration and one-click deploy script, and full documentation.

**中文版 / Chinese version**: [README.md](README.md)

---

## 0. Quick Start (Ready to Use, 4 Steps)

> Just want sound? Follow these 4 steps and reboot. Details below.

**Step 1 · Mount EFI**
Open Disk Utility and mount the **EFI** partition on the main disk (usually `disk0s1`, mounted at `/Volumes/EFI`).

**Step 2 · Deploy (choose either method)**

**Method A | One-click script (recommended, includes backup, rollback available)**

Open Terminal and paste:

```bash
cd /Users/doro/WorkBuddy/2026-11-24-11-32-31/SN6140-Hackintosh-Audio/02-efi-oc
python3 deploy_sn6140.py
```

`✅ 部署完成` (deployment complete) means success.

**Method B | Manual configuration (no script)**

Use Finder and any plist editor (PlistEdit Pro / Xcode / OpenCore Configurator) to do two things:

1. **Replace the kext**: copy `kexts/applealc-sn6140/AppleALC.kext` from the project into the EFI partition's `EFI/OC/Kexts/`, overwriting the original. (Back up the original kext first.)
2. **Edit `EFI/OC/config.plist`**, 4 places:
   - `NVRAM → Add → 7C436110-AB2A-4BBB-A880-FE41995C9F82 → boot-args`: change `alcid=11` to `alcid=15`, append `alcdelay=1000` and `alcapplid=15` at the end (`alcapplid` makes the layout-id reported to AppleHDA also 15; **without it only the internal mic shows and headphone ports are missing**)
   - Under `DeviceProperties → Add → PciRoot(0x0)/Pci(0x1F,0x3)`: set the type of `layout-id` and `alc-layout-id` to **Data**, value `0F000000` (i.e. 15)
   - `Kernel → Add` `SimpleHDA.kext`: set `Enabled` to `false`
   - Confirm `Lilu.kext` comes **before** `AppleALC.kext`

   Rationale and exact paths: [02-efi-oc/config/config-changes.md.en.md](02-efi-oc/config/config-changes.md.en.md).

> Both methods are equivalent; proceed to Step 3 after completing either. Manually back up your original config.plist.

**Step 3 · Reboot**
Restart the computer; OpenCore automatically loads the custom audio driver.

**Step 4 · Verify sound**
After reboot, System Settings → Sound should show input/output devices; or run in Terminal:

```bash
bash /Users/doro/WorkBuddy/2026-11-24-11-32-31/SN6140-Hackintosh-Audio/03-tools/verify_audio.sh
```

> ⚠️ Set **volume to minimum** for first playback; raise only after confirming no harsh noise.
> To roll back: `python3 deploy_sn6140.py --rollback` (in `02-efi-oc/`), then reboot.

---

## 1. Project in One Sentence

The machine's actual sound card is **SN6140**, not the initially assumed SN6180. Official AppleALC does not support this codec, so AppleHDA loads but no driver matches → no sound.
The solution uses the community-verified **custom AppleALC for SN6140 (layout 15)**, injecting the kext via OpenCore and fixing boot-args / layout-id so native AppleHDA drives it — speakers, headphones, microphone, and hot-plug all work.

> 📌 **Updated 2026-11-24**: microphone endpoint fixed. The original resource configured the headset jack pin NID `0x19` as non-mic (Default Device `0x8`) and labelled the input as Line In. It is now `0x00A11030` (Mic) and named `ExtMic`. See [06-麦克风修复说明.md.en.md](docs/06-麦克风修复说明.md.en.md). Re-run the one-click deploy script and reboot to get the fixed build.

---

## 2. Directory Structure

```
SN6140-Hackintosh-Audio/
├── README.md / README.md.en.md      ← you are here (project entry)
├── docs/                            ← full documentation (each with .en.md version)
│   ├── 01-硬件诊断与结论.md            measured codec ID, why not SN6180, root cause
│   ├── 02-技术路线.md                 why AppleALC injection over ALSA port
│   ├── 03-OpenCore配置说明.md          rationale and location of each config change
│   ├── 04-编译指南.md                 source structure, build steps, known limits
│   ├── 05-部署验证与回滚.md            deploy script, verification, rollback
│   └── 06-麦克风修复说明.md           NID 0x19 pin config + ExtMic endpoint fix
├── 01-driver/                       ← audio driver code project
│   ├── linux-reference/              Linux reference drivers (senarytech.c / conexant.c)
│   ├── source/                       complete AppleALC source snapshot (reproducible build)
│   │   ├── Resources/SN6140/         ★ core: layout15.xml / Platforms15.xml (zlib-compressed)
│   │   ├── AppleALC/                 AppleALC source (incl. generated kern_resources.cpp)
│   │   ├── build.sh                  command-line build script
│   │   ├── build_objs/               compiled object files (.o)
│   │   ├── MacKernelSDK/             build dependency: kernel headers and libraries
│   │   ├── Lilu.kext/                build dependency: Lilu dev headers
│   │   └── ResourceConverter/        resource packing tool (XML→zlib→embedded array)
│   ├── prebuilt/AppleALC.kext        ★ verified custom kext artifact (ready to deploy, mic fix included)
│   ├── prebuilt/backup-pre-micfix/   pre-fix kext / resources backup (manual rollback)
│   └── checksums/SHA256SUMS-micfix.txt  SHA256 checksums of the mic-fixed build
├── kexts/                           ← deployment source (script reads here)
│   └── applealc-sn6140/AppleALC.kext  (same as prebuilt, for deploy script)
├── 02-efi-oc/                       ← Hackintosh EFI/OC configuration project
│   ├── deploy_sn6140.py             ★ one-click deploy/rollback (--check/--dry-run/--rollback)
│   ├── config/config-changes.md      machine-readable config change list
│   └── backup/                       rollback script template notes
├── 03-tools/                        ← helper tools
│   └── verify_audio.sh               post-reboot one-click verification script
└── (work log in workspace .workbuddy/memory/)
```

---

## 3. Quick Start (Detailed)

### 1. Deploy (when EFI is mounted)

```bash
cd SN6140-Hackintosh-Audio/02-efi-oc

python3 deploy_sn6140.py --check      # report current state (read-only)
python3 deploy_sn6140.py --dry-run    # preview changes (read-only)
python3 deploy_sn6140.py              # actual deploy (auto backup)
```

The script defaults to EFI mount `/Volumes/EFI`; if not mounted it auto-detects other `/Volumes/EFI*`; you can also specify `--esp /path`.

### 2. Verify after reboot

```bash
bash ../03-tools/verify_audio.sh
```

or manually:

```bash
ioreg -r -n AppleALC -l -w0 | grep VersionInfo   # expect DBG-199-2026-10-26
system_profiler SPAudioDataType                  # expect built-in speakers/headphones/mic
```

### 3. Rollback if problems

```bash
python3 deploy_sn6140.py --rollback
```

---

## 4. Key Facts at a Glance

| Item | Value |
|---|---|
| Machine | Macmini8,1 / x86_64 Hackintosh |
| System | macOS 15.8.1 (Sequoia) / Darwin 24.6.0 |
| Bootloader | OpenCore (ngreen EFI) |
| Sound chip | **SN6140** = `0x14F11F87` (revision `0x100100`) |
| (Contrast) SN6180 | `0x14F120D1` — not this machine's chip |
| HDA controller path | `PciRoot(0x0)/Pci(0x1F,0x3)` (Intel HDEF) |
| layout-id used | **15** |
| AppleALC version | custom 1.9.9 (`DBG-199-2026-10-26`) |
| Stock AppleALC | 1.9.8 (`REL-198-2026-09-27`) — no SN6140, no sound |
| Upstream support | Official AppleALC does not support SN6140; customization required |

---

## 5. Sources and Credits

- SN6140 custom AppleALC source and build artifact: `chenhggu6475/Senary-SN6140-AppleALC-Hackintosh`
- Same-hardware verification record: `gqm321/macos15-rtx5070-jiaolong`
- Linux kernel HDA reference drivers: `torvalds/linux` (`sound/hda/codecs/senarytech.c`, `conexant.c`)
- AppleALC / Lilu / MacKernelSDK: acidanthera

The build artifact's SHA256 was verified; the community validated speakers/microphone/headphone hot-plug all working on the same codec + same macOS.

---

## 6. Documentation Navigation

- Want to know **why** → [02-技术路线.md.en.md](docs/02-技术路线.md.en.md)
- Want to know **how the chip was identified** → [01-硬件诊断与结论.md.en.md](docs/01-硬件诊断与结论.md.en.md)
- Want to change **OpenCore config** → [03-OpenCore配置说明.md.en.md](docs/03-OpenCore配置说明.md.en.md)
- Want to **build the driver** → [04-编译指南.md.en.md](docs/04-编译指南.md.en.md)
- Want to **deploy / verify / roll back** → [05-部署验证与回滚.md.en.md](docs/05-部署验证与回滚.md.en.md)
- Microphone not working / what changed in this fix → [06-麦克风修复说明.md.en.md](docs/06-麦克风修复说明.md.en.md)
