# Apps from other systems

DOS runs apps from the Arch repos, the AUR, Debian, Ubuntu, Fedora and Flathub.
Each one becomes a DOS command: install it once, then type its name at `DOS>`.

```
DOS> install --debian vlc
DOS> vlc                    VLC opens full screen, the prompt comes back
DOS> apps
NAME     SOURCE               PACKAGE
discord  Flathub              com.discordapp.Discord
vlc      debian (dos-debian)  vlc
DOS> remove vlc
```

Module `modules/70-apps` sets this up: Podman (rootless), Distrobox, Flatpak
with the Flathub remote for your user, and the `install`, `remove` and `apps`
commands.

## install

| Command | Where the app comes from |
|---------|--------------------------|
| `install <pkg>` | Arch repos (pacman). If the package isn't there, the AUR (paru). |
| `install --debian <pkg>` | Debian stable, in the `dos-debian` container |
| `install --ubuntu <pkg>` | Ubuntu 26.04 LTS, in `dos-ubuntu` |
| `install --fedora <pkg>` | Fedora (latest), in `dos-fedora` |
| `install --arch <pkg>` | Arch, in `dos-arch` (keeps a messy app off the DOS base) |
| `install --flatpak <app-id>` | Flathub, installed for your user only |
| `install --flatpak <term>` | Searches Flathub. A single match, or an app whose name is the term, is installed. Otherwise you pick from a list. |
| `install --search <term>` | Searches the Arch repos, the AUR, every container you already have, and Flathub |

Add `--name <cmd>` to pick the DOS command name, for example
`install --fedora --name gimp-fedora gimp`.

Examples:

```
install vlc                                  Arch package, command "vlc"
install visual-studio-code-bin              not in the repos, so it comes from the AUR
install --debian vlc                         command "vlc"
install --ubuntu libreoffice                 command "libreoffice"
install --fedora ripgrep                     CLI tool; "ripgrep" runs rg in the terminal
install --flatpak com.discordapp.Discord     command "discord"
install --flatpak "OBS Studio"               searches Flathub; exact name, so command "obs-studio"
install --search kdenlive                    look before you install
```

### Command names

- Arch, AUR and container apps use the package name (`vlc`).
- Flatpak apps use the app's own name from Flathub, lowercased with spaces
  turned into dashes (`Discord` becomes `discord`, `OBS Studio` becomes
  `obs-studio`). If an app has no name, DOS uses the last part of its ID.
- A name can't take over a built-in DOS command (`chrome`, `win`, ...) or an
  app from another source. Use `--name` in that case.

### Containers

The first `install --debian` (or `--ubuntu`, `--fedora`, `--arch`) makes the
container once, from the distro's official image on Docker Hub:

| Container | Image |
|-----------|-------|
| `dos-debian` | `docker.io/library/debian:stable` |
| `dos-ubuntu` | `docker.io/library/ubuntu:26.04` |
| `dos-fedora` | `docker.io/library/fedora:latest` |
| `dos-arch` | `docker.io/library/archlinux:latest` |

It's created with `distrobox-create --yes --no-entry --name dos-<distro> --image <image>`.
That keeps the containers light:

- Home is shared, so files you open or save are the normal ones in `~`.
- The Intel GPU (`/dev/dri`), sound and the Wayland display are shared, which
  Distrobox does by default. There's no `--nvidia` because the HD 520 is Intel.
- There's no `--init`, so no systemd runs inside. There's no menu entry either,
  because DOS has no menu.

Containers run on the DOS kernel, so apps run at native speed. Each container
costs disk space for its distro's base, which is about 100-300 MB plus its apps.

### GUI or CLI: how `install` decides

After the package is installed, `install` looks at what it brought. It checks
the package's own file list (`dpkg -L`, `rpm -ql` or `pacman -Qlq`) and, in
containers, also the files that appeared during this install. The second
check catches metapackages such as Debian's `vlc`.

1. If there's a visible desktop entry in `/usr/share/applications` (a `.desktop`
   file with `Type=Application` and without `NoDisplay=true` or `Hidden=true`),
   the package is a **GUI app**. The entry whose file name matches the package
   wins; otherwise the first one is used. Its `Exec=` line, without the
   `%U`-style placeholders, is the command.
2. If not, and the package has an executable in `/usr/bin` or `/usr/sbin`, it's
   a **CLI app**. The binary named like the package wins; otherwise the first
   one is used.
3. Otherwise (a library, for example) the package stays installed and is
   listed in `apps`, but no command is written.

All Flatpak apps are treated as GUI apps.

The heuristic is simple on purpose: the desktop entry is how a package says
"I have a window". If it picks the wrong binary, remove the app and run the
right command inside the container with `distrobox-enter --name dos-debian`.

### Export and the DOS command

- **GUI apps** are exported with
  `distrobox-export --app /usr/share/applications/<app>.desktop`, which puts
  `dos-<distro>-<app>.desktop` and its icons in `~/.local/share`. The DOS
  command starts the app detached with `swaymsg exec`, so it opens full
  screen and `DOS>` comes back. Without sway it prints "start the display
  first". Arguments such as file names, even ones with spaces, are passed on.
- **CLI apps** are exported with
  `distrobox-export --bin /usr/bin/<tool> --export-path ~/.local/share/dos/bin`
  and run inline in the DOS terminal. They go into DOS's own `bin` rather than
  `~/.local/bin`, so a container's `python3` can't shadow the DOS one.

The command is written to `~/.local/share/dos/commands/<name>`. Its second
line is `# help: <pkg> (from <distro>)`, so `help` lists it.

## apps

`apps` lists everything `install` added, with its source and package. The list
lives in `~/.local/share/dos/apps.tsv` and has one tab-separated row per app:

```
# name	source	package	export
vlc	debian	vlc	/usr/share/applications/vlc.desktop
discord	flatpak	com.discordapp.Discord	-
```

`source` is `pacman`, `aur`, `debian`, `ubuntu`, `fedora`, `arch` or
`flatpak`. `export` is the desktop file or binary exported from a container,
or `-`.

## remove

`remove <name>` undoes `install`:

| Source | What it runs |
|--------|--------------|
| Arch repos / AUR | `sudo pacman -Rns <pkg>` |
| Container | `distrobox-export --delete`, then apt `purge` + `autoremove`, `dnf remove` or `pacman -Rns` inside the container |
| Flatpak | `flatpak uninstall --user <id>`, then `--unused` to drop runtimes nothing needs |

Then it deletes the DOS command and the row in `apps.tsv`. You can also pass
the package name if only one app uses it (`remove com.discordapp.Discord`).

The container stays after its last app is removed, so the next install is
quick. To get the disk space back, run `distrobox-rm --force dos-debian`. The
next `install --debian` makes a new one.

## Setup details (module 70-apps)

- Packages: `podman`, `crun`, `distrobox`, `flatpak`. `crun` is named so pacman
  doesn't have to ask which OCI runtime to use.
- Rootless Podman: if your user has no line in `/etc/subuid` or `/etc/subgid`,
  the module adds 65536 IDs after the highest range in use (from 100000), then
  runs `podman system migrate`.
- Flathub: `flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`.
- With `DOS_TEST=1` (CI), the module installs the packages, the remote and the
  commands but makes no containers, and `install --<distro>` refuses to run.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `start the display first` | Start sway, then run the app command again |
| A container app has no sound or GPU | `distrobox-enter --name dos-debian -- ls /dev/dri` should list `card*` and `renderD*` |
| `podman` complains about subuid | Log out and in once after the module first runs |
| The AUR or an install asks for your password | It's `sudo` on DOS itself. Inside containers, sudo needs no password. |
