# DOS design

DOS uses the Linux kernel for hardware support, and everything you see is DOS.
Android, ChromeOS and SteamOS are built the same way.

```
┌──────────────────────────────────────────────────────────┐
│ DOS Shell (Rust)    DOS> chrome · spotify · tlauncher     │
│                     epic · install · win · extend · help  │
├──────────────────────────────────────────────────────────┤
│ App layers                                                │
│  • Native: Chrome, Spotify, TLauncher (Java), Heroic       │
│  • Distrobox: Debian / Ubuntu / Arch / Fedora apps        │
│  • Wine: Windows .exe apps          • Proton: Epic games  │
├──────────────────────────────────────────────────────────┤
│ Display: sway, no bar and no desktop, apps full screen;   │
│          kanshi for HDMI extend · PipeWire for sound      │
├──────────────────────────────────────────────────────────┤
│ Base: Arch packages, systemd, zram, BFQ, Intel drivers    │
│ Kernel: Linux (stock Arch kernel, stored on the DOS root) │
└──────────────────────────────────────────────────────────┘
```

## Why the Linux kernel

A new kernel would need new drivers for the HD 520 GPU, Wi-Fi, USB, sound and
HDMI. Chrome, Spotify, Java and Epic would also need to be ported to it, and
the closed-source ones can't be. The lag on this laptop comes from the HDD, the
missing swap and a heavy desktop, not from the kernel.

## Boot (triple boot)

```
GRUB (on the shared Windows ESP, 16 MB free)
├── DOS          kernel + initramfs live on the DOS ext4 partition, not the ESP
├── Arch Linux   existing install
└── Windows 10   existing install
```

`dos-install` adds a single GRUB entry and copies nothing onto the ESP.

Boot runs straight to `DOS>`, with autologin on tty1. There's no display
manager and no splash screen.

## Running apps from other systems

| Source | How | DOS command |
|--------|-----|-------------|
| Arch repos / AUR | pacman / paru | `install <app>` |
| Debian, Ubuntu, Fedora | Distrobox container that shares home, GPU and sound | `install --debian <app>` |
| Flatpak (Flathub) | flatpak | `install --flatpak <app>` |
| Windows .exe | Wine, in its own prefix per app | `win install setup.exe`, `win run <app>`, `win cmd` |
| Epic games | Heroic Games Launcher + Proton | `epic` |

The containers run on the same kernel as DOS, so they run at native speed. The
only extra cost is disk space for each distro's base image.

## Games

- **GTA 5 (Epic):** runs through Heroic + Proton, Legacy edition, story mode
  only. GTA Online's BattlEye anti-cheat blocks Linux. Online works in the
  Windows 10 entry on the same boot menu.
- **Minecraft:** TLauncher, with Java from the DOS base.

## Speed budget (HDD, 8 GB)

| Item | Target |
|------|--------|
| Boot from GRUB to `DOS>` | under 15 s |
| RAM used at `DOS>` | under 400 MB |
| Background services | NetworkManager, PipeWire, thermald, power-profiles-daemon; nothing else |

## DOS base and updates

The pendrive installs only the **DOS base**:

| Part | Packages / setup |
|------|------------------|
| Kernel + firmware | linux, linux-firmware, intel-ucode |
| Network | networkmanager (`nmtui` for Wi-Fi) |
| Speed | zram-generator, BFQ rule, sysctl tuning, thermald, power-profiles-daemon (performance) |
| Graphics | mesa, vulkan-intel, intel-media-driver |
| User | `dhruv` with sudo, autologin on tty1 |
| Tools | git, github-cli, base-devel, nano |
| Claude Code | native installer, run on first boot as `dhruv` |

On first boot, DOS prints a short welcome: connect Wi-Fi (`nmtui`), run
`claude` once to sign in, then turn on `/remote-control`. From then on, DOS
updates are Claude Code sessions on the laptop, driven over Remote Control.
Each change is committed to this repo on the `claude` branch and merged by PR,
the same way as now.
