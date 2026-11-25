#!/usr/bin/env bash
# DOS module 40: Spotify, plus playerctl for the play/pause/next/prev commands.
#
# Why spotify-launcher (Arch "extra") and not the AUR "spotify" package:
#  - It's an official Arch package, so pacman installs it signed and prebuilt,
#    with no AUR build and no manual GPG key import.
#  - It downloads Spotify's own .deb from repository.spotify.com, checks it
#    against Spotify's signing key (shipped in the package), and unpacks it to
#    ~/.local/share/spotify-launcher/install. It checks for updates once a day
#    at launch, so Spotify stays current without rebuilding anything.
#  - The AUR package repackages the same .deb but has to be rebuilt through
#    paru for every Spotify release, and needs Spotify's GPG key imported by
#    hand (the PKGBUILD lists 7 rotated keys so far).
set -euo pipefail
# shellcheck source=../../lib/dos.sh source-path=SCRIPTDIR
source "$(dirname "$0")/../../lib/dos.sh"
dos_require_user

MODULE=40-spotify
HERE="modules/$MODULE"

dos_pkg spotify-launcher playerctl

# spotify-launcher reads ~/.config/spotify-launcher.conf before /etc.
CONF_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
install -Dm644 "$DOS_ROOT/$HERE/files/spotify-launcher.conf" "$CONF_HOME/spotify-launcher.conf"

# Limit Spotify's cache to 2 GB (storage.size, in MB, in Spotify's prefs file).
# Spotify keeps its other prefs in the same file, so only this line is changed.
PREFS="$CONF_HOME/spotify/prefs"
mkdir -p "$(dirname "$PREFS")"
touch "$PREFS"
if grep -q '^storage\.size=' "$PREFS"; then
  sed -i 's/^storage\.size=.*/storage.size=2048/' "$PREFS"
else
  printf 'storage.size=2048\n' >> "$PREFS"
fi

for cmd in spotify play pause next prev; do
  dos_command "$cmd"
done

# Download Spotify now so the first `spotify` opens quickly. spotify-launcher
# shows its progress bar with zenity, so this needs a running display. Without
# one (or in CI), the download happens on the first `spotify` instead.
if [[ $DOS_TEST == 1 ]]; then
  dos_log "DOS_TEST=1: not downloading Spotify"
elif [[ -n ${WAYLAND_DISPLAY:-} || -n ${DISPLAY:-} ]]; then
  dos_log "Downloading Spotify (first time only)"
  spotify-launcher --no-exec || dos_warn "Spotify download failed; it will retry on the first 'spotify'."
else
  dos_log "No display running: Spotify downloads on the first 'spotify'"
fi

dos_done "$MODULE"
