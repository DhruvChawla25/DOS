# Windows apps in DOS (`win`)

DOS runs Windows programs with [Wine](https://www.winehq.org/). Wine isn't an
emulator or a virtual machine. It translates Windows calls into Linux calls, so
an app that works runs at about native speed. Many apps work, some work after a
tweak, and some never will (see [Limits](#limits)).

## Quick start

```
DOS> win install ~/Downloads/npp.8.6.4.Installer.x64.exe
Command name for this app [npp]: notepad
Creating a Wine prefix in ~/.local/share/dos/wine/notepad ...
Adding Windows core fonts (winetricks corefonts)...
Running the installer. Finish it in its window; DOS waits until it closes.
Start this program for the app: Program Files/Notepad++/notepad++.exe [Y/n]
Installed. Type 'notepad' at DOS> to start it.

DOS> notepad
```

## Commands

| Command | What it does |
|---------|--------------|
| `win install <setup.exe\|.msi> [name]` | New 64-bit prefix for the app, core fonts, runs the installer, then asks which program starts the app and makes `<name>` a DOS command |
| `win run <name\|file.exe> [args]` | Starts an installed app, or any `.exe`/`.msi`/`.bat`/`.lnk` file |
| `win list` | Installed Windows apps and the program each one starts |
| `win remove <name>` | Deletes the app, its prefix and its DOS command (you type the name to confirm) |
| `win tricks <name> <verbs...>` | Runs [winetricks](https://github.com/Winetricks/winetricks) in that app's prefix |
| `win cmd [name]` | Windows command prompt (`wine cmd`) in a full-screen foot terminal; `exit` returns to DOS |
| `win config <name>` | Wine settings (`winecfg`) for that app: Windows version, audio, drives, DLL overrides |

### How `win install` finds the program

After the installer closes (DOS waits for every Wine process in the prefix),
`win` looks for files the installer added: Start Menu and Desktop shortcuts
(`.lnk`) first, then `.exe` files under `C:\Program Files` and
`C:\Program Files (x86)`, newest first. Uninstallers, updaters, crash
reporters and redistributables are skipped. If there's one match it asks you to
confirm it. If there are several it lists them and you pick one. If the setup
file installed nothing (a portable app), `win` offers to use the file itself.

The choice is saved in `~/.local/share/dos/wine/<name>/dos-app.conf`:

```
NAME=notepad
EXE=/home/dhruv/.local/share/dos/wine/notepad/drive_c/Program Files/Notepad++/notepad++.exe
INSTALLED=2026-11-26T18:02:11+05:30
# GAMEMODE=1 starts the app under gamemoderun (if installed).
```

Edit `EXE=` to point at a different program, or add `GAMEMODE=1` for games.
The DOS command is a three-line script in `~/.local/share/dos/commands/<name>`
that runs `win run <name>`.

### Examples

```
win install ~/Downloads/7z2408-x64.exe 7zip         # 7-Zip
win install ~/Downloads/IrfanView.msi irfanview     # an .msi
win run ~/Downloads/putty.exe                       # portable .exe, shared prefix
win run notepad C:\\users\\dhruv\\notes.txt          # extra arguments go to the app
win tricks irfanview vcrun2022                      # Visual C++ 2015-2022 runtime
win tricks myapp dotnet48                           # real .NET Framework 4.8 (slow to install)
win tricks oldgame d3dx9 dxvk                       # DirectX 9 helpers + DXVK
win config oldgame                                  # e.g. set "Windows 7" for an old app
win cmd                                             # C:\> prompt in the shared prefix
win cmd notepad                                     # C:\> prompt inside notepad's prefix
win remove 7zip
```

## How it's set up

- **Packages** (module `80-windows`): `wine`, `wine-mono`, `wine-gecko`,
  `winetricks`, plus `gnutls` (TLS), `libpulse` (sound through PipeWire),
  `gst-plugins-base` and `gst-plugins-good` (media playback),
  `sdl2-compat` (controllers) and `vulkan-icd-loader`. All are in Arch's
  `extra` repo.
- **Pure WoW64.** Since June 2025, Arch's `wine` is a pure WoW64 build: one
  64-bit Wine runs both 32-bit and 64-bit Windows programs, without multilib
  `lib32-*` packages. Every prefix is 64-bit (`WINEARCH=win64`). Wine 11 no
  longer supports pure 32-bit prefixes (`WINEARCH=win32`).
- **One prefix per app** in `~/.local/share/dos/wine/<name>`. A runtime that
  one app needs can't break another app, and `win remove` deletes the whole
  prefix. `win run file.exe` and `win cmd` without a name share a hidden
  prefix at `~/.local/share/dos/wine/.default`.
- **Fonts at first use.** `winetricks corefonts` (Arial, Times New Roman,
  Verdana, Courier New and others) is installed into each new prefix by
  `win install`. The downloads are cached in `~/.cache/winetricks`, so only the
  first app needs the internet for them. If you're offline, add them later with
  `win tricks <name> corefonts`.
- **Mono and Gecko** come from the Arch packages, so new prefixes don't
  download anything or show "install Mono?" dialogs.
- **No desktop clutter.** `winemenubuilder` is turned off, so Wine doesn't
  write `.desktop` files, menus or file associations. DOS has no desktop, and
  the DOS command is the launcher.
- **Logs** of running apps go to `~/.local/state/dos/wine/<name>.log`. The
  installer log is `~/.local/share/dos/wine/<name>/.dos-install.log`.
- **Display.** Apps use Wine's X11 driver through XWayland under sway. Wine 11's
  Wayland driver is still marked experimental upstream, so DOS doesn't use it.

## Performance on the ideapad (i3-6006U, HD 520, HDD)

| Setting | Choice | Why |
|---------|--------|-----|
| `WINEDEBUG=-all` | on, always | Debug output costs CPU and HDD writes |
| esync / fsync | not used | Mainline Wine never had them (they're Proton and wine-staging patches). Wine 11 uses the kernel's **NTSync** (`/dev/ntsync`, Linux 6.14+) automatically. Arch's `wine` pulls in `ntsync-autoload`, which loads the module |
| DXVK | off by default, opt in per app | See below |
| GameMode | opt in: `GAMEMODE=1` in `dos-app.conf` | Only helps games, and only if the `epic` module installed `gamemode` |
| Separate prefixes | yes | A new prefix with fonts takes about 300–500 MB on disk and a minute or two to create on the HDD. That only happens at install |

**DXVK** turns Direct3D 9/10/11 into Vulkan. On Intel it's usually much faster
than Wine's built-in OpenGL path for **3D games**, and the HD 520 runs Mesa's
`anv` Vulkan driver. Current DXVK needs Vulkan 1.4 and Mesa 25.1 or newer; Mesa
25.0 brought Vulkan 1.4 to `anv`. Check on the laptop with
`vulkaninfo --summary` (from `vulkan-tools`). DXVK is off by default because:

- ordinary apps (editors, tools, office programs) don't use Direct3D, so
  DXVK adds nothing for them;
- the first run of a game compiles shaders, which stutters, and the shader
  cache costs extra reads on the 5400 rpm disk;
- some older Direct3D 9 games run better on Wine's own renderer.

For a 3D game, try it and compare: `win tricks <game> dxvk`. To undo it, open
`win config <game>`, go to *Libraries* and remove the `d3d9`, `d3d10core`,
`d3d11` and `dxgi` overrides. For Direct3D 12, winetricks `vkd3d` installs
vkd3d-proton, but the HD 520 is too slow for most D3D12 games anyway.

Other tips:

- Close Chrome before running a heavy app. RAM is the tightest resource here.
- An app that's slow only on its first start is usually the HDD filling the
  page cache. The second start is faster.

## Limits

Be realistic. Wine runs a lot of software, but not everything:

- **Anti-cheat games don't work** when the anti-cheat runs in the kernel or
  blocks Linux: Valorant (Vanguard), most BattlEye and Easy Anti-Cheat titles
  whose developers haven't enabled Linux support (e.g. GTA Online), FACEIT,
  Call of Duty's Ricochet. Use the Windows 10 entry in the boot menu for those.
- **Kernel drivers can't be installed.** Wine runs user-space code only, so
  hardware tools that ship a `.sys` driver don't work: VPN clients, some USB
  devices, RGB/fan utilities, phone flashing tools, antivirus.
- **Some DRM and copy protection fails**: old disc protection (SecuROM,
  StarForce, SafeDisc), some licence managers and dongles.
- **Microsoft 365 / new Office, Adobe Creative Cloud** and other apps that
  depend on recent Windows services are unreliable or don't work. Old
  standalone Office versions (2010–2016) often work with tweaks.
- **Store (UWP/MSIX) apps** don't install. Wine runs classic `.exe` and `.msi`
  programs.
- **Windows shell extensions, services and system tweaks** have no effect
  outside the app's prefix.
- **Performance** is limited by the hardware. The HD 520 manages light and
  older 3D games, not new AAA titles.
- **Full screen.** sway shows apps full screen. Apps with many small floating
  windows (old toolbars, palettes) can feel awkward. If an app misbehaves, try
  *Emulate a virtual desktop* in `win config <name>` → *Graphics*.

### Before you install, check

- **[WineHQ AppDB](https://appdb.winehq.org/)**: reports for apps, rated
  Platinum (works out of the box) to Garbage (doesn't work), often with the
  winetricks verbs that fix them.
- **[ProtonDB](https://www.protondb.com/)**: reports for games. They're for
  Proton (Valve's Wine), so a game rated Gold there may need DXVK
  (`win tricks <game> dxvk`) to match under plain Wine. Epic games are
  better run through the `epic` command (Heroic + Proton).
- **[areweanticheatyet.com](https://areweanticheatyet.com/)**: whether a
  game's anti-cheat runs on Linux.

## Troubleshooting

| Problem | Try |
|---------|-----|
| App doesn't start | Read `~/.local/state/dos/wine/<name>.log`. To see Wine's errors, run it once from a bash prompt with `WINEDEBUG=err+all win run <name>` |
| Missing `MSVCP140.dll` / `VCRUNTIME140.dll` | `win tricks <name> vcrun2022` |
| .NET app crashes on start | `win tricks <name> dotnet48` (Wine Mono covers many but not all .NET apps) |
| Text is boxes or the wrong font | `win tricks <name> corefonts` (also `cjkfonts` for Chinese/Japanese/Korean) |
| App wants "Windows 7/8" | `win config <name>` → *Applications* → Windows version |
| Wrong program starts | Edit `EXE=` in `~/.local/share/dos/wine/<name>/dos-app.conf` |
| Everything is broken | `win remove <name>` and install again. Other apps aren't affected |
