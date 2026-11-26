#!/usr/bin/env bash
# End-to-end test of DOS in virtual machines (Linux host with QEMU + OVMF; CI
# runs it on ubuntu-latest). Never touches a real disk.
#   1. build a disk image shaped exactly like the laptop's (make-laptop-disk.sh)
#   2. boot the DOS ISO with that disk, UEFI, and run dos-install --free for real
#   3. prove partitions 1-6 are byte-for-byte unchanged and DOS is p7 in the free space
#   4. boot the disk alone through its own GRUB -> DOS entry -> installed DOS checks
#   sudo bash tests/e2e/run.sh out/DOS-*.iso
set -euo pipefail
iso=$(realpath "$1")
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work=${E2E_WORK:-/var/tmp/dos-e2e}
rm -rf "$work"; mkdir -p "$work"
cd "$work"

# First existing file of each (Ubuntu, older Ubuntu, Arch). Not ls | head:
# ls exits 2 for the missing ones, which pipefail turns into a failure.
first() { local f; for f in "$@"; do [[ -f $f ]] && { echo "$f"; return; }; done; }
code=$(first /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd)
vars=$(first /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd)
[[ -n $code && -n $vars ]] || { echo "OVMF not found" >&2; exit 1; }
accel=tcg cpu=max
[[ -w /dev/kvm ]] && accel=kvm cpu=host
echo "QEMU accel: $accel"

qemu() {  # qemu LOG TIMEOUT_MIN extra args...
  local log=$1 mins=$2; shift 2
  cp "$vars" "$work/vars.fd"
  timeout "$(( mins * 60 ))" qemu-system-x86_64 -machine q35,accel=$accel -cpu $cpu -m 4096 -smp 2 \
    -drive if=pflash,format=raw,readonly=on,file="$code" \
    -drive if=pflash,format=raw,file="$work/vars.fd" \
    -drive file="$work/laptop.img",format=raw,if=virtio,cache=unsafe \
    -nic user,model=virtio-net-pci -display none -no-reboot \
    -serial file:"$log" "$@" || echo "qemu exited with $? (124 = timed out)"
}

echo "== 1. fake laptop disk"
bash "$here/make-laptop-disk.sh" laptop.img before.txt

echo "== 2. live ISO: dos-install --free /dev/vda"
label=$(blkid -o value -s LABEL "$iso")
mkdir -p isofiles
bsdtar -xf "$iso" -C isofiles arch/boot/x86_64/vmlinuz-linux arch/boot/x86_64/initramfs-linux.img
mkdir -p www && cp "$here/live-test.sh" "$here/dos-e2e-check" www/
(cd www && exec python3 -m http.server 8000 --bind 127.0.0.1) >/dev/null 2>&1 &
http=$!
trap 'kill $http 2>/dev/null || true' EXIT
qemu live.log 75 -cdrom "$iso" \
  -kernel isofiles/arch/boot/x86_64/vmlinuz-linux -initrd isofiles/arch/boot/x86_64/initramfs-linux.img \
  -append "archisobasedir=arch archisolabel=$label script=http://10.0.2.2:8000/live-test.sh console=ttyS0,115200"
grep -a 'DOS-E2E' live.log || true

echo "== 3. existing partitions untouched, DOS in the free space"
dev=$(losetup -fP --show laptop.img); udevadm settle || true
bash "$here/fingerprint.sh" "$dev" > after.txt
sgdisk -p "$dev"
p7=$(sgdisk -i 7 "$dev" || true)
losetup -d "$dev"
fail=0
if diff -u before.txt after.txt; then echo "DOS-E2E: check partitions-1-6-unchanged ok"
else echo "DOS-E2E: check partitions-1-6-unchanged FAIL"; fail=1; fi
grep -q 'First sector: 1320511488 ' <<<"$p7" && grep -qi '4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709' <<<"$p7" \
  && echo "DOS-E2E: check p7-in-free-space ok" || { echo "DOS-E2E: check p7-in-free-space FAIL"; echo "$p7"; fail=1; }

echo "== 4. boot the disk alone: OVMF -> GRUB on the ESP -> DOS"
qemu boot.log 20
grep -a -E 'DOS-E2E|GNU GRUB|DOS' boot.log | head -n 80 || true

{ grep -a -h 'DOS-E2E' live.log boot.log; } > results.txt || true
echo "== results"
cat results.txt
grep -q 'DOS-E2E: check install ok' results.txt || { echo "install did not finish"; fail=1; }
grep -q 'DOS-E2E: boot done' results.txt || { echo "installed DOS did not finish booting"; fail=1; }
if grep -E 'check .* FAIL' results.txt; then fail=1; fi
# thermald needs real Intel thermal hardware; it may fail in a VM.
if grep 'failed-unit' results.txt | grep -v -E 'thermald' ; then fail=1; fi
(( fail == 0 )) && echo "E2E PASSED" || { echo "E2E FAILED"; exit 1; }
