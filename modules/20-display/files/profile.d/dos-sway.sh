# shellcheck shell=sh
# DOS: start the display (sway) on tty1 at login. Installed by modules/20-display.
#
# Escape hatches:
#   - Super+Shift+E in sway leaves it cleanly; you stay at the text console.
#   - If sway fails 3 times in a row, the login stays at the text console.
#   - touch ~/.config/dos/no-display to never start it automatically.

[ "$(tty)" = /dev/tty1 ] || return 0
[ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ] || return 0
[ "${DOS_TEST:-0}" = 1 ] && return 0
[ -e "$HOME/.config/dos/no-display" ] && return 0
command -v sway >/dev/null 2>&1 || return 0

# /tmp survives logouts but is cleared at boot, so every boot gets 3 tries.
dos_sway_fails="/tmp/dos-sway-fails-$(id -u)"
dos_sway_n=$(cat "$dos_sway_fails" 2>/dev/null) || dos_sway_n=0
case $dos_sway_n in '' | *[!0-9]*) dos_sway_n=0 ;; esac

if [ "$dos_sway_n" -ge 3 ]; then
  echo
  echo "  The display failed to start 3 times; staying at the text console."
  echo "  See why:   journalctl -b -t sway"
  echo "  Try again: rm $dos_sway_fails; exec bash -l"
  echo
  unset dos_sway_fails dos_sway_n
  return 0
fi

export XDG_CURRENT_DESKTOP=sway XDG_SESSION_DESKTOP=sway XDG_SESSION_TYPE=wayland
# Java (TLauncher) draws blank windows under sway without this.
export _JAVA_AWT_WM_NONREPARENTING=1

dos_sway_start=$(date +%s)
# Log to the journal (RAM-buffered) rather than a file on the HDD.
if command -v systemd-cat >/dev/null 2>&1; then
  systemd-cat -t sway sway
else
  sway >/dev/null 2>&1
fi
dos_sway_rc=$?

if [ "$dos_sway_rc" -eq 0 ]; then
  # Left on purpose (Super+Shift+E): stay here.
  rm -f "$dos_sway_fails"
  echo "  Display closed. Type 'sway' to start it again."
  unset dos_sway_fails dos_sway_n dos_sway_start dos_sway_rc
  return 0
fi

# A crash after a long session isn't a failed start.
[ $(( $(date +%s) - dos_sway_start )) -gt 60 ] && dos_sway_n=0
echo $(( dos_sway_n + 1 )) > "$dos_sway_fails"
# Log out; getty logs in again on tty1 and this file tries once more.
exit "$dos_sway_rc"
