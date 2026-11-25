#!/usr/bin/env bash
# Run every DOS module (modules/*/install.sh) in name order, the way dos-update
# does, then a second time to check that each one is safe to re-run.
#
#   tests/run-modules.sh            as your user (needs sudo); DOS_TEST=1 by default
#   tests/run-modules.sh --ci       as root in a throwaway Arch container: creates
#                                   user dhruv with passwordless sudo, copies the
#                                   repo to /home/dhruv/dos and re-runs itself as dhruv
#   tests/run-modules.sh --once     skip the second (re-run) pass
#
# A module fails when it exits non-zero or doesn't record dos_done <module>.
# Works with zero modules. Exits 1 if any module failed.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI_USER=dhruv
passes=2
ci=0
for a in "$@"; do
  case $a in
    --ci) ci=1 ;;
    --once) passes=1 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

if (( ci )); then
  [[ $EUID -eq 0 ]] || { echo "--ci runs as root (in a container)" >&2; exit 2; }
  id -u "$CI_USER" >/dev/null 2>&1 || useradd -m -G wheel -s /bin/bash "$CI_USER"
  echo "$CI_USER ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-dos-ci
  chmod 0440 /etc/sudoers.d/90-dos-ci
  home=$(getent passwd "$CI_USER" | cut -d: -f6)
  rm -rf "$home/dos"
  cp -a "$repo" "$home/dos"
  chown -R "$CI_USER:" "$home/dos"
  once=(); (( passes == 1 )) && once=(--once)
  exec runuser -u "$CI_USER" -- env -i \
    HOME="$home" USER="$CI_USER" LOGNAME="$CI_USER" SHELL=/bin/bash \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/bin LANG=C.UTF-8 TERM="${TERM:-dumb}" \
    CI="${CI:-}" GITHUB_ACTIONS="${GITHUB_ACTIONS:-}" \
    DOS_TEST=1 DOS_ROOT="$home/dos" \
    bash "$home/dos/tests/run-modules.sh" "${once[@]}"
fi

[[ $EUID -ne 0 ]] || { echo "run as a normal user (modules use sudo), or use --ci as root" >&2; exit 2; }
export DOS_TEST="${DOS_TEST:-1}"
export DOS_ROOT="${DOS_ROOT:-$repo}"
export DOS_STATE="${DOS_STATE:-$HOME/.local/state/dos}"

shopt -s nullglob
mods=("$DOS_ROOT"/modules/*/install.sh)
shopt -u nullglob
if (( ${#mods[@]} == 0 )); then
  echo "No modules in $DOS_ROOT/modules: nothing to run."
  exit 0
fi
# Name order, independent of locale.
mapfile -t mods < <(printf '%s\n' "${mods[@]}" | LC_ALL=C sort)

logs=$(mktemp -d)
declare -A result
group()    { [[ -n ${GITHUB_ACTIONS:-} ]] && echo "::group::$*" || echo "=== $*"; }
endgroup() { [[ -n ${GITHUB_ACTIONS:-} ]] && echo "::endgroup::" || true; }

for (( pass = 1; pass <= passes; pass++ )); do
  for m in "${mods[@]}"; do
    name=$(basename "$(dirname "$m")")
    log="$logs/$name.$pass.log"
    rm -f "$DOS_STATE/$name.done"
    group "pass $pass: $name"
    start=$SECONDS rc=0
    (cd "$DOS_ROOT" && bash "$m" </dev/null) 2>&1 | tee "$log" || rc=${PIPESTATUS[0]}
    secs=$(( SECONDS - start ))
    endgroup
    if (( rc != 0 )); then
      status="FAIL (exit $rc)"
    elif [[ ! -f $DOS_STATE/$name.done ]]; then
      status="FAIL (no dos_done $name)"
    else
      status="ok"
    fi
    result[$name.$pass]="$status ${secs}s"
    [[ $status == ok ]] || echo "::error title=module $name (pass $pass)::$status"
  done
done

echo
echo "Module summary (DOS_TEST=$DOS_TEST)"
printf '  %-24s %-30s %s\n' MODULE "FIRST RUN" "$( (( passes == 2 )) && echo RE-RUN)"
failed=0
for m in "${mods[@]}"; do
  name=$(basename "$(dirname "$m")")
  r1=${result[$name.1]}; r2=${result[$name.2]:-}
  printf '  %-24s %-30s %s\n' "$name" "$r1" "$r2"
  [[ $r1 == ok* && ( $passes == 1 || $r2 == ok* ) ]] || failed=$((failed + 1))
done
echo
if (( failed )); then
  echo "$failed of ${#mods[@]} modules failed. Last lines of each failing run:"
  for key in "${!result[@]}"; do
    [[ ${result[$key]} == ok* ]] && continue
    echo "--- $key: ${result[$key]}"; tail -n 30 "$logs/$key.log"
  done
  exit 1
fi
echo "All ${#mods[@]} modules passed."
