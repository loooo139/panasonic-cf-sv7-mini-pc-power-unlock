#!/usr/bin/env bash
# Remove the CF-SV7 EC power-limit unlock service and restore the EC limit.
#
#   sudo ./scripts/uninstall.sh
#
# This does NOT restore the BIOS Setup values. See uefi/revert.nsh.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root: sudo $0" >&2
  exit 1
fi

# Restore the firmware EC limit before removing the helper.
if [ -x /usr/local/sbin/dptf-ec-unlock.sh ]; then
  /usr/local/sbin/dptf-ec-unlock.sh restore || true
fi

systemctl disable --now dptf-ec-unlock.timer 2>/dev/null || true

rm -f /etc/systemd/system/dptf-ec-unlock.service \
      /etc/systemd/system/dptf-ec-unlock.timer \
      /usr/local/sbin/dptf-ec-unlock.sh \
      /usr/lib/systemd/system-sleep/dptf-ec-unlock \
      /etc/modules-load.d/acpi_call.conf

systemctl daemon-reload

echo "Removed the unlock service and restored the EC limit."
echo "The acpi-call-dkms package was left installed; remove it manually if desired."
echo "To restore BIOS Setup values, boot the UEFI Shell and run uefi/revert.nsh."
