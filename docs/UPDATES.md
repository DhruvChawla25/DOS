# How DOS is updated

The pendrive installs only the DOS base. Everything after that (display, apps,
the DOS Shell) is a module in this repo, and `dos-update` applies it. Nothing is
reflashed.

```
GitHub: DhruvChawla25/DOS (main)
        │  git pull --ff-only
        ▼
/opt/dos  (a clone, owned by dhruv)
        │  dos-update
        ├─ sudo pacman -Syu   (+ paru -Sua when paru exists)
        └─ modules/10-*/install.sh, 20-*, ... in name order, as dhruv
```

## First time

After the welcome steps (Wi-Fi with `nmtui`, sign in to `claude`):

```
gh auth login     GitHub.com, HTTPS, log in with a browser
dos-update        clones the private repo to /opt/dos and runs every module
```

If GitHub isn't signed in, `dos-update` prints `run: gh auth login` and stops.

## Running it

| Command | What it does |
|---------|--------------|
| `dos-update` | pull, full upgrade, run all modules |
| `dos-update --skip-system` | no `pacman -Syu`; just pull and run modules |
| `dos-update --only display` | run one module (`20-display` or `display`); repeatable |
| `dos-update --list` | each module and when it last finished |
| `dos-update --dry-run` | print every step, change nothing |
| `dos-update --yes` | no pacman/paru questions (automatic without a terminal) |
| `dos-update --check` | look for updates quietly (the daily timer runs this) |
| `dos-update --notice` | the "updates available" line, at most once a day |

Settings: `DOS_BRANCH` (default `main`), `DOS_DIR` (default `/opt/dos`),
`DOS_REPO` (default `DhruvChawla25/DOS`). For example, to try a branch before
it's merged: `DOS_BRANCH=claude dos-update --skip-system`.

Rules it follows:

- Runs as `dhruv` and refuses root. It uses `sudo` itself for pacman.
- The full upgrade runs once, first. Modules never run `pacman -Syu` themselves
  (see [MODULES.md](MODULES.md)).
- When a module fails, the rest still run. The summary at the end lists the
  modules that worked, the ones that failed and the time taken, and the exit code
  is 1. Each module's output is in `~/.local/state/dos/logs/<module>.log`. Retry
  one with `dos-update --skip-system --only <name>`.
- A module that finishes writes `~/.local/state/dos/<module>.done`, which
  `--list` shows.
- Only one `dos-update` runs at a time (a lock in `~/.local/state/dos`).
- The pull is fast-forward only. If `/opt/dos` has local changes or commits that
  aren't on GitHub, it stops and asks you to sort them out with git.

### dos-update updates itself

The source is `iso/airootfs/usr/share/dos/rootfs/usr/local/bin/dos-update`.
`scripts/dos-update` is a symlink to it, so there's only one copy. (The real file
has to be in the rootfs, because the ISO only carries `iso/airootfs`, and a
symlink pointing out of it would be broken there.) `dos-install` copies it to
`/usr/local/bin/dos-update`.

After each pull, if the repo's copy differs from the one running, `dos-update`
switches to the repo's copy for the rest of the run, and copies it over
`/usr/local/bin/dos-update`. A fix to `dos-update` therefore applies on the run
that pulls it.

The other base files (`/etc/profile.d/dos-*.sh`, the timer) are copied only
once, by `dos-install`. To change them on an installed DOS, a module has to
install the new version.

## "Updates available"

There's no background daemon. A systemd **user timer**,
`dos-update-check.timer`, runs `dos-update --check` 15 minutes after boot and
then once a day, at idle CPU and I/O priority. It runs `git fetch` (and
`checkupdates`, if pacman-contrib is installed) and writes what it found to
`~/.local/state/dos/updates-available`. It never installs anything and needs
no sudo.

At login, `/etc/profile.d/dos-update-notice.sh` reads that file and prints, at
most once a day:

```
DOS: updates available (2 DOS changes, 37 packages). Run: dos-update
```

A full `dos-update` clears it. To turn the check off:
`systemctl --user disable --now dos-update-check.timer`.

## Updating through Claude Code (Remote Control)

New features are written on the laptop itself by Claude Code, which you drive
from your phone or another computer with `/remote-control`. A change goes
through the same path as everything else:

1. **Ask Claude** in the Remote Control session, e.g. "add a `vlc` command".
2. **Claude works in `/opt/dos`** on the `claude` branch: it writes or edits a
   module under `modules/` (following [MODULES.md](MODULES.md)) and runs
   `shellcheck`. To try it before merging, you run
   `DOS_BRANCH=claude dos-update --skip-system --only <module>` at the laptop.
3. **Claude commits, pushes the `claude` branch and opens a pull request** with
   `gh pr create`. CI runs ShellCheck and the module tests. Claude never merges.
4. **You review and merge** the PR on GitHub.
5. **Apply it:** run `dos-update` at the laptop. It switches `/opt/dos`
   back to `main`, pulls the merge and runs the modules.

`main` is the only branch `dos-update` installs from by default, so nothing
reaches the laptop for good until you merge it. If an update breaks something,
revert the PR on GitHub and run `dos-update` again.

### sudo and Remote Control

`dos-update` and most modules need `sudo`. In a Remote Control session there's
no terminal to type the password into, so `sudo` fails with "a terminal is
required". So the split is:

- Claude can run `dos-update --list`, `dos-update --dry-run` and
  `dos-update --check` (no sudo) to see what an update would do.
- You run `dos-update` itself at the laptop, where you can type the password.

Claude Code must not change the sudo rules to get around the password.
