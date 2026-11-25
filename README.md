# DOS — Dhruv's Operating System

A fast, command-driven OS for the Lenovo ideapad 110-15ISK (i3-6006U, HD 520,
8 GB, HDD). There's no desktop. It boots straight to the DOS Shell:

```
DOS> chrome                 Google Chrome
DOS> spotify                Spotify
DOS> tlauncher              Minecraft (TLauncher)
DOS> epic                   Epic Games library (Heroic) — GTA 5 story mode
DOS> install vlc            apps from Arch, Debian, Ubuntu, Fedora or Flathub
DOS> win install setup.exe  Windows apps (Wine)
DOS> extend                 extend the display to the HDMI monitor
```

DOS uses the Linux kernel for hardware support, and everything you see is DOS.
See [docs/DESIGN.md](docs/DESIGN.md).

## Triple boot from a pendrive

DOS ships as a single `.iso`. Flash it with balenaEtcher, boot from it (F12 on
the ideapad), and run `dos-install`. It installs DOS next to the existing
systems:

```
GRUB boot menu
├── DOS
├── Arch Linux   (existing)
└── Windows 10   (existing)
```

The installer only writes to the partition you confirm. It never formats
Windows or any partition you didn't pick, and it puts nothing on the nearly full
EFI partition.

## Status

| Step | What | State |
|------|------|-------|
| 0 | Repo, CI, hardware check (`scripts/collect-info.sh`) | ✅ |
| 0.5 | Speed base for the current Arch (`scripts/01-speed-base.sh`) | ready, dry run passed |
| 1 | DOS live ISO built in CI with archiso (`scripts/build-iso.sh`) | in progress |
| 2 | DOS Shell (Rust): command prompt, app commands, `help` | planned |
| 3 | `dos-install`: safe install to a chosen partition + GRUB entry | planned |
| 4 | Display (sway, no desktop) + HDMI extend | planned |
| 5 | Apps: Chrome, Spotify, TLauncher, Heroic | planned |
| 6 | `install` (Distrobox / Flatpak) and `win` (Wine) | planned |

## Build the ISO yourself (on Arch)

```bash
sudo pacman -S archiso
sudo bash scripts/build-iso.sh   # ISO in out/
```

Version tags (`v0.1.0`) are built by GitHub Actions and attached to a release.

## License

MIT
