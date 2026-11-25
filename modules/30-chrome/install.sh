#!/usr/bin/env bash
# DOS module 30: Google Chrome (AUR "google-chrome"), Wayland + VA-API flags,
# Memory Saver policy, and the `chrome` and `web` commands.
set -euo pipefail
# shellcheck source=lib/dos.sh  # path from the repo root, where CI runs shellcheck
source "$(dirname "$0")/../../lib/dos.sh"
dos_require_user

here="$(cd "$(dirname "$0")" && pwd)"

# google-chrome is the AUR package for the Stable channel
# (https://aur.archlinux.org/packages/google-chrome). It installs the launcher
# /usr/bin/google-chrome-stable, which reads $XDG_CONFIG_HOME/chrome-flags.conf.
# libva-utils gives `vainfo` to check VA-API (see docs/CHROME.md).
dos_aur google-chrome
dos_pkg libva-utils

# Per-user flags file. Back up a copy that differs (e.g. hand edits) once.
conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
flags_src="$here/files/chrome-flags.conf"
flags_dst="$conf_dir/chrome-flags.conf"
if [[ -f $flags_dst ]] && ! cmp -s "$flags_src" "$flags_dst"; then
  dos_log "Saving your old $flags_dst as $flags_dst.bak"
  cp -f "$flags_dst" "$flags_dst.bak"
fi
install -Dm644 "$flags_src" "$flags_dst"

# Memory Saver on (balanced) and no background mode, as a Chrome policy.
# Google Chrome on Linux reads /etc/opt/chrome/policies/managed/*.json.
dos_file modules/30-chrome/files/dos-policy.json /etc/opt/chrome/policies/managed/dos.json

dos_command chrome
dos_command web

command -v google-chrome-stable >/dev/null 2>&1 \
  || dos_die "google-chrome-stable not found after install"

dos_done 30-chrome
