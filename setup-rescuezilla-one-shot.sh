#!/usr/bin/env bash
set -euo pipefail

ISO_SRC="/home/sionlockett/Downloads/rescuezilla-2.6.2-64bit.resolute.iso"
ISO_NAME="$(basename "$ISO_SRC")"
ISO_SCAN_PATH="/home/sionlockett/Downloads/$ISO_NAME"
MOUNT_POINT="/mnt/rescuezilla-iso"
ESP="/boot/efi"
ENTRY_LABEL="Rescuezilla Secure Boot"
EFI_DIR="$ESP/EFI/rescuezilla"
UBUNTU_EFI_DIR="$ESP/EFI/ubuntu"
UBUNTU_GRUB_CFG="$UBUNTU_EFI_DIR/grub.cfg"
UBUNTU_GRUB_BACKUP="$UBUNTU_EFI_DIR/grub.cfg.rescuezilla-backup"
CLEANUP_SCRIPT="/home/sionlockett/Downloads/cleanup-rescuezilla-one-shot.sh"

if [[ $EUID -ne 0 ]]; then
  echo "Run this with sudo:"
  echo "  sudo $0"
  exit 1
fi

SETUP_COMPLETE=0
rollback_on_error() {
  if [[ "$SETUP_COMPLETE" -eq 1 ]]; then
    return
  fi

  echo "Setup did not complete; rolling back temporary Rescuezilla files." >&2
  rm -rf "$EFI_DIR" 2>/dev/null || true
  if [[ -f "$UBUNTU_GRUB_BACKUP" ]]; then
    mv "$UBUNTU_GRUB_BACKUP" "$UBUNTU_GRUB_CFG" 2>/dev/null || true
  fi
}
trap rollback_on_error EXIT

for cmd in efibootmgr findmnt lsblk mount install; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

if [[ ! -f "$ISO_SRC" ]]; then
  echo "ISO not found: $ISO_SRC" >&2
  exit 1
fi

if [[ ! -d /sys/firmware/efi ]]; then
  echo "This system is not currently booted in UEFI mode." >&2
  exit 1
fi

echo "Secure Boot state:"
mokutil --sb-state 2>/dev/null || true

echo "Creating mount point: $MOUNT_POINT"
mkdir -p "$MOUNT_POINT"

if ! findmnt -rn "$MOUNT_POINT" >/dev/null 2>&1; then
  echo "Mounting ISO read-only at $MOUNT_POINT"
  mount -o loop,ro "$ISO_SRC" "$MOUNT_POINT"
else
  echo "$MOUNT_POINT is already mounted"
fi

echo "Staging Rescuezilla signed EFI boot files and kernel/initrd"
mkdir -p "$EFI_DIR/casper" "$UBUNTU_EFI_DIR"
install -m 0644 "$MOUNT_POINT/EFI/BOOT/BOOTx64.EFI" "$EFI_DIR/BOOTx64.EFI"
install -m 0644 "$MOUNT_POINT/EFI/BOOT/grubx64.efi" "$EFI_DIR/grubx64.efi"
install -m 0644 "$MOUNT_POINT/casper/vmlinuz" "$EFI_DIR/casper/vmlinuz"
install -m 0644 "$MOUNT_POINT/casper/initrd.lz" "$EFI_DIR/casper/initrd.lz"

if [[ -e "$UBUNTU_GRUB_BACKUP" ]]; then
  echo "Refusing to continue because a previous backup exists:" >&2
  echo "  $UBUNTU_GRUB_BACKUP" >&2
  echo "Restore or remove that file first." >&2
  exit 1
fi

if [[ -e "$UBUNTU_GRUB_CFG" ]]; then
  echo "Backing up existing $UBUNTU_GRUB_CFG"
  cp -a "$UBUNTU_GRUB_CFG" "$UBUNTU_GRUB_BACKUP"
fi

cat > "$UBUNTU_GRUB_CFG" <<EOF
set timeout=5
set default=0

menuentry "Start Rescuezilla from ISO" {
    search --no-floppy --set=root --file /EFI/rescuezilla/casper/vmlinuz
    if [ ! -e /EFI/rescuezilla/casper/vmlinuz ]; then
        echo "Could not find Rescuezilla kernel on the EFI partition"
        sleep 10
        reboot
    fi

    linux /EFI/rescuezilla/casper/vmlinuz boot=casper quiet splash fastboot fsck.mode=skip noprompt edd=on iso-scan/filename=$ISO_SCAN_PATH locale=en_US console-setup/layoutcode=us bootkbd=us --
    initrd /EFI/rescuezilla/casper/initrd.lz
}
EOF

ESP_SOURCE="$(findmnt -no SOURCE "$ESP")"
ESP_DISK="/dev/$(lsblk -no PKNAME "$ESP_SOURCE")"
ESP_PART="$(lsblk -no PARTN "$ESP_SOURCE")"

if [[ ! -b "$ESP_DISK" || -z "$ESP_PART" ]]; then
  echo "Could not determine EFI partition disk/number from $ESP_SOURCE" >&2
  exit 1
fi

echo "Creating UEFI boot entry on $ESP_DISK partition $ESP_PART"
efibootmgr -c -d "$ESP_DISK" -p "$ESP_PART" -L "$ENTRY_LABEL" -l '\EFI\rescuezilla\BOOTx64.EFI'

BOOTNUM="$(efibootmgr | awk -v label="$ENTRY_LABEL" '$0 ~ label {gsub(/^Boot|[* ].*/, "", $1); print $1}' | tail -n 1)"
if [[ -z "$BOOTNUM" ]]; then
  echo "Could not find the new UEFI boot entry for $ENTRY_LABEL" >&2
  exit 1
fi

echo "Setting one-time BootNext entry: $BOOTNUM"
efibootmgr -n "$BOOTNUM"

cat > "$CLEANUP_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ \$EUID -ne 0 ]]; then
  echo "Run this with sudo:"
  echo "  sudo \$0"
  exit 1
fi

rm -rf '$EFI_DIR'
if [[ -f '$UBUNTU_GRUB_BACKUP' ]]; then
  mv '$UBUNTU_GRUB_BACKUP' '$UBUNTU_GRUB_CFG'
else
  rm -f '$UBUNTU_GRUB_CFG'
fi
efibootmgr -b '$BOOTNUM' -B 2>/dev/null || true
EOF
chmod 0755 "$CLEANUP_SCRIPT"
SETUP_COMPLETE=1

cat <<EOF

Ready.

Rescuezilla has been staged for Secure Boot and selected for the next
boot only:
  Boot$BOOTNUM $ENTRY_LABEL

Reboot when ready:
  systemctl reboot

After you finish the backup and return to Fedora, optional cleanup is:
  sudo '$CLEANUP_SCRIPT'
EOF
