# 06 · Microphone Support Fix (2026-11-24)

## 1. Symptom and diagnosis

The original custom AppleALC (layout 15) drove the **speakers and headphones** correctly, but macOS exposed only an inactive line input; the headset/internal microphone could not record.

Both root causes are in resource files, not in kernel code:

| Location | Before fix | Problem |
|---|---|---|
| `PinConfigs.kext` → SN6140 / layout 15 `ConfigData` | NID `0x19` pin config = `0x00811030` | Default Device field is `0x8` (Other/undefined), not a microphone. This is the mic pin of the headset jack. |
| `Resources/SN6140/layout15.xml` → `Inputs` | `Mic`, `LineIn` | The second input path (NID `0x19` → ADC `0x13`) was exposed as Line In instead of an external microphone. |

Linux mainline `sound/hda/codecs/conexant.c` states explicitly for SN6140:

> In cx11880 and sn6140, the node 16 can only be configured to headphone or disabled, the node 19 can only be configured to microphone or disabled.

The coreboot SN6140 verb table (`vendor_id=0x14f11f87`) likewise configures **Port D / NID `0x19`** as `0x04A19020 Headset Microphone`. Configuring `0x19` as a non-mic was therefore a clear resource error.

Codec identity re-checked on this machine:

```
IOHDACodecVendorID            = 351346567  (0x14F11F87  SN6140)
IOHDACodecFunctionSubsystemID = 351339323  (0x14F1033B)
```

## 2. What changed

### 2.1 Pin configuration (the key fix)

The four verbs for NID `0x19` in `ConfigData`:

```
Before: 01 97 1c 30  01 97 1d 10  01 97 1e 81  01 97 1f 00   → 0x00811030
After:  01 97 1c 30  01 97 1d 10  01 97 1e A1  01 97 1f 00   → 0x00A11030
```

Only Default Device changed from `0x8` to `0xA` (Mic); all other fields were preserved:

- Jack / External
- 1/8" connection, color 1
- Association 3, Sequence 0 (same as before, so existing grouping is untouched)

This is the smallest possible change and does not touch the already working speaker/headphone paths.

### 2.2 Input endpoint naming

In `layout15.xml`:

```diff
 <key>Inputs</key>
 <array>
     <string>Mic</string>
-    <string>LineIn</string>
+    <string>ExtMic</string>
 </array>
```

The matching endpoint dictionary key was also renamed from `<key>LineIn</key>` to `<key>ExtMic</key>`. The non-essential `DspNoiseReduction` block on that endpoint was removed so the compressed embedded resource still fits the original 322-byte slot. The internal microphone (NID `0x1A` → ADC `0x14`) and its DSP settings are unchanged.

### 2.3 Files updated

- `01-driver/source/Resources/PinConfigs.kext/Contents/Info.plist`
- `01-driver/source/Resources/SN6140/layout15.xml`
- `01-driver/source/Resources/SN6140/layout15.xml.zlib` and `.zlib.md5`
- `01-driver/source/AppleALC/kern_resources.cpp` (embedded `file85` array)
- `kexts/applealc-sn6140/AppleALC.kext` (deployment source)
- `01-driver/prebuilt/AppleALC.kext` (prebuilt artifact)
- `01-driver/checksums/SHA256SUMS-micfix.txt`
- `01-driver/prebuilt/backup-pre-micfix/` (pre-fix backup for manual rollback)

The driver version tag remains `DBG-199-2026-10-26`; no OpenCore config change is required.

## 3. Deploy

Mount the EFI partition of the main disk in Disk Utility if it is not mounted, then run:

```bash
cd /Users/doro/WorkBuddy/2026-11-24-11-32-31/SN6140-Hackintosh-Audio/02-efi-oc
python3 deploy_sn6140.py
```

The script backs up the current `config.plist` and `AppleALC.kext` from EFI, then installs the mic-fixed kext. Reboot to apply.

Manual deployment is also fine: copy `kexts/applealc-sn6140/AppleALC.kext` over `EFI/OC/Kexts/AppleALC.kext`. `config.plist` needs no changes.

## 4. Verify

