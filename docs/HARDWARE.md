# Hardware notes

## Why XFCE lags

XFCE itself is light. The lag on this laptop most likely comes from these four
things, starting with the biggest:

1. **The disk (confirmed).** `sda` is a Toshiba MQ01ABD1, a 5400 rpm laptop
   HDD. Every app launch and every page swap waits on it. Software can only
   soften this (BFQ I/O scheduler, `noatime`, fewer background services).
2. **No swap at all.** With 8 GB, Chrome and Minecraft together fill RAM. With
   no swap the kernel drops cached files and then freezes or kills apps.
   Fix: zram, which is compressed swap in RAM and costs nothing.
3. **X11 with no compositor tuning.** Screen tearing and slow window redraws.
   A Wayland compositor (sway) draws through the GPU and stays smooth.
4. **A slow CPU.** The i3-6006U has no turbo boost and is capped at 2.0 GHz.
   The fixes are to keep background services to a minimum, use the
   `performance` energy setting when plugged in, and run thermald.

## Upgrades by value

| Upgrade | Rough cost | Effect |
|---------|-----------|--------|
| 2.5" SATA SSD (or M.2 SATA if the board has a slot), 256–512 GB | low | **Biggest change.** Boot and app launch go from tens of seconds to a few seconds. |
| A second 8 GB DDR4-2133 stick (16 GB total) | low | Chrome and Minecraft can run at the same time without swapping. Two sticks also give **dual-channel** memory, which roughly doubles iGPU speed in games. |
| Repaste the CPU and clean the fan | ~free | Stops thermal throttling during games. |

The CPU supports up to 32 GB of DDR4-2133. `collect-info.sh` reports how many RAM
slots the board has and whether one is empty.

## What gaming to expect (HD 520)

| Game | Expectation |
|------|-------------|
| Minecraft Java with Sodium (through Prism Launcher) | 40–60+ fps at 720p–900p, short render distance. Playable. |
| Minecraft without mods (official launcher) | 20–40 fps. Sodium matters a lot. |
| Light Epic titles (2D and indie games, older games) | Usually fine. |
| Fortnite | **Won't run**: its anti-cheat blocks Linux. |
| Modern 3D AAA free games | Mostly not playable on this GPU. |

Epic Games has no Linux client. Heroic Games Launcher is the native Linux front
end for your Epic library, and it runs the games through Wine/Proton.

## External monitor

HD 520 drives the laptop panel plus one external screen (HDMI, usually up to
4K at 30 Hz or 1080p at 60 Hz). Under sway, an extended desktop is a simple
config entry, and `kanshi` switches the layout when you plug the monitor in or
unplug it.

## Measured on 2026-11-25

- Disk: Toshiba MQ01ABD1 HDD (`rotational=1`).
- Swap: none. Chrome alone used about 4 GB of the 7.5 GB.
- Power: governor `powersave`, EPP `balance_performance`. thermald,
  power-profiles-daemon and tlp are all off.
- GPU: i915 with mesa 26.2. `vulkan-intel` and `intel-media-driver` are not
  installed, so Chrome decodes video on the CPU.
- Boot: GRUB on the shared 96 MB Windows ESP mounted at `/boot`, with 16 MB
  free. That's enough for one kernel. **Don't add a second kernel**
  (linux-zen and similar), because a full ESP breaks updates.
- Partitions: sda3 holds Windows (NTFS), sda4 Windows recovery, sda5 "New
  Volume" (NTFS data), and sda6 Arch (ext4).
- RAM slots: not yet checked (needs sudo). Run
  `sudo dmidecode -t memory | grep -E "Size|Locator"` to see whether a slot is
  free before buying RAM.
