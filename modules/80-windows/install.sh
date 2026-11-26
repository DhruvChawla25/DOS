#!/usr/bin/env bash
# DOS module 80-windows: Wine for Windows apps, and the `win` command.
#
# Arch's wine (extra) has been a pure WoW64 build since June 2025: a single
# 64-bit Wine runs 32-bit and 64-bit Windows programs, so it needs nothing from
# multilib. wine-mono (.NET) and wine-gecko (HTML) are still separate packages;
# with them installed, new prefixes set themselves up offline. Fonts
# (winetricks corefonts) are fetched per app by `win install`, not here.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../../lib/dos.sh
source "$(dirname "$0")/../../lib/dos.sh"
dos_require_user

packages=(
  wine wine-mono wine-gecko   # Wine itself, .NET (Mono) and the HTML engine (Gecko)
  winetricks                  # per-prefix extras: fonts, vcrun, dxvk, ...
  gnutls                      # TLS for installers and apps that go online
  libpulse                    # sound (Wine's PulseAudio driver -> PipeWire)
  gst-plugins-base gst-plugins-good   # video/audio playback in apps (mfplat)
  sdl2-compat                 # game controllers
  vulkan-icd-loader           # winevulkan; DXVK when an app opts in
)
dos_pkg "${packages[@]}"

dos_command win

if [[ $DOS_TEST == 1 ]]; then
  dos_log "DOS_TEST=1: Wine installed; no prefix is created at install time anyway"
else
  dos_log "$(wine --version 2>/dev/null || echo 'wine: not runnable yet') ready: try 'win install setup.exe'"
fi

dos_done 80-windows
