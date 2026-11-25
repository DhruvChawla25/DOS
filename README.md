# DOS — Dhruv's Operating System

A fast, command-driven OS for the Lenovo ideapad 110-15ISK (i3-6006U, HD 520,
8 GB, HDD). There's no desktop. It boots straight to the DOS Shell:

```
DOS> help                       every command, with a one-line description
DOS> chrome [url]  ·  web <words>   Google Chrome (hardware video decode)
DOS> spotify  ·  play · pause · next · prev
DOS> tlauncher  (or minecraft)  Minecraft through TLauncher, Java 8–25
DOS> epic  (or games)           Epic library through Heroic + GE-Proton (GTA 5 story mode)
DOS> install vlc                Arch / AUR
DOS> install --debian <pkg>     also --ubuntu, --fedora, --arch, --flatpak; then: apps, remove
DOS> win install setup.exe      Windows apps (Wine); win run · list · cmd · tricks · remove
DOS> extend · single · external · screens   HDMI monitor layouts
DOS> wifi · update · shutdown · reboot · sh
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
| 1 | DOS live ISO built in CI with archiso (`scripts/build-iso.sh`) | ✅ builds |
| 2 | `dos-install`: DOS base on a chosen partition + GRUB entry | written, not run on hardware |
| 3 | Claude Code in the base, `dos-update` | written, not run on hardware |
| — | **Everything below ships as modules through `dos-update`** | |
| 4 | DOS Shell (Rust) — [shell/](shell/) | ✅ 34 tests pass |
| 5 | Display: sway, no desktop, HDMI extend — [DISPLAY](docs/DISPLAY.md) | written |
| 6 | Chrome [·](docs/CHROME.md) Spotify [·](docs/SPOTIFY.md) TLauncher [·](docs/MINECRAFT.md) Epic/GTA 5 [·](docs/GAMES.md) | written |
| 7 | `install` — [APPS](docs/APPS.md), `win` — [WINDOWS](docs/WINDOWS.md) | written |

"Written" means checked with ShellCheck and CI but not yet run on the laptop.
See [docs/MODULES.md](docs/MODULES.md) for how modules and commands fit
together, and [docs/UPDATES.md](docs/UPDATES.md) for updates.

## How DOS is updated

The ISO only installs a small **DOS base**: kernel, drivers, network, speed
tuning and Claude Code. Every later feature is built on the laptop itself by
Claude Code, which is driven over Remote Control and commits each change to this
repo. That avoids rebuilding and reflashing the pendrive for every change.

## Build the ISO yourself (on Arch)

```bash
sudo pacman -S archiso
sudo bash scripts/build-iso.sh   # ISO in out/
```

Version tags (`v0.1.0`) are built by GitHub Actions and attached to a release.

## License

MIT
