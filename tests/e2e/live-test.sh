#!/usr/bin/env bash
# Runs INSIDE the DOS live ISO in the test VM (archiso's script= boot option).
# Installs DOS for real onto the fake laptop disk, then leaves a boot check in
# the new system. Everything goes to the serial port, which the host reads.
exec > >(tee -a /dev/ttyS0) 2>&1
srv=http://10.0.2.2:8000
say() { echo "DOS-E2E: $*"; }
end() { say "live done"; sync; sleep 2; systemctl poweroff; exit 0; }

say "live system up, kernel $(uname -r)"
[[ -d /sys/firmware/efi ]] && say "check live-uefi ok" || say "check live-uefi FAIL"
command -v dos-install >/dev/null && [[ -x $(command -v dos-install) ]] \
  && say "check dos-install-executable ok" || { say "check dos-install-executable FAIL"; end; }
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME

# Must refuse what it must refuse, on the real-shaped disk.
for t in /dev/vda1 /dev/vda2 /dev/vda3 /dev/vda4 /dev/vda5 /dev/vda6 /dev/sr0; do
  if dos-install --dry-run "$t" >/dev/null 2>&1; then say "check refuses-$t FAIL"; else say "check refuses-$t ok"; fi
done

export DOS_INSTALL_TEST_ANSWER=vda DOS_INSTALL_TEST_PASSWORD=dos-e2e
if dos-install --free /dev/vda --dry-run; then say "check dry-run ok"; else say "check dry-run FAIL"; end; fi

start=$SECONDS
if dos-install --free /dev/vda; then
  say "check install ok ($(( SECONDS - start ))s)"
else
  say "check install FAIL (exit $?)"; end
fi

# The 324 GB block is used up now: a second --free must refuse.
if dos-install --free /dev/vda --dry-run >/dev/null 2>&1; then say "check second-free-refused FAIL"; else say "check second-free-refused ok"; fi
# And the new DOS partition now holds a system: must refuse to erase it.
if dos-install --dry-run /dev/vda7 >/dev/null 2>&1; then say "check refuses-installed-dos FAIL"; else say "check refuses-installed-dos ok"; fi

mkdir -p /mnt/dos && mount /dev/vda7 /mnt/dos
curl -fsS "$srv/dos-e2e-check" -o /mnt/dos/usr/local/sbin/dos-e2e-check
chmod 755 /mnt/dos/usr/local/sbin/dos-e2e-check
cat > /mnt/dos/etc/systemd/system/dos-e2e.service <<'UNIT'
[Unit]
Description=DOS end-to-end boot check (test only)
[Service]
Type=simple
ExecStart=/usr/local/sbin/dos-e2e-check
StandardOutput=tty
StandardError=tty
TTYPath=/dev/ttyS0
[Install]
WantedBy=multi-user.target
UNIT
ln -sf /etc/systemd/system/dos-e2e.service /mnt/dos/etc/systemd/system/multi-user.target.wants/dos-e2e.service
echo "--- custom.cfg"; mount -o ro /dev/vda1 /mnt/dos-esp 2>/dev/null || { mkdir -p /mnt/dos-esp; mount -o ro /dev/vda1 /mnt/dos-esp; }
cat /mnt/dos-esp/grub/custom.cfg; umount /mnt/dos-esp
echo "--- fstab"; cat /mnt/dos/etc/fstab
umount /mnt/dos
end
