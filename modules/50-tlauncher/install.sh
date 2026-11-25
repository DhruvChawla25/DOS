#!/usr/bin/env bash
# Module 50: Minecraft through TLauncher, plus the Java runtimes Minecraft needs.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=../../lib/dos.sh
source "$(dirname "$0")/../../lib/dos.sh"
dos_require_user

# --- Java --------------------------------------------------------------------
# One runtime per Minecraft era, all official Arch packages that install side by
# side (each in /usr/lib/jvm/java-N-openjdk). The system default from
# archlinux-java is left alone; DOS picks the path it needs explicitly.
#   jre25-openjdk  Minecraft 26.1 and newer (Java 25 is the minimum since 26.1)
#   jre21-openjdk  Minecraft 1.20.5 - 1.21.x, and TLauncher itself
#   jre17-openjdk  Minecraft 1.17 - 1.20.4, i.e. most Forge modpacks
#   jre8-openjdk   Minecraft 1.16.5 and older, old Forge modpacks
# Full JREs (not -headless): TLauncher's window is Swing, and old LWJGL 2 /
# Forge versions use AWT too.
dos_pkg jre25-openjdk jre21-openjdk jre17-openjdk jre8-openjdk
# unzip unpacks the download; Java GUI apps and Minecraft run under XWayland.
dos_pkg unzip xorg-xwayland

# --- TLauncher ---------------------------------------------------------------
# Install source, and why:
# The AUR has one TLauncher package, "tlauncher-installer" (5 votes, one
# maintainer, last updated 2025-12). It repackages the upstream .deb from
# dl1.tlauncher.org, but declares no Java dependency, labels the closed-source
# launcher as MIT and pins a checksum that breaks whenever upstream changes the
# file. It adds a third party without adding any review, so DOS skips it.
# Instead DOS downloads the official Linux/macOS build (TLauncher.v*.zip, which
# holds TLauncher.jar) straight from tlauncher.org over HTTPS. Its download page
# lists https://tlauncher.org/jar as the Linux "direct" download. Any redirect
# must stay on HTTPS and on tlauncher.org, and the file must be a valid zip with
# a runnable jar inside, or nothing is installed.
# Note: after the first start, TLauncher's starter fetches its own core files
# from TLauncher's servers and keeps itself updated. DOS can't control that part.
TL_URL="https://tlauncher.org/jar"
TL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/dos/tlauncher"
TL_JAR="$TL_DIR/TLauncher.jar"
MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Official domain only: https://tlauncher.org/... or https://<sub>.tlauncher.org/...
tl_valid_url() {
  [[ $1 =~ ^https://([a-z0-9-]+\.)*tlauncher\.org(/[^[:space:]]*)?$ ]]
}

# Runs in a subshell so the temp dir is always cleaned up. Callers use
# `tl_download || ...`, which turns off set -e inside, so every step checks.
tl_download() (
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  dos_log "Downloading TLauncher from $TL_URL"
  final=$(curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 20 --max-time 300 --retry 3 \
    --output "$tmp/tlauncher.zip" --write-out '%{url_effective}' "$TL_URL") \
    || { dos_warn "TLauncher download failed"; exit 1; }
  tl_valid_url "$final" || { dos_warn "download left tlauncher.org ($final), refusing it"; exit 1; }
  unzip -tq "$tmp/tlauncher.zip" >/dev/null || { dos_warn "the download isn't a valid zip"; exit 1; }
  unzip -oq "$tmp/tlauncher.zip" -d "$tmp/x" || exit 1
  [[ -s $tmp/x/TLauncher.jar ]] || { dos_warn "TLauncher.jar is missing from the zip"; exit 1; }
  # No grep -q: it would close the pipe early and pipefail would flag unzip.
  unzip -p "$tmp/x/TLauncher.jar" META-INF/MANIFEST.MF | grep '^Main-Class:' >/dev/null \
    || { dos_warn "TLauncher.jar has no Main-Class"; exit 1; }
  # Copy next to the target, then rename, so a half-written jar never replaces a good one.
  install -m644 "$tmp/x/TLauncher.jar" "$TL_JAR.new" && mv -f "$TL_JAR.new" "$TL_JAR" || exit 1
  if [[ -f $tmp/x/README-EN.txt ]]; then install -m644 "$tmp/x/README-EN.txt" "$TL_DIR/README-EN.txt"; fi
  sha256sum "$TL_JAR" | cut -d' ' -f1 > "$TL_DIR/TLauncher.jar.sha256"
  date -Is > "$TL_DIR/downloaded-at"
  dos_log "TLauncher installed in $TL_DIR"
)

tl_valid_url "$TL_URL" || dos_die "TLauncher URL isn't on https://tlauncher.org: $TL_URL"
mkdir -p "$TL_DIR"
# Tuned JVM arguments for the game (paste into TLauncher settings, see docs/MINECRAFT.md).
install -m644 "$MODULE_DIR/files/jvm-args.txt" "$TL_DIR/jvm-args.txt"

# TLauncher updates itself, so download only when it's missing.
# DOS_TLAUNCHER_REFRESH=1 forces a fresh copy (for example if the jar is broken).
if [[ -f $TL_JAR && ${DOS_TLAUNCHER_REFRESH:-0} != 1 ]]; then
  dos_log "TLauncher is already installed"
elif [[ $DOS_TEST == 1 ]]; then
  # CI: the URL format is checked above; the network may be flaky, so a failed
  # download is only a warning here.
  tl_download || dos_warn "DOS_TEST: skipped the TLauncher download"
else
  tl_download || dos_die "couldn't install TLauncher, run dos-update again later"
fi

dos_command tlauncher
dos_command minecraft
dos_done 50-tlauncher
