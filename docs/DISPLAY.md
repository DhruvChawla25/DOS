# DOS display

Login on tty1 starts sway. Workspace 1 is the DOS Shell (`DOS>`). Each app you
start opens full screen on its own workspace; close it and you're back at
`DOS>`. No bar, no wallpaper, no title bars.

## Keys

| Key | Does |
|-----|------|
| Super+Esc | back to the shell |
| Alt+Tab / Alt+Shift+Tab | next / previous app (the shell is in the cycle) |
| Super+Q | close the app |
| Super+F | toggle full screen |
| Super+Shift+C | reload the sway config |
| Super+Shift+E | leave the display, stay at the text console |
| Volume, mute, mic mute | PipeWire (`wpctl`) |
| Play/pause, next, previous | Spotify or any player (`playerctl`) |
| Brightness up/down | `brightnessctl` |

## Commands

| Command | Does |
|---------|------|
| `extend [left\|right\|above]` | laptop screen + HDMI monitor, monitor on that side (default right) |
| `single` | laptop screen only |
| `external` | HDMI monitor only |
| `screens` | list screens, current and available modes |

Plugging in a monitor extends to the right automatically (kanshi); unplugging
goes back to the laptop screen.

## When the display won't start

If sway fails 3 times in a row, tty1 stays at the text console. Then:

- `journalctl -b -t sway` shows why.
- `rm /tmp/dos-sway-fails-$(id -u); exec bash -l` tries again.
- `touch ~/.config/dos/no-display` turns autostart off.

## Files

| Where | What |
|-------|------|
| `~/.config/sway/config` | DOS-managed, rewritten by `dos-update` |
| `~/.config/sway/config.d/` | your own sway lines (kept) |
| `~/.config/kanshi/config` | hotplug profiles |
| `/etc/profile.d/dos-sway.sh` | tty1 autostart |
| `/usr/local/bin/dos-shell-loop` | keeps the shell terminal open |
| `/usr/local/bin/dos-sway-apps` | one full-screen workspace per app |
