# shellcheck shell=sh
# DOS first-boot welcome, shown on tty1 until Claude Code is signed in.
[ "$(tty)" = /dev/tty1 ] || return 0
[ -f "$HOME/.claude.json" ] && return 0
cat <<'MSG'

  DOS base is installed. Three steps to finish:

    1. Wi-Fi:        nmtui
    2. Sign in:      claude          (follow the link it prints)
    3. Remote:       /remote-control (inside claude)

  After that, DOS updates arrive through Claude Code.

MSG
if ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
  echo "  Claude Code isn't installed yet. After Wi-Fi, run:"
  echo "    curl -fsSL https://claude.ai/install.sh | bash"
  echo
fi
