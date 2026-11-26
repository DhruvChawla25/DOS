#!/usr/bin/env bash
# DOS: one app per workspace, full screen. Started by the sway config.
#  - a new window of any app (Wayland app_id or XWayland class; only the
#    dos-shell foot window is exempt) moves to the lowest free workspace from
#    2 up, gets focus and goes full screen. Dialogs stay over their app;
#    X11 windows sway floated only for a fixed size (Java, Wine) are tiled;
#  - when a window closes and leaves the focused workspace empty, go back to
#    workspace 1 (the shell).
set -u

free_workspace() {
  swaymsg -t get_workspaces | jq -r '[.[].num] as $used
    | first(range(2; 100) | select(. as $n | $used | any(.[]; . == $n) | not))'
}

on_new() {
  local id=$1 app=$2 kind=$3 ws unfloat=
  [[ $app == dos-shell || $kind == dialog ]] && return 0
  [[ $kind == float ]] && unfloat="[con_id=$id] floating disable; "
  ws=$(free_workspace) || return 0
  [[ -n $ws ]] || return 0
  swaymsg -q "${unfloat}[con_id=$id] move container to workspace number $ws; workspace number $ws; [con_id=$id] fullscreen enable"
}

on_close() {
  local empty
  # A focused workspace with no windows is itself the focused node.
  empty=$(swaymsg -t get_tree | jq -r 'first(.. | objects
    | select(.type == "workspace" and .focused == true
             and (.nodes | length) == 0 and (.floating_nodes | length) == 0)
    | .num) // empty')
  if [[ -n $empty && $empty != 1 ]]; then
    swaymsg -q workspace number 1
  fi
}

# Re-subscribe if the stream drops; stop when sway is gone.
while swaymsg -q -t get_version 2>/dev/null; do
  swaymsg -t subscribe -m '["window"]' \
    | jq --unbuffered -r 'select(.change == "new" or .change == "close")
        | [.change, .container.id,
           (.container.app_id // .container.window_properties.class // "-"),
           (.container as $c
            | if $c.type != "floating_con" then "tiled"
              elif $c.shell == "xwayland"
                   and ($c.window_properties.transient_for // null) == null
                   and (($c.window_properties.window_type // "normal")
                        | IN("normal", "unknown"))
              then "float"
              else "dialog" end)] | @tsv' \
    | while IFS=$'\t' read -r change id app kind; do
        case $change in
          new)   on_new "$id" "$app" "$kind" ;;
          close) on_close ;;
        esac
      done
  sleep 1
done
