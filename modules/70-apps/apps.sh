# shellcheck shell=bash
# Helpers shared by the install, remove and apps commands. Source it after
# lib/dos.sh:
#   source "$DOS_ROOT/modules/70-apps/apps.sh"
# shellcheck disable=SC2034  # variables here are used by the commands that source this file

DOS_DATA="${DOS_DATA:-$HOME/.local/share/dos}"
DOS_USER_COMMANDS="${DOS_USER_COMMANDS:-$DOS_DATA/commands}"
DOS_APP_BIN="$DOS_DATA/bin"        # binaries exported from containers (kept off $PATH)
DOS_APPS="$DOS_DATA/apps.tsv"      # one row per app: name, source, package, export

# ---------------------------------------------------------------- distros ---

# apps_image DISTRO — the official image for a Distrobox container.
apps_image() {
  case $1 in
    debian) echo docker.io/library/debian:stable ;;
    ubuntu) echo docker.io/library/ubuntu:26.04 ;;   # newest LTS (April 2026)
    fedora) echo docker.io/library/fedora:latest ;;
    arch)   echo docker.io/library/archlinux:latest ;;
    *) return 1 ;;
  esac
}

apps_is_distro() { apps_image "$1" >/dev/null 2>&1; }
apps_container() { echo "dos-$1"; }

# apps_manager DISTRO — package database the probe reads: dpkg, rpm or pacman.
apps_manager() {
  case $1 in
    debian|ubuntu) echo dpkg ;;
    fedora) echo rpm ;;
    arch|pacman|aur) echo pacman ;;
  esac
}

apps_container_exists() { podman container exists "$(apps_container "$1")" 2>/dev/null; }

# apps_in DISTRO CMD... — run a command inside the distro's container.
apps_in() {
  local c; c=$(apps_container "$1"); shift
  distrobox-enter --name "$c" -- "$@"
}

# shellcheck disable=SC2016  # "$1" belongs to the inner sh -c script
# apps_pkg DISTRO install|remove PKG — install or remove a package in a container.
apps_pkg() {
  local distro=$1 action=$2 pkg=$3
  case $distro/$action in
    debian/install|ubuntu/install)
      apps_in "$distro" sh -c 'sudo apt-get update && sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$1"' sh "$pkg" ;;
    debian/remove|ubuntu/remove)
      apps_in "$distro" sh -c 'sudo env DEBIAN_FRONTEND=noninteractive apt-get purge -y "$1" && sudo apt-get autoremove -y' sh "$pkg" ;;
    fedora/install) apps_in "$distro" sudo dnf install -y "$pkg" ;;
    fedora/remove)  apps_in "$distro" sudo dnf remove -y "$pkg" ;;
    # Inside the container a full upgrade is fine: it doesn't touch DOS.
    arch/install)   apps_in "$distro" sudo pacman -Syu --needed --noconfirm "$pkg" ;;
    arch/remove)    apps_in "$distro" sudo pacman -Rns --noconfirm "$pkg" ;;
  esac
}

# ------------------------------------------------------------------ probe ---
# A POSIX sh script that runs inside the container (or on the host for
# pacman/AUR installs) and works out what a package gave us:
#   probe snapshot                    print every .desktop file and binary
#   probe detect PKG MANAGER BEFORE   (BEFORE is a snapshot file, or - for none)
#                                     print one line:
#       gui<TAB>/usr/share/applications/x.desktop<TAB>Exec command
#       cli<TAB>/usr/bin/x
#       none
# Candidates are the files the package owns, then the files that appeared
# since the BEFORE snapshot (this catches metapackages such as Debian's vlc).
# A visible desktop entry (Type=Application, not NoDisplay or Hidden) means a
# GUI app. Otherwise the app is a CLI tool in /usr/bin or /usr/sbin. A name
# that matches the package wins over the first match.
# shellcheck disable=SC2016  # $vars below belong to the inner sh script
APPS_PROBE='
snapshot() {
  find /usr/share/applications -maxdepth 1 -name "*.desktop" 2>/dev/null
  find /usr/bin /usr/sbin -maxdepth 1 ! -type d 2>/dev/null
}
owned() {
  case $2 in
    dpkg)   dpkg -L "$1" ;;
    rpm)    rpm -ql "$1" ;;
    pacman) pacman -Qlq "$1" ;;
  esac 2>/dev/null | sed -e "s|^/bin/|/usr/bin/|" -e "s|^/sbin/|/usr/sbin/|"
}
pick() {  # pick PKG < paths: exact basename, then basename containing PKG, then first
  awk -v p="$1" '\''
    { n = $0; sub(/.*\//, "", n); sub(/\.desktop$/, "", n); l = tolower(n) }
    l == tolower(p) && !e { e = $0 }
    index(l, tolower(p)) && !c { c = $0 }
    !f { f = $0 }
    END { print (e ? e : (c ? c : f)) }'\''
}
visible() {
  while IFS= read -r d; do
    [ -f "$d" ] || continue
    grep -qx "Type=Application" "$d" || continue
    grep -Eqx "(NoDisplay|Hidden)=true" "$d" && continue
    printf "%s\n" "$d"
  done
}
case $1 in
  snapshot) snapshot ;;
  detect)
    pkg=$2 mgr=$3 before=$4
    cands=$( {
      owned "$pkg" "$mgr"
      [ "$before" = - ] || snapshot | grep -vxF -f "$before"
    } | awk "!seen[\$0]++")
    desk=$(printf "%s\n" "$cands" | grep -E "^/usr/share/applications/[^/]+\.desktop$" | visible | pick "$pkg")
    if [ -n "$desk" ]; then
      ex=$(awk "/^\\[/ { s = (\$0 == \"[Desktop Entry]\") } s && /^Exec=/ { sub(/^Exec=/, \"\"); print; exit }" "$desk" |
        sed -e "s/ *%[fFuUdDnNickvm]//g")
      if [ -n "$ex" ]; then printf "gui\t%s\t%s\n" "$desk" "$ex"; exit 0; fi
    fi
    bin=$(printf "%s\n" "$cands" | grep -E "^/usr/s?bin/[^/]+$" |
      while IFS= read -r b; do [ -x "$b" ] && [ ! -d "$b" ] && printf "%s\n" "$b"; done | pick "$pkg")
    if [ -n "$bin" ]; then printf "cli\t%s\n" "$bin"; else echo none; fi ;;
