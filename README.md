# DOS — Dhruv's Operating System

A light, Arch-based OS for the Lenovo ideapad 110-15ISK (i3-6006U, HD 520, 8 GB,
HDD). It ships as a single `.iso` file. Flash it to a pendrive with
balenaEtcher, boot from it, and it installs DOS next to Windows 10 and the
existing Arch. That gives a **triple boot**:

```
GRUB boot menu
├── DOS              ← new: sway, type-a-word app launcher, tuned for this laptop
├── Arch Linux       ← existing install (XFCE)
└── Windows 10       ← existing install
```

## What DOS includes

- The LiteBox speed base: zram swap, BFQ on the HDD, Intel Vulkan and VA-API
  drivers, thermald, performance power profile.
- A minimal sway session with no desktop. Type `chrome`, `spotify`,
  `minecraft` or `epic` and the app opens.
- Extended display over HDMI, with automatic monitor profiles (kanshi).
- Apps: Google Chrome, Spotify, Prism Launcher (Minecraft) and Heroic Games
  Launcher (Epic). Chrome and Spotify don't allow redistribution, so the
  installer downloads them from their official sources during setup instead of
  packing them into the ISO.

## How it works

1. **Build:** GitHub Actions builds the ISO with `archiso` inside an Arch Linux
   container, and attaches it to a GitHub Release.
2. **Flash:** download `DOS-<version>-x86_64.iso` and write it to the pendrive
   with balenaEtcher.
3. **Install:** boot the pendrive (F12 on the ideapad for the boot menu) and run
   `dos-install`. It shows the disk layout, installs only to the partition you
   confirm, and adds DOS to the existing GRUB menu. It never formats Windows or
   any partition you didn't pick.

## Status

| Step | What | State |
|------|------|-------|
| 0 | Repo, plan, CI | ✅ |
| 1 | archiso profile that boots to a shell | planned |
| 2 | ISO built in CI and attached to a release | planned |
| 3 | `dos-install`: safe install to a chosen partition + GRUB entry | planned |
| 4 | Speed base + sway session + launcher | planned |
| 5 | Apps + extended display | planned |

## License

MIT
