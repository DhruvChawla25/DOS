#!/usr/bin/env bash
# DOS module 20: the display. sway (no bar, one full-screen app per workspace),
# Xwayland, kanshi for HDMI, autostart on tty1, and the display commands.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=../../lib/dos.sh
source "$(dirname "$0")/../../lib/dos.sh"
dos_require_user

files="modules/20-display/files"

# sway + Xwayland (Spotify, Java, Wine), kanshi (hotplug), portal (screen share,
# file pickers), jq (dos-sway-apps and the commands), brightnessctl and
# playerctl (keys).
dos_pkg sway xorg-xwayland kanshi xdg-desktop-portal-wlr jq brightnessctl playerctl

# Helpers started by the sway config.
dos_file "$files/bin/dos-shell-loop.sh" /usr/local/bin/dos-shell-loop 755
dos_file "$files/bin/dos-sway-apps.sh"  /usr/local/bin/dos-sway-apps 755

# Start sway on tty1 at login.
dos_file "$files/profile.d/dos-sway.sh" /etc/profile.d/dos-sway.sh

# User configs (DOS-managed; local additions go in ~/.config/sway/config.d/).
install -Dm644 "$DOS_ROOT/$files/sway/config"   "$HOME/.config/sway/config"
install -Dm644 "$DOS_ROOT/$files/kanshi/config" "$HOME/.config/kanshi/config"
mkdir -p "$HOME/.config/sway/config.d"

# brightnessctl changes the backlight through logind or the video group.
if ! id -nG | tr ' ' '\n' | grep -qx video; then
  sudo usermod -aG video "$(id -un)"
fi

for c in extend single external screens; do dos_command "$c"; done

if [[ $DOS_TEST == 1 ]]; then
  dos_log "DOS_TEST=1: not touching a running sway"
elif [[ -n ${SWAYSOCK:-} ]] && swaymsg -q -t get_version 2>/dev/null; then
  swaymsg -q reload || dos_warn "sway reload failed; check ~/.config/sway/config"
fi

dos_done 20-display
