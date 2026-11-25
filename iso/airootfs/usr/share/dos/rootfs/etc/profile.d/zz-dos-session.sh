# shellcheck shell=sh
# Start the display on tty1 once a module has installed it. Until then (a fresh
# base), you stay at the text prompt. Named zz- so the other login notices run first.
#
# The display module owns what starts: it installs /usr/local/bin/dos-session, and
# without that, plain sway runs if it's installed. Not exec'd: if the display fails
# or you quit it, you land at a normal shell on tty1 instead of a login loop.
# To stay at the text prompt on boot: touch ~/.config/dos/no-display
[ "$(tty)" = /dev/tty1 ] || return 0
case $- in *i*) ;; *) return 0 ;; esac
[ -z "${WAYLAND_DISPLAY:-}" ] || return 0
[ -e "${XDG_CONFIG_HOME:-$HOME/.config}/dos/no-display" ] && return 0
if [ -x /usr/local/bin/dos-session ]; then
  /usr/local/bin/dos-session
elif command -v sway >/dev/null 2>&1; then
  sway
fi
