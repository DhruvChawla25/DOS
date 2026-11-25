# shellcheck shell=sh
# "DOS: updates available" at login, at most once a day. The daily user timer
# (dos-update-check.timer) does the looking; this only reads its result, so it's instant.
case $- in *i*) ;; *) return 0 ;; esac
[ -f "$HOME/.local/state/dos/updates-available" ] || return 0
[ -x /usr/local/bin/dos-update ] && /usr/local/bin/dos-update --notice
