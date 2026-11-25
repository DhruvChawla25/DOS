#!/usr/bin/env bash
# Static checks of the module/command contract (docs/MODULES.md). No root, no Arch.
#   commands/<name>            executable, bash shebang, line 2 is "# help: <text>"
#   modules/NN-name/install.sh bash shebang, set -euo pipefail, sources lib/dos.sh,
#                              calls dos_require_user and dos_done
# Works with zero commands and zero modules.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
errors=0
err() { printf 'contract: %s\n' "$*" >&2; errors=$((errors + 1)); }

shopt -s nullglob
for c in commands/*; do
  [[ -f $c ]] || continue
  [[ -x $c ]] || err "$c is not executable (git update-index --chmod=+x $c)"
  [[ $(head -n1 "$c") == '#!/usr/bin/env bash' || $(head -n1 "$c") == '#!/bin/bash' ]] \
    || err "$c: first line must be a bash shebang"
  [[ $(sed -n 2p "$c") =~ ^#\ help:\ .+ ]] || err "$c: line 2 must be '# help: <one-line description>'"
done

for d in modules/*/; do
  d=${d%/}; m="$d/install.sh"; name=${d#modules/}
  [[ $name =~ ^[0-9][0-9]-[a-z0-9-]+$ ]] || err "$d: module directories are named NN-name"
  [[ -f $m ]] || { err "$d has no install.sh"; continue; }
  [[ $(head -n1 "$m") == '#!/usr/bin/env bash' ]] || err "$m: first line must be #!/usr/bin/env bash"
  grep -q '^set -euo pipefail' "$m" || err "$m: missing 'set -euo pipefail'"
  grep -q 'lib/dos\.sh' "$m"         || err "$m: doesn't source lib/dos.sh"
  grep -q 'dos_require_user' "$m"    || err "$m: doesn't call dos_require_user"
  grep -q 'dos_done' "$m"            || err "$m: doesn't call dos_done"
  grep -qE 'pacman +-Sy?u' "$m"      && err "$m: modules must not run pacman -Syu (dos-update does)"
done
shopt -u nullglob

if (( errors )); then echo "contract: $errors problem(s)" >&2; exit 1; fi
echo "contract: ok"