```bash
# 1) driver is still the expected build
ioreg -r -n AppleALC -l -w0 | grep VersionInfo      # DBG-199-2026-10-26

# 2) injected pin config contains the fix
ioreg -r -c IOHDACodecDevice -l -w0 | grep -o '01971ea1'

# 3) macOS sees a microphone input
system_profiler SPAudioDataType | grep -i -E 'microphone|input|ExtMic'

# 4) list and record 5 seconds (change device index as needed)
ffmpeg -f avfoundation -list_devices true -i ""
ffmpeg -f avfoundation -i ":1" -t 5 mic-test.wav
afinfo mic-test.wav | grep -i channels
```

System Settings → Sound → Input or QuickTime recording can be used for a subjective check. Keep the volume low during the first test.

The one-click helper also works:

```bash
bash /Users/doro/WorkBuddy/2026-11-24-11-32-31/SN6140-Hackintosh-Audio/03-tools/verify_audio.sh
```

## 5. Rollback

```bash
cd /Users/doro/WorkBuddy/2026-11-24-11-32-31/SN6140-Hackintosh-Audio/02-efi-oc
python3 deploy_sn6140.py --rollback
```

Or copy `01-driver/prebuilt/backup-pre-micfix/AppleALC.kext` back to `EFI/OC/Kexts/` manually and reboot.

## 6. Limits and follow-up

- This fix is based on public Linux/coreboot SN6140 pin definitions plus the codec identity read from this machine via IORegistry. It is a **minimal safe change**, not a per-pin hardware trace validated under Windows.
- The internal microphone NID `0x1A` still uses the CX8070-derived `0x90A60020` (Mic / internal / connection type 6). If the internal mic is still silent, capture `/proc/asound/card*/codec#*` under Linux before deciding whether to switch to `0x90A70020` or route through ADC `0x13`.
- Linux also uses vendor verb `0x3B0` and dynamic VREF on plug/unplug for CTIA/OMTP headset recognition. AppleALC does not implement this. If the headset mic remains intermittent, additional vendor verbs can be appended to `ConfigData`, but they need real recording tests.

## 7. Second fix: alcapplid (2026-11-24, port visibility issue)

### Symptom

After deploying the resource fixes in sections 1–5, a reboot still showed only the **Internal Microphone** under System Settings → Sound → Input, with no headphone / headset-mic ports.

### Root cause (IORegistry evidence)

```
IOAudioDeviceModelID      = "AppleHDA:7"
HDEF layout-id            = <07000000>   (7)
HDEF alc-layout-id        = <0f000000>   (15)
AppleHDAEngineInput info   = {"num-internal-mics"=1, "layout-id"=7}
Input selector options     = InternalMic (only 1)
Output selector options    = Headphones (only 1)
```

Key point: since 1.2.8 AppleALC uses **two** layout ids:

| Parameter | Purpose | Current value |
|---|---|---|
| `alcid=15` / `alc-layout-id` | AppleALC **internal** id used to select and inject the SN6140 layout15 resources | 15 ✓ |
| `alcapplid` / `apple-layout-id` | layout-id reported to **AppleHDA**, deciding which resources it loads | unset → **Lilu default 7** ✗ |

In Lilu's `kern_devinfo.hpp`, `DefaultReportedLayoutId = 7`. Because boot-args lacked `alcapplid`, AppleHDA received layout-id=7 and loaded its **built-in** generic layout 7 (1 internal mic + 1 headphone), not our injected SN6140 layout15 (2 inputs + 2 outputs). This is why the layout15 edits from sections 1–5 never took effect.

Note: `WakeConfigData` (an 8-byte short verb set) + `WakeVerbReinit` is a standard AppleALC pattern shared by 451 entries (for reinitialization after sleep/wake). It is **not** the cause here and needs no change.

### Fix

Append to `NVRAM > Add > 7C4361... > boot-args`:

```
alcapplid=15
```

Current value is `alcid=15 alcdelay=1000 alcapplid=15`. `deploy_sn6140.py` has been updated to write it and to verify `alcapplid=15` in `--check` / `validate`, so repeated runs will not drop it. Manual-configuration users must add this boot-arg themselves.

