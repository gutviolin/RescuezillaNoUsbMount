# Rescuezilla Secure Boot Tools

Small helper scripts for one-time UEFI boots of Rescuezilla while Secure Boot remains enabled.

These scripts were written for a Fedora UEFI system where the ISO file lives at:

- `/home/sionlockett/Downloads/rescuezilla-2.6.2-64bit.resolute.iso`

The ISO file is intentionally not committed. GitHub rejects normal Git files over 100 MB, and this image is much larger.

## Scripts

- `setup-rescuezilla-one-shot.sh`: stages Rescuezilla signed EFI boot files plus kernel/initrd on the EFI System Partition, creates a one-time UEFI `BootNext` entry, and writes a cleanup script.
- `cleanup-rescuezilla-one-shot.sh`: removes the staged Rescuezilla EFI files, restores the temporary Ubuntu GRUB config if needed, and removes the generated UEFI boot entry.

## Rescuezilla Usage

```bash
sudo ./setup-rescuezilla-one-shot.sh
systemctl reboot
```

After returning to Fedora:

```bash
sudo ./cleanup-rescuezilla-one-shot.sh
```

## Notes

- These scripts require root because they mount ISOs, write to `/boot/efi`, and use `efibootmgr`.
- They require UEFI boot mode.
- Secure Boot stays enabled; the scripts rely on the signed shim/GRUB/kernel included in the Rescuezilla ISO.
- Review the hardcoded ISO paths before using on another machine.
