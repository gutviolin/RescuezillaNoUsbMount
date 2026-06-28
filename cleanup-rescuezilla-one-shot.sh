#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this with sudo:"
  echo "  sudo $0"
  exit 1
fi

rm -rf '/boot/efi/EFI/rescuezilla'
if [[ -f '/boot/efi/EFI/ubuntu/grub.cfg.rescuezilla-backup' ]]; then
  mv '/boot/efi/EFI/ubuntu/grub.cfg.rescuezilla-backup' '/boot/efi/EFI/ubuntu/grub.cfg'
else
  rm -f '/boot/efi/EFI/ubuntu/grub.cfg'
fi
efibootmgr -b '0007' -B 2>/dev/null || true
