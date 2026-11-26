#!/usr/bin/env bash
# Build a raw disk image shaped like the real laptop's 1 TB Toshiba disk, with
# the same partitions at the same byte offsets (from Windows' Get-Partition):
#   p1 EFI (vfat, real GRUB, ~16 MB free)  p4 Windows recovery (NTFS)
#   p2 Microsoft reserved                  p6 Arch (ext4, with os-release)
#   p3 C: Windows (NTFS)                   p5 E: "New Volume" (NTFS)
# and ~324 GB unallocated at the end, where DOS goes. The image is sparse.
# Records fingerprints of every existing partition in $2 so the test can
# prove dos-install didn't touch them.
#   sudo bash tests/e2e/make-laptop-disk.sh laptop.img before.txt
set -euo pipefail
img=$1 fp=$2
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

truncate -s 1000204886016 "$img"
# sector = byte offset / 512; end = start + size - 1
sgdisk -o \
  -n 1:2048:206847          -t 1:ef00 -c 1:"EFI system partition" \
  -n 2:206848:239615        -t 2:0c01 -c 2:"Microsoft reserved partition" \
  -n 3:239616:306156177     -t 3:0700 -c 3:"Basic data partition" \
  -n 4:306157568:307199999  -t 4:2700 -c 4:"Basic data partition" \
  -n 6:307200000:1130430463 -t 6:8300 -c 6:"" \
  -n 5:1130430464:1320511487 -t 5:0700 -c 5:"Basic data partition" \
  "$img" >/dev/null

dev=$(losetup -fP --show "$img")
trap 'umount -q /tmp/dos-e2e-mnt 2>/dev/null || true; losetup -d "$dev"' EXIT
udevadm settle || true
mkfs.vfat -F 32 -n SYSTEM "${dev}p1" >/dev/null
mkntfs -Q -q -F -L Windows "${dev}p3"
mkntfs -Q -q -F -L Recovery "${dev}p4"
mkntfs -Q -q -F -L "New Volume" "${dev}p5"
mkfs.ext4 -q -F -E lazy_itable_init=1,lazy_journal_init=1 "${dev}p6"

m=/tmp/dos-e2e-mnt; mkdir -p "$m"
# ESP: real GRUB like Arch's (grub.cfg at ESP:/grub, loads custom.cfg), a
# Windows boot manager stand-in, and filler so only ~16 MB is free.
mount "${dev}p1" "$m"
grub-install --target=x86_64-efi --efi-directory="$m" --boot-directory="$m" \
  --removable --no-nvram --no-uefi-secure-boot >/dev/null 2>&1 \
  || grub-install --target=x86_64-efi --efi-directory="$m" --boot-directory="$m" --removable --no-nvram
mkdir -p "$m/EFI/Microsoft/Boot"
echo "fake bootmgfw" > "$m/EFI/Microsoft/Boot/bootmgfw.efi"
cp "$here/grub.cfg" "$m/grub/grub.cfg"
free_mb=$(( $(stat -f -c '%a*%S' "$m") / 1024 / 1024 ))
(( free_mb > 16 )) && fallocate -l $(( (free_mb - 16) * 1024 * 1024 )) "$m/EFI/Microsoft/Boot/filler.bin"
df -h "$m" | tail -n1
umount "$m"

mount "${dev}p6" "$m"
mkdir -p "$m/etc" "$m/home/dhruv"
printf 'NAME="Arch Linux"\nPRETTY_NAME="Arch Linux"\nID=arch\n' > "$m/etc/os-release"
echo "arch data" > "$m/home/dhruv/notes.txt"
umount "$m"
for n in 3 5; do
  mount -t ntfs-3g "${dev}p$n" "$m" 2>/dev/null || mount "${dev}p$n" "$m"
  echo "windows data $n" > "$m/data.txt"
  umount "$m"
done

bash "$here/fingerprint.sh" "$dev" > "$fp"
cat "$fp"
