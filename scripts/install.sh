#!/usr/bin/env bash
# Install the CF-SV7 EC power-limit unlock as a systemd service + timer.
#
#   sudo ./scripts/install.sh
#
# This does NOT modify the BIOS. Run the UEFI Shell step first if you have not
# already unlocked the MSR (see uefi/README.md).
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root: sudo $0" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# acpi_call is required; /proc/acpi/call is created by the module.
if [ ! -e /proc/acpi/call ]; then
  if ! modprobe acpi_call 2>/dev/null; then
    echo "acpi_call is not installed. Install it with:" >&2
    echo "  sudo apt-get update && sudo apt-get install -y acpi-call-dkms" >&2
    exit 1
  fi
fi

install -d /usr/lib/systemd/system-sleep
install -m 755 "$ROOT/scripts/dptf-ec-unlock.sh" /usr/local/sbin/dptf-ec-unlock.sh
install -m 644 "$ROOT/scripts/dptf-ec-unlock.service" /etc/systemd/system/dptf-ec-unlock.service
install -m 644 "$ROOT/scripts/dptf-ec-unlock.timer" /etc/systemd/system/dptf-ec-unlock.timer
install -m 755 "$ROOT/scripts/dptf-ec-unlock-sleep" /usr/lib/systemd/system-sleep/dptf-ec-unlock
install -m 644 "$ROOT/scripts/acpi_call.conf" /etc/modules-load.d/acpi_call.conf

systemctl daemon-reload
systemctl enable --now dptf-ec-unlock.timer
/usr/local/sbin/dptf-ec-unlock.sh unlock

echo
echo "Installed. Verify with:"
echo "  systemctl list-timers --all | grep dptf"
echo "  journalctl -u dptf-ec-unlock.service -n 20 --no-pager"
echo "  sudo $ROOT/scripts/verify_power.sh"
