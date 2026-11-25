#!/usr/bin/env bash
# Shared helpers for DOS modules. Source it, don't run it:
#   source "$DOS_ROOT/lib/dos.sh"
# shellcheck disable=SC2034  # variables here are used by the scripts that source this file

DOS_ROOT="${DOS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DOS_STATE="${DOS_STATE:-$HOME/.local/state/dos}"
DOS_COMMANDS_DIR="${DOS_COMMANDS_DIR:-/usr/local/share/dos/commands}"
# DOS_TEST=1 is set in CI: skip anything that needs a screen, GPU, sound or a real login.
DOS_TEST="${DOS_TEST:-0}"

dos_log()  { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
dos_warn() { printf '\033[1;33m!! \033[0m %s\n' "$*" >&2; }
dos_die()  { printf '\033[1;31mxx \033[0m %s\n' "$*" >&2; exit 1; }

# Modules run as the normal user and use sudo for system changes.
dos_require_user() {
  [[ $EUID -ne 0 ]] || dos_die "run DOS modules as your user, not root (they use sudo when needed)."
}

# dos_pkg PKG... — install official-repo packages if missing.
dos_pkg() {
  local missing=() p
  for p in "$@"; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
  (( ${#missing[@]} == 0 )) && return 0
  dos_log "Installing: ${missing[*]}"
  sudo pacman -S --needed --noconfirm "${missing[@]}"
}

# dos_aur PKG... — install AUR packages with paru (bootstrapped on first use).
dos_aur() {
  dos_ensure_paru
  local missing=() p
  for p in "$@"; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
  (( ${#missing[@]} == 0 )) && return 0
  dos_log "Installing from AUR: ${missing[*]}"
  paru -S --needed --noconfirm --skipreview "${missing[@]}"
}

dos_ensure_paru() {
  command -v paru >/dev/null 2>&1 && return 0
  dos_log "Bootstrapping the paru AUR helper"
  dos_pkg base-devel git
  local tmp; tmp=$(mktemp -d)
  git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
  (cd "$tmp/paru-bin" && makepkg -si --noconfirm)
  rm -rf "$tmp"
}

# dos_command NAME — install commands/NAME from the repo as a DOS Shell command.
dos_command() {
  local name="$1" src="$DOS_ROOT/commands/$1"
  [[ -x $src ]] || dos_die "commands/$name is missing or not executable"
  sudo install -Dm755 "$src" "$DOS_COMMANDS_DIR/$name"
}

# dos_file SRC DEST [MODE] — install a file from the repo (system path, via sudo).
dos_file() {
  sudo install -Dm"${3:-644}" "$DOS_ROOT/$1" "$2"
}

# dos_done MODULE — record that a module finished (dos-update shows this).
dos_done() {
  mkdir -p "$DOS_STATE"
  date -Is > "$DOS_STATE/$1.done"
}
