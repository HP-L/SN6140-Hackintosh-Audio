# Collecting SN6140 Hardware Information in Linux

## Why this step is necessary

The pin configuration has now been loaded correctly by AppleHDA (`ConfigData` is the full 72 bytes, `layout-id=15`), yet the system still exposes only `InternalMic` + `Headphones`. That means the problem is no longer in the AppleALC configuration, but that **this community layout resource does not match your machine's real hardware routing** — it was copied from CS8409/CX8070, and its headset-mic path (NID, ADC, widget connections) may not correspond to your hardware.

To rebuild it precisely, we need the real pin definitions of the SN6140 in this machine. The Linux kernel driver exports all of this — it is the only reliable source.

Important background: **SN6140 is a SoundWire codec.** If the microphone is actually routed over the SoundWire bus rather than traditional HDA pins, macOS's AppleHDA cannot see it at all — an architectural limit that no AppleALC configuration can work around. This collection will also confirm whether that is the case.

## How to do it (~5 minutes)

### 1. Prepare a Linux Live USB

Any distribution works (Ubuntu / Fedora / Debian Live). Create the boot stick with Rufus or `dd`. If you already have a Linux dual-boot, skip this step.

### 2. Boot from the USB

Press F12 / F11 / Esc at boot (depends on the board) and select the USB device. Choose "Try Linux" — **do not install**.

### 3. Run the export script

Copy `03-tools/dump_codec_linux.sh` from the project into Linux (via USB stick or phone), then open a terminal:

```bash
cd <directory-with-the-script>
chmod +x dump_codec_linux.sh
./dump_codec_linux.sh
```

It produces `sn6140-linux-dump-<datetime>.tar.gz`.

### 4. Send me the tar.gz

Put the file on a USB stick or upload it, then send it to me. From it I will:
- Confirm each NID's real device type (headphone / headset mic / internal mic / speaker)
- Confirm the headset mic's ADC and widget connection path
- Determine whether the mic runs over SoundWire (and thus whether macOS can support it at all)
- Rebuild layout / Platforms / PinConfig and give you a definite answer

## What the script collects

| File | Contents | Purpose |
|------|----------|---------|
| `00-system.txt` | Kernel version, distro | Match driver behaviour |
| `01-lspci.txt` | PCI audio device and SoundWire controller | Identify codec and bus |
| `02-asound-cards.txt` | ALSA card list | Check driver recognition |
| `codecs/*` | **HDA codec dump (most important)** | Each pin's default config, widget connections |
| `03-soundwire.txt` | SoundWire sysfs device tree | SN6140 bus topology |
| `04-dmesg-audio.txt` | Kernel audio log | Driver initialization |
| `05-modules.txt` | Audio modules and firmware | Identify loaded driver |

## If the script reports errors

- The script intentionally tolerates failures (`codec#*` files legitimately do not exist on SoundWire machines)
- As long as a `tar.gz` is produced, it is usable; I will tell you if something is missing
- If no file is produced at all, just send me a screenshot of the terminal error

## Chinese version

See `07-Linux采集说明.md`.
