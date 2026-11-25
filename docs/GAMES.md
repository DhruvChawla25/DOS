# Games on DOS (Epic through Heroic)

`DOS> epic` (or `DOS> games`) opens [Heroic Games Launcher](https://heroicgameslauncher.com/),
an open-source Epic, GOG and Amazon launcher. Windows games run through Proton
(GE-Proton), with Feral GameMode on. Module: `modules/60-epic`.

This page was checked on 2026-11-26. Laptop: i3-6006U (2 cores/4 threads,
2.0 GHz, no turbo), Intel HD 520, 7.5 GB RAM in **one** channel, 5400 rpm HDD.

## What the module sets up

| Part | What |
|------|------|
| `[multilib]` | Enabled in `/etc/pacman.conf` (backup: `/etc/pacman.conf.dos-bak.<date>`), then `pacman -Sy` |
| Packages | `heroic-games-launcher-bin` (AUR), `lib32-mesa`, `lib32-vulkan-intel`, `lib32-vulkan-icd-loader`, `vulkan-tools`, `gamemode`, `lib32-gamemode`, `jq` |
| GameMode | You are added to the `gamemode` group, so it can change the CPU governor without a password prompt (log in again once) |
| GE-Proton | The latest release from [GloriousEggroll/proton-ge-custom](https://github.com/GloriousEggroll/proton-ge-custom/releases), sha512 checked, unpacked to `~/.config/heroic/tools/proton/`, the folder Heroic scans for Proton builds |
| Heroic defaults | `~/.config/heroic/config.json`: install path `~/Games`, GameMode on, GE-Proton as the default Proton, "allow installation of games with broken or denied anticheat" on (needed to install GTA 5, see below). Written once; your later changes in Heroic are kept |

Check the GPU after install: `vulkaninfo --summary` should list
`Intel(R) HD Graphics 520 (SKL GT2)`.

### If GE-Proton was not preinstalled (no network during dos-update)

1. Heroic sidebar: **Wine Manager**, **GE-Proton** tab, download the newest one.
2. **Settings**, **Game Defaults**, **Wine Version**: pick that GE-Proton.

Install path and GameMode, if you ever need to set them by hand: **Settings**,
**General**, **Default Installation Path** = `~/Games`; **Settings**,
**Game Defaults**, **Other**, **Use GameMode**.

## GTA 5 (owned on Epic)

Owning GTA 5 on Epic gives you both editions in the library
([Epic help](https://www.epicgames.com/help/c-1/a202300000013575?lang=en-US)).
**Install Grand Theft Auto V Legacy**, not Enhanced:

| | Legacy | Enhanced |
|---|---|---|
| Minimum GPU (Steam page) | GeForce 9800 GT / Radeon HD 4870, DirectX 10/11 | GeForce GTX 1630 4 GB / Radeon RX 6400 4 GB |
| Storage | 125 GB | 105 GB, **SSD required** |
| On HD 520 | Playable at 720p, lowest settings | Below minimum on both GPU and disk |

### What works on Linux

- **Story mode works.** ProtonDB rates Legacy *Gold* (2,286 reports,
  [protondb.com/app/271590](https://www.protondb.com/app/271590)).
- **GTA Online does not.** Rockstar added BattlEye anti-cheat in September 2024
  and did not turn on BattlEye's Linux/Proton support, which BattlEye offers as
  an opt-in for developers
  ([GamingOnLinux](https://www.gamingonlinux.com/2024/09/grand-theft-auto-v-gets-battleye-anti-cheat-breaks-online-play-on-steam-deck-linux/)).
  It is still blocked in late 2026: [AreWeAntiCheatYet](https://areweanticheatyet.com/game/grand-theft-auto-v)
  lists GTA V as *Denied* with no change since 2024-09-17, Heroic's own wiki
  (edited 2026-11-24) says online "does NOT work on Linux nor MacOS and there's
  nothing that can be done to fix that"
  ([Heroic wiki](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/wiki/Rockstar-Games-from-Epic-Games)),
  and Linux players were still reporting the block on Steam's forum in February 2026.
  Hosts-file and fake-runtime tricks posted online are unreliable and risk a ban.
  **For Online, boot Windows 10 from the GRUB menu.**

### Installing it

1. `DOS> epic`, sign in to Epic.
2. Library: **Grand Theft Auto V Legacy**, **Install**. Heroic warns that the
   anti-cheat is denied (DOS already allowed this in settings). Confirm. Online
   won't work, story mode will.
3. Install to `~/Games` (default). See the disk section below for space.
4. First launch: Heroic downloads its umu/Steam runtime and creates
   the Proton prefix, then the **Rockstar Games Launcher** installs and asks you
   to sign in to your Rockstar account. Story mode needs this sign-in once and
   an internet connection for entitlement checks.

### Rockstar Launcher quirks under Proton

All from Heroic's [Rockstar Games from Epic Games](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/wiki/Rockstar-Games-from-Epic-Games)
wiki page unless noted.

- **Launcher says you don't own the game / offers to buy it.** Heroic 2.17+
  fixes this automatically on Linux. If it comes back: game settings,
  **Advanced**, **Environment Variables**, add `USE_FAKE_EPIC_EXE` = `true`.
- **Heroic refuses to install it ("Anticheat Broken/Denied").** Settings,
  **Advanced**, turn on "Allow installation of games with broken or
  denied anticheat". DOS sets this for you.
- **The launcher opens but the game doesn't start.** Leave the Rockstar
  Launcher open; it starts the game itself after loading. On this HDD the
  first start can take several minutes.
- **Enhanced only:** needs GE-Proton9-27 or newer; GE-Proton10-31 and 10-32
  failed to open the launcher (use 10-30). `ucrtbase.dll._strerror_s` error:
  delete the prefix and install `vcrun2019` via the game's **Winetricks**.
- **Anything online** (GTA Online, the online menu entries) is expected to
  fail. Stay in story mode.

### Expected fps on the HD 520

No measurement on this exact laptop yet, so this is an estimate.
The closest public data: an i5-6200U with HD 520 and 8 GB gets about
**30 fps at 1280x720, lowest settings** on Windows
([Tech Centurion](https://www.techcenturion.com/intel-hd-graphics-520-benchmark-review/)).
This laptop is slower than that: the i3-6006U has no turbo (2.0 GHz vs up to
2.8 GHz), single-channel RAM cuts the iGPU's memory bandwidth roughly in half,
and DXVK (DirectX 11 to Vulkan) costs some CPU. Expect:

- **about 20-30 fps** at 1280x720 in the countryside and indoors,
- **high teens** while driving fast through the city or in big shootouts,
- texture and building pop-in when driving fast (the HDD can't stream fast enough).

Adding a second RAM stick (dual channel) is the biggest cheap upgrade for this GPU.

### Best settings (in-game, Graphics)

| Setting | Value |
|---|---|
| DirectX version | DirectX 11 |
| Screen type | Fullscreen |
| Resolution | 1280x720 (try 1024x576 if it drops below 20) |
| VSync | Off |
| Population density / variety | lowest (CPU-bound on 2 cores) |
| Distance scaling | lowest |
| Texture, shader, shadow, reflection, water, particles, grass quality | Normal |
| Soft shadows | Sharp |
| FXAA, MSAA, reflection MSAA | Off |
| Post FX | Normal |
| Anisotropic filtering | Off or x2 |
| Ambient occlusion, tessellation | Off |
| Advanced Graphics | all off (long shadows, high-res shadows, high-detail streaming while flying, extended distance scaling) |
| Ignore suggested limits | On, only if the game won't let you pick these settings |

Leave GameMode on, and leave the laptop on mains power (it has no battery, so
it always is). Don't run Chrome in the background while playing: RAM is tight.

### The 110+ GB install on the HDD

- Budget **at least 125 GB free** (Rockstar's figure for Legacy) plus a few
  GB for the Proton prefix and runtime. Each 100 GB takes about 4.5 hours at
  50 Mbit/s.
- `dos-install` only needs 40 GB for DOS, so the default DOS partition is
  **too small for GTA 5**. Either make the DOS partition about 200 GB when
  installing DOS, or create a separate ext4 partition for games and mount it at
  `~/Games` (add it to `/etc/fstab`), then install there.
- Use **ext4**. Don't install to, or reuse the copy on, the Windows NTFS
  partition: Proton on NTFS breaks in many ways (permissions, case, symlinks;
  see Valve's [NTFS notes](https://github.com/ValveSoftware/Proton/wiki/Using-a-NTFS-disk-with-Linux-and-Windows)).
  Two copies (one per OS) cost 2 x 125 GB, so check free space first.
- Loading into story mode from the HDD takes a few minutes; that's the disk,
  not DOS.

## Other Epic games that suit this laptop

Light games, with Steam-version ProtonDB ratings (checked 2026-11-26).
They're all sold on Epic or were Epic free giveaways; run them through Heroic
the same way.

| Game | ProtonDB | Note |
|---|---|---|
| Hades | Platinum | 2D |
| Celeste | Platinum | 2D |
| Limbo | Platinum | 2D |
| Inside | Platinum | light 3D |
| Slime Rancher | Platinum | low settings |
| Overcooked | Gold | local co-op |
| BioShock Remastered | Gold | DX11, low settings, 720p |
| Subnautica | Platinum | the heaviest here: lowest settings, 720p |

Avoid online games with kernel or denied anti-cheat; they won't run on Linux.
**Fortnite** is *Denied* (Easy Anti-Cheat,
[AreWeAntiCheatYet](https://areweanticheatyet.com/game/fortnite)). Check any
multiplayer game on AreWeAntiCheatYet and ProtonDB before downloading.
