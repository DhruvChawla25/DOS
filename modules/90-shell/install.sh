#!/usr/bin/env bash
# Module 90: build the DOS Shell (shell/) and install it as /usr/local/bin/dos-shell.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../../lib/dos.sh
source "$(dirname "$0")/../../lib/dos.sh"
dos_require_user

dos_pkg rust

# Build outside the repo so /opt/dos stays clean (and may be read-only for us).
export CARGO_TARGET_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dos/shell-target"

dos_log "Building the DOS Shell"
(cd "$DOS_ROOT/shell" && cargo build --release --locked)

built="$CARGO_TARGET_DIR/release/dos-shell"
dest=/usr/local/bin/dos-shell
"$built" --version >/dev/null || dos_die "the new dos-shell doesn't run"

if cmp -s "$built" "$dest"; then
  dos_log "dos-shell is up to date"
else
  sudo install -Dm755 "$built" "$dest"
  dos_log "Installed $("$dest" --version)"
fi

dos_done 90-shell