esac
'

# apps_probe WHERE ARGS... — WHERE is a distro name, or "host".
apps_probe() {
  local where=$1; shift
  if [[ $where == host ]]; then
    sh -c "$APPS_PROBE" probe "$@"
  else
    apps_in "$where" sh -c "$APPS_PROBE" probe "$@"
  fi
}

# --------------------------------------------------------------- app list ---

# apps_rows — print the rows of apps.tsv (no comments, no blank lines).
apps_rows() {
  [[ -f $DOS_APPS ]] || return 0
  grep -v -e '^#' -e '^[[:space:]]*$' "$DOS_APPS" || true
}

# apps_get NAME — print the row for NAME, or fail.
apps_get() {
  apps_rows | awk -F'\t' -v n="$1" '$1 == n { print; f = 1; exit } END { exit !f }'
}

# apps_add NAME SOURCE PACKAGE EXPORT — add or replace the row for NAME.
apps_add() {
  apps_del "$1"
  mkdir -p "$DOS_DATA"
  [[ -f $DOS_APPS ]] || printf '# name\tsource\tpackage\texport\n' > "$DOS_APPS"
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:--}" >> "$DOS_APPS"
}

# apps_del NAME — drop the row for NAME.
apps_del() {
  [[ -f $DOS_APPS ]] || return 0
  local tmp; tmp=$(mktemp "$DOS_APPS.XXXXXX")
  awk -F'\t' -v n="$1" '$1 != n' "$DOS_APPS" > "$tmp"
  mv "$tmp" "$DOS_APPS"
}

# apps_name TEXT — turn TEXT into a DOS command name (lowercase, a-z 0-9 . _ -).
apps_name() {
  local n
  n=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-')
  n=${n#-}; n=${n%-}
  printf '%s' "$n"
}

# -------------------------------------------------------------- wrappers ---

# apps_wrapper NAME HELP KIND CMD — write ~/.local/share/dos/commands/NAME.
# CMD is already shell-quoted; the user's arguments are appended to it.
# KIND gui: starts detached through `swaymsg exec`. The arguments travel in a
#           NUL-separated file so spaces, quotes and commas survive sway's
#           command parser.
# KIND cli: runs inline in the DOS Shell's terminal.
apps_wrapper() {
  local name=$1 help=$2 kind=$3 cmd=$4 file="$DOS_USER_COMMANDS/$1"
  mkdir -p "$DOS_USER_COMMANDS"
  {
    printf '#!/usr/bin/env bash\n'
    printf '# help: %s\n' "$help"
    printf '# Written by the install command; "remove %s" deletes it.\n' "$name"
    printf 'set -euo pipefail\n'
    if [[ $kind == gui ]]; then
      cat <<EOF
if [[ \${1-} == --dos-run ]]; then
  mapfile -d '' -t args < "\$2"
  rm -f "\$2"
  exec $cmd "\${args[@]}"
fi
if [[ -z \${SWAYSOCK:-} ]]; then
  echo "start the display first" >&2
  exit 1
fi
argv=\$(mktemp "\${XDG_RUNTIME_DIR:-/tmp}/dos-$name.XXXXXX")
(( \$# == 0 )) || printf '%s\\0' "\$@" > "\$argv"
swaymsg -q exec -- $(printf '%q' "$file") --dos-run "\$argv" || {
  rm -f "\$argv"
  echo "$name: sway could not start it" >&2
  exit 1
}
EOF
    else
      printf 'exec %s "$@"\n' "$cmd"
    fi
  } > "$file.tmp"
  chmod 755 "$file.tmp"
  mv "$file.tmp" "$file"
}

# apps_check_name NAME SOURCE PACKAGE — fail if NAME belongs to something else.
apps_check_name() {
  local name=$1 row
  [[ $name =~ ^[a-z0-9][a-z0-9._-]*$ ]] || dos_die "'$name' isn't a usable command name; pick one with --name"
  if [[ -e $DOS_COMMANDS_DIR/$name ]]; then
    dos_die "'$name' is already a DOS command; pick another name with --name"
  fi
  if row=$(apps_get "$name"); then
    IFS=$'\t' read -r _ s p _ <<<"$row"
    [[ $s == "$2" && $p == "$3" ]] ||
      dos_die "'$name' is already installed from $s ($p); run 'remove $name' or pick another name with --name"
  elif [[ -e $DOS_USER_COMMANDS/$name ]]; then
    dos_die "$DOS_USER_COMMANDS/$name already exists; pick another name with --name"
  fi
}
