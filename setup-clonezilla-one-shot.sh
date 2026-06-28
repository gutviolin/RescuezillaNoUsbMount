#!/usr/bin/env bash
set -euo pipefail

ISO_SRC="/home/sionlockett/Downloads/clonezilla-live-3.3.2-31-amd64.iso"
MOUNT_POINT="/mnt/clonezilla-iso"
ESP="/boot/efi"
ENTRY_LABEL="Clonezilla Secure Boot"
EFI_DIR="$ESP/EFI/clonezilla"

if [[ $EUID -ne 0 ]]; then
  echo "Run this with sudo:"
  echo "  sudo $0"
  exit 1
fi

for cmd in efibootmgr findmnt lsblk mount rsync; do
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

echo "Staging Clonezilla files on the EFI System Partition"
mkdir -p "$EFI_DIR" "$ESP/live" "$ESP/boot/grub"
rsync -a --delete "$MOUNT_POINT/live/" "$ESP/live/"
rsync -a --delete "$MOUNT_POINT/boot/grub/" "$ESP/boot/grub/"
install -m 0644 "$MOUNT_POINT/EFI/boot/bootx64.efi" "$EFI_DIR/bootx64.efi"
install -m 0644 "$MOUNT_POINT/EFI/boot/grubx64.efi" "$EFI_DIR/grubx64.efi"

cat > "$EFI_DIR/grub.cfg" <<'EOF'
search --set=root --file /live/vmlinuz
set prefix=($root)/boot/grub
configfile ($root)/boot/grub/grub.cfg
EOF

ESP_SOURCE="$(findmnt -no SOURCE "$ESP")"
ESP_DISK="/dev/$(lsblk -no PKNAME "$ESP_SOURCE")"
ESP_PART="$(lsblk -no PARTN "$ESP_SOURCE")"

if [[ ! -b "$ESP_DISK" || -z "$ESP_PART" ]]; then
  echo "Could not determine EFI partition disk/number from $ESP_SOURCE" >&2
  exit 1
fi

echo "Creating UEFI boot entry on $ESP_DISK partition $ESP_PART"
efibootmgr -c -d "$ESP_DISK" -p "$ESP_PART" -L "$ENTRY_LABEL" -l '\EFI\clonezilla\bootx64.efi'

BOOTNUM="$(efibootmgr | awk -v label="$ENTRY_LABEL" '$0 ~ label {gsub(/^Boot|[* ].*/, "", $1); print $1}' | tail -n 1)"
if [[ -z "$BOOTNUM" ]]; then
  echo "Could not find the new UEFI boot entry for $ENTRY_LABEL" >&2
  exit 1
fi

echo "Setting one-time BootNext entry: $BOOTNUM"
efibootmgr -n "$BOOTNUM"

cat <<EOF

Ready.

Clonezilla has been staged on the EFI System Partition and selected for
the next boot only:
  Boot$BOOTNUM $ENTRY_LABEL

Reboot when ready:
  systemctl reboot

After you finish the backup and return to Fedora, optional cleanup is:
  sudo rm -rf '$ESP/live' '$ESP/boot/grub' '$EFI_DIR'
  sudo efibootmgr
  sudo efibootmgr -b $BOOTNUM -B
EOF
