# shellcheck shell=sh
# DOS first-boot welcome on tty1. Lists the setup steps and goes away once
# Claude Code is signed in, GitHub is signed in and /opt/dos has been fetched.
[ "$(tty)" = /dev/tty1 ] || return 0
_dos_claude=0; [ -f "$HOME/.claude.json" ] && _dos_claude=1
_dos_gh=0;     [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/gh/hosts.yml" ] && _dos_gh=1
_dos_repo=0;   [ -d /opt/dos/.git ] && _dos_repo=1
if [ "$_dos_claude$_dos_gh$_dos_repo" != 111 ]; then
  _dos_net=0; [ -n "$(ip route show default 2>/dev/null)" ] && _dos_net=1
  _dos_mark() { if [ "$1" = 1 ]; then printf '[x]'; else printf '[ ]'; fi; }
  cat <<MSG

  DOS base is installed. Finish setting it up:

    $(_dos_mark "$_dos_net") 1. Wi-Fi     nmtui
    $(_dos_mark "$_dos_claude") 2. Claude    claude           sign in with the link it prints,
                                      then type /remote-control
    $(_dos_mark "$_dos_gh") 3. GitHub    gh auth login    GitHub.com, HTTPS, log in with a browser
    $(_dos_mark "$_dos_repo") 4. Update    dos-update       fetches DOS and installs every feature

  After the first dos-update, log out (or reboot) and the DOS display
  starts on tty1. Later, run dos-update whenever DOS says updates are available.

MSG
  if ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
    echo "  Claude Code isn't installed yet. After Wi-Fi, run:"
    echo "    curl -fsSL https://claude.ai/install.sh | bash"
    echo
  fi
  unset -f _dos_mark
  unset _dos_net
fi
unset _dos_claude _dos_gh _dos_repo
