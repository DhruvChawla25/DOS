#!/usr/bin/env bash
# 60-epic: Epic Games through Heroic Games Launcher + Proton (GE-Proton) + GameMode.
# shellcheck source-path=SCRIPTDIR
# Main target: GTA 5 Legacy, story mode. See docs/GAMES.md.
#
# Steps (all safe to run again):
#   1. enable [multilib] in /etc/pacman.conf (backup first) and refresh the dbs
#   2. 32-bit Mesa/Vulkan for Proton, GameMode, vulkan-tools, Heroic (AUR)
#   3. put the user in the gamemode group (no polkit agent on DOS, so no prompts)
#   4. preinstall the latest GE-Proton into Heroic's tools folder (skipped with DOS_TEST=1)
#   5. Heroic defaults in config.json: install path ~/Games, GameMode on (first run only)
#   6. install the `epic` and `games` commands
set -euo pipefail
# shellcheck source=../../lib/dos.sh
source "$(dirname "$0")/../../lib/dos.sh"
dos_require_user

PACMAN_CONF=/etc/pacman.conf
HEROIC_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/heroic"
HEROIC_CONFIG="$HEROIC_DIR/config.json"
PROTON_DIR="$HEROIC_DIR/tools/proton"
GAMES_DIR="$HOME/Games"
GE_API=https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest

# --- 1. multilib -------------------------------------------------------------
enable_multilib() {
  if pacman-conf --repo-list | grep -qx multilib; then
    return 0
  fi
  local backup
  backup="$PACMAN_CONF.dos-bak.$(date +%Y%m%d-%H%M%S)"
  dos_log "Enabling [multilib] in $PACMAN_CONF (backup: $backup)"
  sudo cp -a "$PACMAN_CONF" "$backup"
  if grep -qE '^[[:space:]]*#[[:space:]]*\[multilib\][[:space:]]*$' "$PACMAN_CONF"; then
    # Stock Arch file: uncomment "#[multilib]" and the "#Include" line right after it.
    sudo sed -i -E '/^[[:space:]]*#[[:space:]]*\[multilib\][[:space:]]*$/,/^[[:space:]]*#?[[:space:]]*Include/ s/^[[:space:]]*#[[:space:]]*//' "$PACMAN_CONF"
  else
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a "$PACMAN_CONF" >/dev/null
  fi
  if ! pacman-conf --repo-list | grep -qx multilib; then
    sudo cp -a "$backup" "$PACMAN_CONF"
    dos_die "could not enable [multilib]; restored $PACMAN_CONF from $backup"
  fi
  # Only fetches the package lists (multilib's is new). dos-update did -Syu just before.
  sudo pacman -Sy
}

# --- 4. GE-Proton --------------------------------------------------------------
ge_proton_installed() {
  local d
  for d in "$PROTON_DIR"/GE-Proton*/; do
    [[ -x ${d}proton ]] && return 0
  done
  return 1
}

# Newest GE-Proton install path (for Heroic's wineVersion), or nothing.
ge_proton_newest() {
  local d
  d=$(find "$PROTON_DIR" -mindepth 1 -maxdepth 1 -type d -name 'GE-Proton*' 2>/dev/null | sort -V | tail -n1)
  [[ -n $d && -x $d/proton ]] && printf '%s\n' "$d"
  return 0
}

