#!/usr/bin/env bash
# Safety test for dos-install, on loop-device disk images (no real disks).
#
# Builds a fake laptop disk:
#   p1 ESP (vfat) with grub/grub.cfg     p5 empty ext4 (the only valid target)
#   p2 Microsoft reserved                p6 ext4 holding a data file
#   p3 NTFS "Windows" (MS data type)     p7 NTFS on a Linux-typed partition
#   p4 ext4 "Arch" with /etc/os-release  then ~63 GB free at the end
#   (a 10 MiB gap between p4 and p5, so the first free block isn't the largest)
# and checks that dos-install refuses every partition it must refuse, that
# `--free --dry-run` picks the largest free block, and that a dry run writes
# nothing (destructive tools are replaced by stubs that record any call).
#
# Needs root, loop devices and: sgdisk, mkfs.vfat, mkntfs, mkfs.ext4, losetup.
# In CI: archlinux container with --privileged.
#   sudo bash tests/install-safety.sh
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$repo/iso/airootfs/usr/local/bin/dos-install"

[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
for t in sgdisk mkfs.vfat mkntfs mkfs.ext4 losetup blkid lsblk findmnt sfdisk; do
  command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
done

tmp=$(mktemp -d /var/tmp/dos-safety.XXXXXX)
loops=()
mnt="$tmp/mnt"; mkdir -p "$mnt"

cleanup() {
  set +e
  mountpoint -q "$mnt" && umount "$mnt"
  for l in "${loops[@]}"; do losetup -d "$l"; done
  rm -rf "$tmp"
}
trap cleanup EXIT

pass=0 failed=0
ok()  { printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; failed=$((failed + 1)); }

# Container /dev is a tmpfs, so new loop devices and their partitions get no
# device nodes. Make them from sysfs.
mknode() {  # mknode NAME
  local name=$1 majmin
  [[ -b /dev/$name ]] && return 0
  majmin=$(cat "/sys/class/block/$name/dev")
  mknod "/dev/$name" b "${majmin%%:*}" "${majmin##*:}"
}

attach() {  # attach IMAGE -> prints /dev/loopN, partition nodes ready
  local img=$1 dev name i p want
  want=$(sgdisk -p "$img" 2>/dev/null | grep -c '^ *[0-9]' || true)
  dev=$(losetup -f)
  [[ -b $dev ]] || mknod "$dev" b 7 "${dev#/dev/loop}"
  losetup -P "$dev" "$img"
  loops+=("$dev")
  name=${dev#/dev/}
  for (( i = 0; i < 20; i++ )); do
    (( $(compgen -G "/sys/class/block/$name/${name}p*" | wc -l) >= want )) && break
    sleep 0.25
  done
  for p in /sys/class/block/"$name"/"$name"p*; do
    [[ -e $p ]] && mknode "$(basename "$p")"
  done
  echo "$dev"
}

# ---------------------------------------------------------------- fake disks
echo "Building fake disks in $tmp"
main_img="$tmp/laptop.img"
truncate -s 64G "$main_img"
sgdisk -o \
  -n 1:2048:206847      -t 1:ef00 -c 1:EFI \
  -n 2:206848:239615    -t 2:0c01 -c 2:MSR \
  -n 3:239616:854015    -t 3:0700 -c 3:Windows \
  -n 4:854016:1468415   -t 4:8300 -c 4:Arch \
  -n 5:1488896:2103295  -t 5:8300 -c 5:Empty \
  -n 6:2103296:2308095  -t 6:8300 -c 6:Data \
  -n 7:2308096:2512895  -t 7:8300 -c 7:NtfsOnLinux \
  "$main_img" >/dev/null
EXPECT_FIRST=2512896            # first sector after p7 (1 MiB aligned)
EXPECT_LAST=$(sgdisk -E "$main_img" | tail -n1)

disk=$(attach "$main_img")
p() { echo "${disk}p$1"; }
echo "Main disk: $disk"

mkfs.vfat -F 32 -n EFI "$(p 1)" >/dev/null
mkntfs -Q -q -F -L Windows "$(p 3)"
mkfs.ext4 -q -F -L arch "$(p 4)"
mkfs.ext4 -q -F -L empty "$(p 5)"
mkfs.ext4 -q -F -L data "$(p 6)"
mkntfs -Q -q -F -L data2 "$(p 7)"

mount "$(p 1)" "$mnt"
mkdir -p "$mnt/grub/x86_64-efi"
cat > "$mnt/grub/grub.cfg" <<'EOF'
### BEGIN /etc/grub.d/41_custom ###
if [ -f  ${config_directory}/custom.cfg ]; then
  source ${config_directory}/custom.cfg
fi
### END /etc/grub.d/41_custom ###
EOF
: > "$mnt/grub/x86_64-efi/ext2.mod"
umount "$mnt"

mount "$(p 4)" "$mnt"
mkdir -p "$mnt/etc"
printf 'NAME="Arch Linux"\nPRETTY_NAME="Arch Linux"\nID=arch\n' > "$mnt/etc/os-release"
umount "$mnt"

mount "$(p 6)" "$mnt"
echo "important" > "$mnt/notes.txt"
umount "$mnt"

# An MBR disk, a small GPT disk, and a GPT disk whose 60 GB of free space is
# split into two blocks of ~30 GB (total is enough, the largest block isn't).
mbr_img="$tmp/mbr.img";   truncate -s 64G "$mbr_img"
printf 'label: dos\n' | sfdisk -q "$mbr_img"
small_img="$tmp/small.img"; truncate -s 2G "$small_img"
sgdisk -o "$small_img" >/dev/null
frag_img="$tmp/frag.img"; truncate -s 64G "$frag_img"
sgdisk -o -n 1:2048:206847 -t 1:ef00 -n 2:62914560:62916607 -t 2:8300 "$frag_img" >/dev/null
mbr=$(attach "$mbr_img"); small=$(attach "$small_img"); frag=$(attach "$frag_img")
mkfs.vfat -F 32 "${frag}p1" >/dev/null

# ---------------------------------------------------------------- stubs
stubs="$tmp/stubs"; stublog="$tmp/stub-calls.log"; : > "$stublog"
mkdir -p "$stubs"
for t in mkfs mkfs.ext4 mkfs.vfat mkntfs wipefs pacstrap genfstab arch-chroot partprobe \
         sfdisk parted cp chmod chroot runuser passwd useradd mv; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 97\n' "$t" "$stublog" > "$stubs/$t"
done
real_sgdisk=$(command -v sgdisk) real_mount=$(command -v mount)
# sgdisk: reading (-p -F -E -i) is allowed, anything else is recorded.
cat > "$stubs/sgdisk" <<EOF
#!/bin/sh
for a in "\$@"; do
  case \$a in -p|-F|-E|-i*|--print|/dev/*) ;; *) echo "sgdisk \$*" >> "$stublog"; exit 97 ;; esac
done
exec "$real_sgdisk" "\$@"
EOF
# mount: only read-only mounts are allowed.
cat > "$stubs/mount" <<EOF
#!/bin/sh
prev=""
for a in "\$@"; do
  if [ "\$prev" = "-o" ]; then case \$a in ro|ro,*) exec "$real_mount" "\$@" ;; esac; fi
  prev=\$a
done
echo "mount \$*" >> "$stublog"; exit 97
EOF
chmod +x "$stubs"/*

out="$tmp/out.log"
# di ARGS... — run dos-install with the stubs; sets $rc, output in $out.
di() {
  rc=0
  env PATH="$stubs:$PATH" DOS_INSTALL_ALLOW_LOOP="${ALLOW:-1}" DOS_INSTALL_MIN_GB="${MIN:-0}" \
    bash "$INSTALLER" "$@" </dev/null >"$out" 2>&1 || rc=$?
}

refuses() {  # refuses DESCRIPTION PATTERN ARGS...
  local desc=$1 pat=$2; shift 2
  di "$@"
  if (( rc != 0 )) && grep -qF -- "$pat" "$out"; then ok "$desc"
  else bad "$desc (rc=$rc, wanted '$pat')"; sed 's/^/       | /' "$out"; fi
}

has() {  # has DESCRIPTION PATTERN — check the last output
  if grep -qF -- "$2" "$out"; then ok "$1"; else bad "$1 (wanted '$2')"; sed 's/^/       | /' "$out"; fi
}

before=$(sgdisk -p "$disk")

# ---------------------------------------------------------------- tests
echo "Refusals"
refuses "refuses the EFI partition"          "is the EFI partition"        --dry-run "$(p 1)"
refuses "refuses Microsoft reserved"         "Microsoft reserved"          --dry-run "$(p 2)"
refuses "refuses the Windows NTFS partition" "Microsoft data partition"    --dry-run "$(p 3)"
refuses "refuses the existing Arch system"   "installed system (Arch Linux)" --dry-run "$(p 4)"
refuses "refuses a partition with files"     "is not empty"                --dry-run "$(p 6)"
refuses "refuses NTFS on a Linux-typed part" "holds a ntfs filesystem"     --dry-run "$(p 7)"
refuses "refuses a whole disk as partition"  "is not a partition"          --dry-run "$disk"
refuses "refuses a missing device"           "is not a block device"       --dry-run /dev/nonexistent
MIN=40 refuses "refuses a partition under 40 GB" "DOS needs 40 GB"         --dry-run "$(p 5)"
mount -o ro "$(p 5)" "$mnt"
refuses "refuses a mounted partition"        "is mounted"                  --dry-run "$(p 5)"
umount "$mnt"
refuses "refuses an MBR disk for --free"     "no GPT partition table"      --dry-run --free "$mbr"
MIN=40 refuses "refuses a disk without 40 GB free" "DOS needs 40 GB"       --dry-run --free "$small"
MIN=40 refuses "uses the largest block, not total free" "largest free block on $frag is 33 GB" --dry-run --free "$frag"
ALLOW=0 refuses "refuses loop devices outside tests" "is not a disk"       --dry-run --free "$disk"
refuses "--free needs a disk argument"       "usage: dos-install --free"   --dry-run --free

echo "Dry run on the empty partition"
di --dry-run "$(p 5)"
if (( rc == 0 )); then ok "dry run on an empty partition succeeds"; else bad "dry run on $(p 5) failed (rc=$rc)"; sed 's/^/       | /' "$out"; fi
has "prints the mkfs step"             "[dry-run] mkfs.ext4 -F -L DOS $(p 5)"
has "prints the pacstrap step"         "[dry-run] pacstrap -K /mnt/dos"
has "finds GRUB on the fake ESP"       "GRUB found on $(p 1)"
has "prints the GRUB entry"            'menuentry "DOS" --class dos'
has "asks for confirmation (dry)"      "would ask you to type '$(basename "$(p 5)")'"
has "warns when there's no room for games" "games like GTA 5 need 125+ GB"
has "prints the multilib step"         "[dry-run] sed -i -E"

echo "Dry run with --free"
MIN=40 di --dry-run --free "$disk"
if (( rc == 0 )); then ok "--free dry run succeeds"; else bad "--free dry run failed (rc=$rc)"; sed 's/^/       | /' "$out"; fi
has "picks the largest free block"     "[dry-run] sgdisk -n 8:$EXPECT_FIRST:$EXPECT_LAST -t 8:8304 -c 8:DOS $disk"
has "names the new partition"          "DOS would go on $(p 8)"
if grep -q -- "-n 8:1468416" "$out"; then bad "used the small gap after p4"; else ok "skips the small gap"; fi

echo "Nothing was written"
if [[ -s $stublog ]]; then bad "destructive tools were called:"; sed 's/^/       | /' "$stublog"; else ok "no destructive tool was called"; fi
if [[ $(sgdisk -p "$disk") == "$before" ]]; then ok "partition table unchanged"; else bad "partition table changed"; fi
mount -o ro "$(p 1)" "$mnt"
if [[ -e $mnt/grub/custom.cfg ]]; then bad "custom.cfg was written"; else ok "ESP unchanged (no custom.cfg)"; fi
umount "$mnt"
if [[ $(blkid -p -o value -s TYPE "$(p 5)") == ext4 && $(blkid -p -o value -s LABEL "$(p 5)") == empty ]]; then
  ok "target partition not formatted"; else bad "target partition changed"; fi
if [[ ! -e $(p 8) ]]; then ok "no partition 8 created"; else bad "partition 8 exists"; fi

echo
echo "install-safety: $pass passed, $failed failed"
(( failed == 0 ))
