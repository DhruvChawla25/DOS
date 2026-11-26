# Minecraft on DOS (TLauncher)

```
DOS> tlauncher        (or: minecraft)
```

TLauncher opens full screen. When you start a version, Minecraft opens in its
own window, and closing it brings you back to TLauncher.

## About TLauncher

TLauncher is an **unofficial** launcher. It has been flagged for bundled adware
in the past, and it isn't made by Mojang or Microsoft. DOS installs it because
you chose it. It keeps the risk down where it can:

- DOS downloads only the official build from `https://tlauncher.org/jar`, over
  HTTPS. If a redirect leaves `tlauncher.org`, or the zip doesn't hold a
  runnable `TLauncher.jar`, nothing is installed.
- It doesn't use the AUR package `tlauncher-installer`. That package
  repackages the same upstream `.deb`, has 5 votes, declares no Java
  dependency and adds a third party without adding any review.
- TLauncher runs as your user and never as root. Its upstream README suggests
  `sudo java -jar`, which you shouldn't do.
- After the first start, TLauncher downloads its own core files from its own
  servers and updates itself. DOS can't check those files.
- **If TLauncher shows an "offer" or asks to install extra software, decline
  it.** Minecraft doesn't need anything else.
- **Mods:** get them from Modrinth (modrinth.com) or CurseForge, not from
  random mirror sites.

Files: `~/.local/share/dos/tlauncher/` holds `TLauncher.jar`, `jvm-args.txt`
and `tlauncher.log`. Game data is in `~/.minecraft`, and TLauncher's own files
are in `~/.tlauncher`. To get a fresh TLauncher, run
`DOS_TLAUNCHER_REFRESH=1 bash /opt/dos/modules/50-tlauncher/install.sh`.

## Java

DOS installs four runtimes side by side, all official Arch packages:

| Minecraft version | Java | Path to give TLauncher |
|-------------------|------|------------------------|
| 26.1 and newer | 25 | `/usr/lib/jvm/java-25-openjdk/bin/java` |
| 1.20.5 – 1.21.x | 21 | `/usr/lib/jvm/java-21-openjdk/bin/java` |
| 1.17 – 1.20.4 (most Forge modpacks) | 17 | `/usr/lib/jvm/java-17-openjdk/bin/java` |
| 1.16.5 and older | 8 | `/usr/lib/jvm/java-8-openjdk/jre/bin/java` |

TLauncher itself always runs on Java 21. If a version crashes at start with
`UnsupportedClassVersionError` or "requires Java N", set TLauncher's Java path
(in its settings, the gear icon) to the matching row above.

## Settings for smooth fps on this laptop

The i3-6006U has 2 cores and runs at 2.0 GHz with no boost, and the Intel HD
520 shares RAM with the CPU. The CPU, not the GPU, sets the limit, so most of
these settings reduce CPU work.

### TLauncher settings

- **Memory:** 2048 MB for vanilla, 3072 MB for modpacks. Don't go higher. The
  laptop has 7.5 GB, and a bigger heap only makes garbage collection pauses
  longer. Close Chrome while you play.
- **JVM arguments:** paste the line from `~/.local/share/dos/tlauncher/jvm-args.txt`.
  It's G1GC tuned for short pauses (a smaller version of Aikar's flags) and
  works on Java 8 through 25. Don't add `-Xmx` there, because the memory
  slider sets it. Leave `-XX:+AlwaysPreTouch` out, since it would fill zram
  for nothing.

### In-game video settings

| Setting | Value |
|---------|-------|
| Graphics | Fast |
| Render distance | 6–8 chunks (8 vanilla, up to 10 with Sodium) |
| Simulation distance | 5–6 |
| Max framerate | 60 (VSync off) |
| Smooth lighting | Off or Minimum |
| Clouds | Off |
| Particles | Minimal |
| Entity shadows | Off |
| Entity distance | 75% |
| Biome blend | Off |
| Mipmap levels | 0–2 |
| Fullscreen | On |
| Shaders | None. The HD 520 can't run them at playable fps. |

### Sodium or OptiFine

Pick one. They don't work together.

- **Sodium (1.20+ and 26.x, recommended):** a rendering rewrite that
  often doubles fps on Intel graphics. In TLauncher, pick the **Fabric**
  build of your version, start it once, then put these mods from
  modrinth.com into `~/.minecraft/mods`:
  - Sodium (rendering)
  - Lithium (game logic, lighter on the 2-core CPU)
  - FerriteCore (less RAM)
  - ImmediatelyFast and Entity Culling (fewer draw calls)
  - Sodium Extra, optional (more video settings)

  The mod versions must match the Minecraft version exactly.
- **OptiFine (older versions, or Forge):** TLauncher lists OptiFine builds
  next to the normal versions (for example "OptiFine 1.16.5"). Pick one. In
  Video Settings → Performance, also turn on Smart Animations, plus Fast
  Render and Render Regions where your OptiFine build has them, and set Chunk
  Updates to 1. Turn Dynamic Lights off.

### The HDD

The first world load and new chunks are slow on a 5400 rpm drive, so it can
stutter for the first minute. Lower render distance helps the most here, and
FerriteCore helps on modpacks. Big modpacks (200+ mods) take several minutes
to start. That's normal on this disk.

## Microsoft account

If you buy Minecraft Java Edition later, it works with your Microsoft
account. TLauncher has a Microsoft login option. For a paid account, it's
safer to sign in through an official or open-source launcher instead of an
unofficial one:

- **Prism Launcher** (open source, in the Arch repos): `install prismlauncher`.
  It signs in with Microsoft, runs Fabric/Forge/modpacks, and can use the same
  Java paths listed above.
- The official Minecraft Launcher, as `minecraft-launcher` on the AUR.

The settings on this page work the same in all of them. Servers that check
licenses, such as Hypixel, need the paid account.