# Runs in a subshell so the EXIT trap cleans up the download folder.
install_ge_proton() (
  if ge_proton_installed; then
    dos_log "GE-Proton already in $PROTON_DIR (update it in Heroic: Wine Manager)"
    return 0
  fi
  if [[ $DOS_TEST == 1 ]]; then
    dos_log "DOS_TEST=1: skipping the GE-Proton download (~600 MB)"
    return 0
  fi
  dos_log "Downloading the latest GE-Proton from GitHub (~600 MB)"
  local json tag tar_url sum_url work
  if ! json=$(curl -fsSL "$GE_API"); then
    dos_warn "could not reach GitHub; install GE-Proton in Heroic instead (docs/GAMES.md)"
    return 0
  fi
  tag=$(jq -r '.tag_name' <<<"$json")
  # Assets are GE-ProtonX-Y-x86_64.tar.gz since 11-x, GE-ProtonX-Y.tar.gz before.
  tar_url=$(jq -r --arg t "$tag" '.assets[] | select(.name == ($t + "-x86_64.tar.gz") or .name == ($t + ".tar.gz")) | .browser_download_url' <<<"$json" | head -n1)
  sum_url=$(jq -r --arg t "$tag" '.assets[] | select(.name == ($t + "-x86_64.sha512sum") or .name == ($t + ".sha512sum")) | .browser_download_url' <<<"$json" | head -n1)
  if [[ -z $tag || -z $tar_url || -z $sum_url ]]; then
    dos_warn "unexpected GE-Proton release layout ($tag); install it in Heroic instead"
    return 0
  fi

  mkdir -p "$PROTON_DIR" "$HOME/.cache/dos"
  work=$(mktemp -d "$HOME/.cache/dos/ge-proton.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  if ! curl -fL --retry 3 -o "$work/${tar_url##*/}" "$tar_url" ||
     ! curl -fsSL --retry 3 -o "$work/${sum_url##*/}" "$sum_url"; then
    dos_warn "GE-Proton download failed; install it in Heroic instead"
    return 0
  fi
  if ! (cd "$work" && sha512sum -c --status "${sum_url##*/}"); then
    dos_warn "GE-Proton checksum mismatch; not installing it"
    return 0
  fi
  # Unpack next to the final folder, then move it in, so Heroic never sees half a Proton.
  mkdir "$work/x"
  tar -xzf "$work/${tar_url##*/}" -C "$work/x"
  local top
  top=$(find "$work/x" -mindepth 1 -maxdepth 1 -type d | head -n1)
  [[ -n $top && -x $top/proton ]] || { dos_warn "GE-Proton archive has no proton script"; return 0; }
  mv "$top" "$PROTON_DIR/"
  dos_log "Installed $(basename "$top") into $PROTON_DIR"
)

# --- 5. Heroic defaults ------------------------------------------------------------
# Format verified in Heroic v2.22.4 src/backend/config.ts (GlobalConfigV0):
#   { "defaultSettings": { ...AppSettings }, "version": "v0" }
# Missing keys fall back to Heroic's factory defaults, except winePrefix and
# defaultWinePrefixDir, so a fresh file must set those two as well.
write_heroic_defaults() {
  local marker="$DOS_STATE/epic-heroic-defaults"
  local ge wine_json=null
  ge=$(ge_proton_newest)
  if [[ -n $ge ]]; then
    wine_json=$(jq -n --arg bin "$ge/proton" --arg name "$(basename "$ge")" \
      '{bin: $bin, name: $name, type: "proton"}')
  fi

  if pgrep -x heroic >/dev/null 2>&1; then
    dos_warn "Heroic is running; close it and run dos-update again to write its defaults"
    return 0
  fi
  mkdir -p "$HEROIC_DIR"

  if [[ ! -f $HEROIC_CONFIG ]]; then
    dos_log "Writing Heroic defaults to $HEROIC_CONFIG"
    local prefixes="$HOME/Games/Heroic/Prefixes"
    jq -n --arg games "$GAMES_DIR" --arg prefixes "$prefixes" --argjson wine "$wine_json" '
      { defaultSettings: ({
          defaultInstallPath: $games,
          defaultWinePrefix: $prefixes,
          defaultWinePrefixDir: $prefixes,
          winePrefix: ($prefixes + "/shared"),
          useGameMode: true,
          allowInstallationBrokenAnticheat: true
        } + (if $wine == null then {} else {wineVersion: $wine} end)),
        version: "v0" }' >"$HEROIC_CONFIG.tmp"
    mv "$HEROIC_CONFIG.tmp" "$HEROIC_CONFIG"
    mkdir -p "$DOS_STATE" && touch "$marker"
    return 0
  fi

  if ! jq -e '.defaultSettings | type == "object"' "$HEROIC_CONFIG" >/dev/null 2>&1; then
    dos_warn "$HEROIC_CONFIG has an unknown format; set the defaults in Heroic (docs/GAMES.md)"
    return 0
  fi

  # Existing file: DOS defaults only once, so later changes made in Heroic stay.
  # The default Proton is set on every run, but only if the current one is gone.
  local first=false cur_bin
  [[ -f $marker ]] || first=true
  cur_bin=$(jq -r '.defaultSettings.wineVersion.bin // ""' "$HEROIC_CONFIG")
  [[ -n $cur_bin && -e $cur_bin ]] && wine_json=null
  jq --arg games "$GAMES_DIR" --argjson wine "$wine_json" --argjson first "$first" '
    .defaultSettings |= (
      (if $first then . + {defaultInstallPath: $games, useGameMode: true,
                           allowInstallationBrokenAnticheat: true} else . end)
      | (if $wine != null then .wineVersion = $wine else . end))' \
    "$HEROIC_CONFIG" >"$HEROIC_CONFIG.tmp"
  if ! cmp -s "$HEROIC_CONFIG" "$HEROIC_CONFIG.tmp"; then
    cp -a "$HEROIC_CONFIG" "$HEROIC_CONFIG.dos-bak"
    mv "$HEROIC_CONFIG.tmp" "$HEROIC_CONFIG"
    dos_log "Updated Heroic defaults in $HEROIC_CONFIG (backup: config.json.dos-bak)"
  else
    rm -f "$HEROIC_CONFIG.tmp"
  fi
  mkdir -p "$DOS_STATE" && touch "$marker"
}

# --- run ---------------------------------------------------------------------------
enable_multilib

# Proton needs the 32-bit Mesa/Vulkan drivers even for 64-bit games (its 32-bit
# helpers and launchers). lib32-vulkan-intel pulls lib32-vulkan-icd-loader.
dos_pkg lib32-mesa lib32-vulkan-intel lib32-vulkan-icd-loader \
        vulkan-tools gamemode lib32-gamemode jq curl
dos_aur heroic-games-launcher-bin

if getent group gamemode >/dev/null && ! id -nG "$USER" | tr ' ' '\n' | grep -qx gamemode; then
  dos_log "Adding $USER to the gamemode group (takes effect at next login)"
  sudo usermod -aG gamemode "$USER"
fi

mkdir -p "$GAMES_DIR"
install_ge_proton
write_heroic_defaults

dos_command epic
dos_command games

dos_done 60-epic
