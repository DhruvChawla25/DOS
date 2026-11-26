#!/usr/bin/env bash
# DOS: keep the DOS Shell terminal open on workspace 1. Started by the sway
# config; restarts the terminal whenever it exits and stops when sway does.
set -u

while swaymsg -q -t get_version 2>/dev/null; do
  start=$SECONDS
  if command -v dos-shell >/dev/null 2>&1; then
    foot --app-id dos-shell -- dos-shell
  else
    # The DOS Shell isn't built yet: give a plain shell instead of nothing.
    foot --app-id dos-shell -- bash
  fi
  # Don't spin if the terminal fails straight away.
  (( SECONDS - start < 3 )) && sleep 3
done
