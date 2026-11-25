# Spotify on DOS

```
DOS> spotify          open Spotify full screen
DOS> spotify --x11    open it through XWayland (fallback)
DOS> play · pause · next · prev
```

## How it's installed

Module `40-spotify` installs `spotify-launcher` from Arch's official `extra`
repo. On first launch, it downloads Spotify's official `.deb` from
repository.spotify.com, checks its signature, and unpacks it to
`~/.local/share/spotify-launcher/install`. After that it checks for updates once
a day when Spotify starts. If a display was running during `dos-update`, the
module already did the download.

We didn't use the AUR `spotify` package: it repackages the same `.deb`, but it
has to be rebuilt for every release and needs Spotify's GPG key imported by
hand.

## Settings

- `~/.config/spotify-launcher.conf` is managed by DOS, and `dos-update`
  overwrites it. It runs Spotify as a native Wayland client
  (`--ozone-platform=wayland`), which uses less memory than XWayland.
- `storage.size=2048` in `~/.config/spotify/prefs` limits the cache to 2 GB.
  The cache saves the slow HDD from re-downloading songs you play often.
- If the window is blank or Spotify won't start, use `spotify --x11`.
- Run `spotify-launcher -v --skip-update --no-exec` in a terminal to see what
  it would pass to Spotify.

## Logging in

The first time Spotify opens, log in with your email and password (or the
one-time code Spotify can email you). If you use "Continue with Google/Apple/Facebook", Spotify
opens the default browser, so run `chrome` once first. You stay logged in after
that.

## Free tier

The free tier works on Linux the same as on Windows: you can play music, with
ads. You need Premium to download songs for
offline listening.

## Media commands

`play`, `pause`, `next` and `prev` use `playerctl` (MPRIS). They control
Spotify if it's running, and otherwise any other player that's open (Chrome,
mpv, ...). They work while Spotify is in the background.
