#!/usr/bin/env bash
# Fingerprint partitions 1-6 of a loop-attached laptop disk: table entries,
# UUIDs, the first 32 MiB of each, and the ESP's files except grub/custom.cfg.
set -euo pipefail
dev=$1
sgdisk -i 1 "$dev" >/dev/null
for n in 1 2 3 4 5 6; do
  p="${dev}p$n"
  echo "p$n table: $(sgdisk -i "$n" "$dev" | grep -E 'GUID code|unique GUID|First sector|Last sector' | tr -s ' ' | tr '\n' ' ')"
  echo "p$n blkid: $(blkid -o export "$p" | grep -E '^(UUID|TYPE|LABEL)=' | sort | tr '\n' ' ')"
  if [[ $n == 1 ]]; then
    m=$(mktemp -d); mount -o ro "$p" "$m"
    (cd "$m" && find . -type f ! -path ./grub/custom.cfg -print0 | sort -z | xargs -0 sha256sum) | sha256sum | sed 's/^/p1 files: /'
    umount "$m"; rmdir "$m"
  else
    echo "p$n head: $(head -c 33554432 "$p" | sha256sum | cut -d' ' -f1)"
  fi
done
