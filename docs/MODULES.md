# DOS modules and commands (contract)

All features after the DOS base ship as **modules**. `dos-update` pulls this repo
to `/opt/dos` and runs every module in name order. Each module must be safe to
run again and again.

## Layout

```
lib/dos.sh                  shared helpers (dos_pkg, dos_aur, dos_command, dos_file, dos_log, dos_done)
modules/NN-name/install.sh  one feature; NN sets the order (10, 20, ...)
modules/NN-name/files/...   config files the module installs
commands/<name>             DOS Shell command, an executable script
shell/                      the DOS Shell (Rust crate)
tests/                      CI tests (Arch container, DOS_TEST=1)
```

## Module rules

- Starts with `#!/usr/bin/env bash`, `set -euo pipefail`, then
  `# shellcheck source=SCRIPTDIR/../../lib/dos.sh` on the line above
  `source "$(dirname "$0")/../../lib/dos.sh"`, then calls `dos_require_user`.
- Uses `dos_pkg` (official repos) and `dos_aur` (AUR, via paru). Never runs
  `pacman -Syu` itself: dos-update does the full upgrade once, first.
- Doesn't touch `/boot`, the ESP, partitions or other operating systems.
- Ends with `dos_done <module-name>`.
- With `DOS_TEST=1` (CI), skips anything that needs a display, GPU, audio or a
  login, but still installs packages and files, so CI catches broken package
  names.

Module numbers:

| NN | Module | Owner |
|----|--------|-------|
| 10 | base-extras (pipewire, fonts, foot terminal) | display |
| 20 | display (sway, kanshi, autostart shell) | display |
| 30 | chrome | chrome |
| 40 | spotify | spotify |
| 50 | tlauncher (+ Java 8/17/21/25) | tlauncher |
| 60 | epic (Heroic + Proton + GameMode) | epic |
| 70 | apps (Distrobox + Podman + Flatpak, `install` command) | apps |
| 80 | windows (Wine, `win` command) | windows |
| 90 | shell (build + install the DOS Shell) | shell |

## Command rules

- The DOS Shell looks up a typed name as: built-in → `~/.local/share/dos/commands/`
  (`DOS_USER_COMMANDS_DIR`, per-user wrappers from `install` and `win`) →
  `/usr/local/share/dos/commands/` (`DOS_COMMANDS_DIR`) → anything on `PATH`.
- `commands/<name>` is an executable script (bash) that the DOS Shell runs
  when you type `<name> [args]`. Modules install it to
  `/usr/local/share/dos/commands/` with `dos_command <name>`.
- The second line is `# help: <one-line description>`. The shell's `help`
  command lists these lines.
- GUI apps must start detached from the shell and full screen under sway, so
  the prompt comes back. Use `swaymsg exec -- <app>` when `$SWAYSOCK` is set,
  otherwise print "start the display first" and exit 1.
- Exit 0 on success, and print a one-line error and exit 1 on failure.
