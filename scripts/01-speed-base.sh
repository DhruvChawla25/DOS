#!/usr/bin/env bash
# DOS step 1 — speed base for the ideapad 110-15ISK (i3-6006U, HD 520, HDD).
#
# What it does (each part is safe to re-run):
#   1. zram: compressed swap in RAM (half of RAM, zstd). Fixes freezes when RAM fills.
#   2. Memory tuning suited to zram (swappiness etc.).
#   3. BFQ I/O scheduler on spinning disks, so the desktop stays responsive during disk load.
#   4. Intel GPU packages: Vulkan (games) and VA-API (hardware video decode for Chrome/Spotify).
#   5. thermald + power-profiles-daemon, set to "performance".
#
# It never touches /boot, the bootloader, partitions or Windows.
#
# Usage:  sudo bash 01-speed-base.sh            # apply
#         bash 01-speed-base.sh --dry-run       # show what would change
set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

PACKAGES=(zram-generator vulkan-intel intel-media-driver libva-utils thermald power-profiles-daemon)

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

run() {
  if (( DRY_RUN )); then printf '    [dry-run] %s\n' "$*"; else "$@"; fi
}

# write_file PATH CONTENT — writes only when the content differs.
write_file() {
  local path="$1" content="$2"
  if [[ -f "$path" ]] && [[ "$(cat "$path")" == "$content" ]]; then
    printf '    unchanged: %s\n' "$path"
    return
  fi
  if (( DRY_RUN )); then
    printf '    [dry-run] would write %s:\n' "$path"
    printf '%s\n' "$content" | sed 's/^/        /'
  else
    printf '%s\n' "$content" > "$path"
    printf '    wrote: %s\n' "$path"
  fi
}

if (( ! DRY_RUN )) && [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo bash $0   (or --dry-run to preview)" >&2
  exit 1
fi

log "1/5 Installing packages: ${PACKAGES[*]}"
run pacman -S --needed --noconfirm "${PACKAGES[@]}"

log "2/5 zram swap (half of RAM, zstd)"
write_file /etc/systemd/zram-generator.conf "[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100"
run systemctl daemon-reload
run systemctl start systemd-zram-setup@zram0.service

log "3/5 Memory tuning for zram"
write_file /etc/sysctl.d/99-dos.conf "# DOS: tuned for zram on an 8 GB laptop
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.vfs_cache_pressure = 50"
run sysctl --system --quiet

log "4/5 BFQ scheduler for spinning disks"
write_file /etc/udev/rules.d/60-dos-ioscheduler.rules \
'ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"'
run udevadm control --reload
run udevadm trigger --subsystem-match=block --action=change

log "5/5 Thermal and power"
run systemctl enable --now thermald.service power-profiles-daemon.service
run powerprofilesctl set performance

if (( ! DRY_RUN )); then
  log "Check:"
  swapon --show
  printf '    scheduler: %s\n' "$(cat /sys/block/sda/queue/scheduler)"
  printf '    power profile: %s\n' "$(powerprofilesctl get)"
  printf '    VA-API: '; vainfo 2>/dev/null | grep -m1 -o 'Driver version.*' || echo "not detected"
  log "Done. Reboot once so every setting is active from boot."
fi
