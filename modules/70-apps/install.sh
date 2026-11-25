#!/usr/bin/env bash
# 70-apps: run apps from other distros (Distrobox on rootless Podman) and
# from Flathub (Flatpak, per-user). Installs the install, remove and apps commands.
set -euo pipefail
# shellcheck source=../../lib/dos.sh
source "$(dirname "$0")/../../lib/dos.sh"
dos_require_user

# crun is named so pacman doesn't have to pick an oci-runtime provider itself.
dos_pkg podman crun distrobox flatpak

# Rootless Podman needs a range of sub-UIDs and sub-GIDs for the user.
# Hand out 65536 IDs after the highest range already in use (100000 at least).
user=$(id -un)
subids_changed=0
start=$(cat /etc/subuid /etc/subgid 2>/dev/null |
  awk -F: 'BEGIN { m = 100000 } NF == 3 && $2 + $3 > m { m = $2 + $3 } END { print m }')
end=$((start + 65535))
for f in /etc/subuid /etc/subgid; do
  if ! grep -q "^${user}:" "$f" 2>/dev/null; then
    dos_log "Giving $user sub-IDs $start-$end in $f (rootless Podman)"
    if [[ $f == /etc/subuid ]]; then
      sudo usermod --add-subuids "$start-$end" "$user"
    else
      sudo usermod --add-subgids "$start-$end" "$user"
    fi
    subids_changed=1
  fi
done
if (( subids_changed )) && [[ $DOS_TEST != 1 ]]; then
  # Restart any Podman processes so they pick up the new ID ranges.
  podman system migrate || dos_warn "podman system migrate failed; log out and back in"
fi

# Flathub, for this user only (no system-wide Flatpak installation).
if ! flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
  [[ $DOS_TEST == 1 ]] || dos_die "could not add the Flathub remote"
  dos_warn "could not add the Flathub remote (DOS_TEST=1, carrying on)"
fi

# Where `install` keeps wrappers, exported container binaries and the app list.
mkdir -p "$HOME/.local/share/dos/commands" "$HOME/.local/share/dos/bin"

dos_command install
dos_command remove
dos_command apps

dos_done 70-apps
