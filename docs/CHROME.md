# Google Chrome on DOS

```
DOS> chrome                  open Chrome
DOS> chrome youtube.com      open Chrome at a URL
DOS> web arch wiki zram      search Google for the words
DOS> web github.com/foo      open a URL (https:// is added for you)
```

Module `modules/30-chrome` installs it. It runs again on every `dos-update`.

## What gets installed

| What | Where | Why |
|------|-------|-----|
| `google-chrome` (AUR, Stable channel) | `/opt/google/chrome`, launcher `/usr/bin/google-chrome-stable` | the browser |
| `libva-utils` | `vainfo` | check that VA-API works |
| Flags | `~/.config/chrome-flags.conf` | Wayland, video decode, RAM |
| Policy | `/etc/opt/chrome/policies/managed/dos.json` | Memory Saver, no background mode |
| Commands | `/usr/local/share/dos/commands/{chrome,web}` | DOS Shell commands |

The AUR launcher reads `~/.config/chrome-flags.conf` with
`grep -v '^#'`, so comments must start at the beginning of a line and a flag
can't contain spaces. `dos-update` overwrites the file. If you had edited it,
your copy is saved as `chrome-flags.conf.bak`.

## The flags

| Flag | What it does |
|------|--------------|
| `--ozone-platform=wayland` | Runs Chrome as a native Wayland app under sway instead of through Xwayland: sharper text, less latency, and VA-API works. Chrome 140+ would pick Wayland by itself; DOS says it explicitly. |
| `--enable-features=AcceleratedVideoDecodeLinuxGL` | The current name of the VA-API decode feature (it was `VaapiVideoDecodeLinuxGL` before Chrome 131). It's on by default since Chrome 143; DOS keeps it set so a field trial can't turn it off. |
| `--process-per-site` | All tabs of the same site share one renderer process instead of one each. That saves RAM on a 2-core, 8 GB machine. |

The policy file turns on **Memory Saver** (balanced): tabs you haven't looked at
for a while are discarded and reload when you click them. It also turns off
**background mode**, so closing the last window really quits Chrome. Because a
policy is set, Chrome shows "Managed by your organization" in its menu. That
only refers to this file. See it at `chrome://policy`.

Left out on purpose:

- `--ignore-gpu-blocklist`, `--enable-zero-copy`: the HD 520 isn't blocklisted,
  and the Arch Wiki warns they can crash the GPU process.
- `AcceleratedVideoEncoder` (hardware encode for video calls): upstream calls
  VA-API on Linux "not supported, no guarantees". To try it, change the line to
  `--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoEncoder`.
  There can be only one `--enable-features` line.
- `--single-process`, `--disable-gpu` and similar: unsafe or slower.

Sources: Arch Wiki
[Chromium](https://wiki.archlinux.org/title/Chromium#Hardware_video_acceleration),
Chromium [`docs/gpu/vaapi.md`](https://chromium.googlesource.com/chromium/src/+/main/docs/gpu/vaapi.md)
and [`media/base/media_switches.cc`](https://chromium.googlesource.com/chromium/src/+/main/media/base/media_switches.cc),
and the Chrome policy definitions (`HighEfficiencyModeEnabled`,
`MemorySaverModeSavings`, `BackgroundModeEnabled`).

## Is video decode hardware-accelerated?

1. **The driver.** In a terminal, run `vainfo`. It should say
   `Driver version: Intel iHD driver` and list `VAEntrypointVLD` lines. Each one is
   a codec the GPU can decode.
2. **`chrome://gpu`.** Check that *Video Decode* says **Hardware accelerated**,
   and that the *Video Acceleration Information* table lists decode profiles
   such as `H264 High`. *Ozone platform* should be `wayland`.
3. **`chrome://media-internals`.** Play a video of at least 720p (Chrome
   doesn't use the GPU for smaller videos), then open this page in a second tab
   and click the player. Check these entries:
   - `kVideoDecoderName`: `VaapiVideoDecoder` (or `VideoDecoderBroker`) means
     hardware. `FFmpegVideoDecoder`, `VpxVideoDecoder` or `Dav1dVideoDecoder`
     mean software.
   - `kIsPlatformVideoDecoder`: `true` means hardware.

   The same panel is in DevTools (Ctrl+Shift+I, menu > More tools > Media).

**YouTube on this laptop.** The HD 520 (Skylake) decodes H.264 in hardware, but
not VP9 or AV1. Chrome's VA-API code doesn't use the hybrid VP9 decoder on
Skylake, so YouTube's default VP9/AV1 streams play on the CPU. To get hardware
decode and a cool CPU, install the
[enhanced-h264ify](https://chromewebstore.google.com/detail/enhanced-h264ify/omkfmpieigblcllmkgbflkikinpkodlk)
extension and block VP9 and AV1 in its settings. YouTube then sends H.264
(up to 1080p).

## Signing in and sync

1. Open Chrome, click the profile icon (top right) and choose **Turn on sync**,
   or go to `chrome://settings/syncSetup`.
2. Sign in with your Google account. Bookmarks, passwords, history, extensions
   and open tabs sync over.
3. Choose what syncs at `chrome://settings/syncSetup/advanced`.

DOS has no desktop keyring (gnome-keyring or kwallet), so Chrome saves passwords
with its **basic** store in your profile (`~/.config/google-chrome`). They aren't
protected by a login password. Synced passwords are still encrypted on Google's
side. To store passwords in a keyring instead, install `gnome-keyring` and
unlock it at login.

## Troubleshooting

- `chrome` says "start the display first": sway isn't running. Start it, then
  run the command again.
- Chrome looks blurry or is slow to open: check that `chrome://gpu` says the
  Ozone platform is `wayland`.
- To reset the flags, delete `~/.config/chrome-flags.conf` and run `dos-update`.