### Diagnostic aid (temporary this round)

This round also added `-alcdbg -liludbg liludump=90` to boot-args (the kext is a DBG build) so AppleALC/Lilu logs are written to `/var/log/` 90 seconds after boot, to confirm the resource-injection path. Once confirmed, these three debug arguments should be removed.

### Verification

After reboot:

```bash
# layout-id should match alc-layout-id, both 15
ioreg -r -c AppleHDAController -l -w0 | grep -i layout-id    # layout-id = <0f000000>

# input/output selectors should expose multiple endpoints (Mic/ExtMic, IntSpeaker/Headphone)
ioreg -r -l -w0 | grep IOAudioSelectorControlSelectionDescriptionKey
```

### Rollback

```bash
# restore config from before alcapplid was added
sudo cp /Volumes/EFI/EFI/OC/config.plist.bak-pre-alcapplid /Volumes/EFI/EFI/OC/config.plist
```

(Use the actual backup path; `--rollback` reverts to the last full-deployment backup.)

## 8. Real root cause found after the second reboot: short WakeConfigData overrode pin config

Adding `alcapplid=15` did make `layout-id` become 15 (`IOAudioDeviceModelID = AppleHDA:15`), yet the system still exposed only `InternalMic` + `Headphones`. Section 7 was therefore incomplete.

### Evidence from IORegistry

After reboot, `HDAConfigDefault` read:

```
ConfigData     = <01770c0201670c02>          ← only 8 bytes / 2 verbs
BootConfigData = <01771c10...01670c02>       ← full 72 bytes / 18 verbs
alc-pinconfig-status = Yes
```

The short blob contains only `0x0c` (Set Pin Control) verbs and **no `0x1c` (Set Configuration Default) verb**. Without `0x1c` no pin gets a default device type, so AppleHDA falls back to BIOS/hardware defaults — hence only the internal mic and headphones.

### Why the swap happens

AppleALC source `kern_alc.cpp:803-808`:

```cpp
if (wakeConfigData != nullptr) {
    if (configData != nullptr)
        newConfig->setObject("BootConfigData", configData);
    newConfig->setObject("ConfigData", wakeConfigData);   // short blob becomes the effective config
    newConfig->removeObject("WakeConfigData");
}
```

The SN6140 entry shipped with `WakeConfigData=<01770c0201670c02>` + `WakeVerbReinit=True`, so `patchPinConfig()` performed that swap at boot. The Section 6 conclusion that "WakeConfigData is standard, leave it alone" was **a misjudgement**: the mechanism is standard, but this community resource's short blob is too minimal — enough for wake-time pin power reinitialization, not for boot configuration.

### Fix

Set the SN6140 entry's `WakeConfigData` to the same full 72 bytes as `ConfigData`. Now both boot and wake paths carry all 18 verbs (including the four `0x1c` pin defaults, where NID `0x19 = 0x00A11030` is the headset mic).

Updated in three places:
- `01-driver/source/Resources/PinConfigs.kext/Contents/Info.plist`
- `kexts/applealc-sn6140/AppleALC.kext/Contents/Info.plist`
- `01-driver/prebuilt/AppleALC.kext/Contents/Info.plist`

Pre-fix backups: `01-driver/prebuilt/backup-pre-wakefix/`, EFI deployment backup: `EFI/OC/backups/sn6140-audio-20261124-155850/`. The Mach-O binary is untouched (SHA256 still `3f37195b...`); only the pin-config table in `Info.plist` changed.

### Verification

After reboot:

```bash
ioreg -r -c IOHDACodecDevice -l -w0 | grep -A2 HDAConfigDefault
```

Expect **both** `ConfigData` and `BootConfigData` to be 72 bytes and contain `01971ea1`. Then check whether selectors expose `ExtMic` / `IntSpeaker`.

### If only the internal mic still appears

That means AppleHDA is not using the injected layout15 resource at all, and boot logs are needed to continue. In this environment `log show` is unavailable and `liludump` produced no file; if that happens, export the AppleALC DBG log manually with Console.app or `sudo log show --last boot` on the machine.
