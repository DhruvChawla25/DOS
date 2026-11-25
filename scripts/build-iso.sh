#!/usr/bin/env bash
# Build the DOS live/installer ISO.
#
# Starts from Arch's official "releng" archiso profile and layers DOS on top:
#   iso/packages.extra   extra packages for the live system
#   iso/airootfs/        files copied over the live root filesystem
#
# Needs Arch Linux (or an archlinux container) with the archiso package, run as root.
#   sudo DOS_VERSION=0.1.0 bash scripts/build-iso.sh
# The ISO lands in out/ (override with OUT_DIR).
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${DOS_VERSION:-dev}"
work="${WORK_DIR:-/tmp/dos-build}"
out="${OUT_DIR:-$repo/out}"
releng=/usr/share/archiso/configs/releng

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (mkarchiso needs it)." >&2
  exit 1
fi
if [[ ! -d $releng ]]; then
  echo "archiso is not installed: pacman -S archiso" >&2
  exit 1
fi

rm -rf "$work"
mkdir -p "$work" "$out"
profile="$work/profile"
cp -r "$releng" "$profile"

# Packages: releng's list plus ours, without comments or duplicates.
cat "$profile/packages.x86_64" "$repo/iso/packages.extra" \
  | sed 's/#.*//; s/[[:space:]]//g; /^$/d' | sort -u > "$work/packages"
mv "$work/packages" "$profile/packages.x86_64"

# Files: our overlay wins over releng's.
cp -r "$repo/iso/airootfs/." "$profile/airootfs/"

# Identity. The label must be uppercase, at most 32 characters.
label="DOS_$(date +%Y%m)"
sed -i \
  -e "s|^iso_name=.*|iso_name=\"DOS\"|" \
  -e "s|^iso_label=.*|iso_label=\"${label}\"|" \
  -e "s|^iso_publisher=.*|iso_publisher=\"Dhruv Chawla\"|" \
  -e "s|^iso_application=.*|iso_application=\"DOS - Dhruv's Operating System\"|" \
  -e "s|^iso_version=.*|iso_version=\"${version}\"|" \
  "$profile/profiledef.sh"

# Our own scripts in the live system must be executable. mkarchiso copies
# airootfs with --no-preserve=mode (everything becomes 644), then applies
# file_permissions; a key without a trailing "/" sets just that file.
for f in "$repo"/iso/airootfs/usr/local/bin/*; do
  printf 'file_permissions+=(["/usr/local/bin/%s"]="0:0:755")\n' "$(basename "$f")"
done >> "$profile/profiledef.sh"

# DOS_ISO_FAST=1 (CI builds that aren't releases): zstd squashfs instead of
# releng's xz. Much faster to build, a little bigger, and faster to boot.
if [[ ${DOS_ISO_FAST:-0} == 1 ]]; then
  sed -i "s|^airootfs_image_tool_options=.*|airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '6' '-b' '1M')|" \
    "$profile/profiledef.sh"
fi

# Boot menu text: "Arch Linux install medium" -> "DOS live".
grep -rlZ "Arch Linux install medium" "$profile/grub" "$profile/syslinux" "$profile/efiboot" 2>/dev/null \
  | xargs -0 -r sed -i "s/Arch Linux install medium/DOS live/g"

mkarchiso -v -w "$work/work" -o "$out" "$profile"

# Check the live root that went into the ISO (mkarchiso keeps it without -r).
live_root="$work/work/x86_64/airootfs"
for f in "$repo"/iso/airootfs/usr/local/bin/*; do
  t="$live_root/usr/local/bin/$(basename "$f")"
  [[ -x $t ]] || { echo "build-iso: $t is not executable in the ISO" >&2; exit 1; }
done
[[ -f $live_root/usr/share/dos/rootfs/etc/sudoers.d/10-wheel ]] \
  || { echo "build-iso: DOS rootfs files missing from the ISO" >&2; exit 1; }
echo "build-iso: dos-install is executable and the DOS rootfs is in the ISO."
ls -lh "$out"
