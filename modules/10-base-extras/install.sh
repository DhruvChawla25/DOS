#!/usr/bin/env bash
# DOS module 10: sound (PipeWire), the foot terminal, a small font set, xdg-utils.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=../../lib/dos.sh
source "$(dirname "$0")/../../lib/dos.sh"
dos_require_user

here="$DOS_ROOT/modules/10-base-extras"

# Sound: PipeWire with the PulseAudio shim (Chrome, Spotify, Wine use it) and WirePlumber.
dos_pkg pipewire pipewire-pulse wireplumber
# Terminal, fonts, xdg-open.
dos_pkg foot ttf-dejavu noto-fonts xdg-utils

# foot config for the DOS Shell terminal.
install -Dm644 "$here/files/foot.ini" "$HOME/.config/foot/foot.ini"

if [[ $DOS_TEST == 1 ]]; then
  dos_log "DOS_TEST=1: not enabling or starting PipeWire"
else
  # Socket activation for every user; works without a running session.
  sudo systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service
  # Start them now if this user's systemd instance is reachable.
  if systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber.service \
      || dos_warn "could not start PipeWire now; it starts at next login"
  fi
fi

dos_done 10-base-extras
