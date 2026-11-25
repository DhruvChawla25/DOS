#!/usr/bin/env bash
# DOS — read-only hardware check for the target laptop.
# Prints the facts the setup plan depends on and saves them to ~/dos-info.txt.
# Nothing on the system is changed. Run with: bash collect-info.sh
set -uo pipefail

out="${HOME}/dos-info.txt"

section() { printf '\n== %s ==\n' "$1"; }

need_sudo() {
  if sudo -n true 2>/dev/null; then return 0; fi
  echo "Some checks need sudo (board model, RAM slots). You may be asked for your password."
  sudo -v
}

{
  section "MODEL"
  cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name /sys/class/dmi/id/product_version 2>/dev/null
  cat /sys/class/dmi/id/bios_version /sys/class/dmi/id/bios_date 2>/dev/null

  section "DISK TYPE (1 = spinning HDD, 0 = SSD)"
  for d in /sys/block/sd* /sys/block/nvme*; do
    [ -e "$d" ] || continue
    printf '%s rotational=%s model=%s\n' "$(basename "$d")" \
      "$(cat "$d/queue/rotational")" "$(cat "$d/device/model" 2>/dev/null | xargs)"
  done

  section "PARTITIONS"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS

  section "RAM SLOTS"
  need_sudo
  sudo dmidecode -t memory | grep -E "Maximum Capacity|Number Of Devices|^\s+Size:|Type: DDR|Speed:|Locator:" | grep -v "Bank"

  section "SWAP / ZRAM"
  swapon --show; zramctl 2>/dev/null || true

  section "GPU DRIVER"
  lspci -k | grep -A3 -iE "vga|display"
  pacman -Q mesa vulkan-intel intel-media-driver libva-intel-driver 2>/dev/null || true

  section "DISPLAY OUTPUTS (connected = monitor plugged in)"
  for c in /sys/class/drm/card*-*; do
    [ -e "$c/status" ] || continue
    printf '%s: %s\n' "$(basename "$c")" "$(cat "$c/status")"
  done

  section "SESSION"
  echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-none}  DESKTOP=${XDG_CURRENT_DESKTOP:-none}"
  systemctl get-default
  ls /usr/share/xsessions /usr/share/wayland-sessions 2>/dev/null

  section "BOOT"
  bootctl status 2>/dev/null | grep -E "Product|Boot Loader|ESP" || true
  ls /boot
  df -h /boot

  section "THERMALS / POWER"
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
  cat /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference 2>/dev/null
  systemctl is-active thermald power-profiles-daemon tlp 2>/dev/null

  section "BIGGEST RAM USERS RIGHT NOW"
  ps -eo rss,comm --sort=-rss | head -12 | awk 'NR==1{print;next}{printf "%7.0f MB  %s\n",$1/1024,$2}'

  section "INSTALLED APPS"
  pacman -Qq | grep -E "^(google-chrome|chromium|spotify|spotify-launcher|minecraft-launcher|prismlauncher|heroic-games-launcher.*|steam|sway|xfce4-session)$" || echo "(none of the target apps found)"
} 2>&1 | tee "$out"

printf '\nSaved to %s — paste it back into the chat.\n' "$out"
