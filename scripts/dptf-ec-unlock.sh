#!/usr/bin/env bash
# Panasonic CF-SV7 EC/DPTF power-limit unlock.
#
# Usage:
#   dptf-ec-unlock.sh unlock    # SEPL(0): EC PL1/PL2 <- 0xFF (no EC cap)
#   dptf-ec-unlock.sh restore   # SEPL(1): restore firmware P589/P592 values
#
# The EC mailbox read-back returns 0xffff0000 on this machine even when the
# write succeeds. Verify the effect with turbostat (see verify_power.sh), not
# with the return value alone.
set -euo pipefail

ACTION="${1:-unlock}"
case "$ACTION" in
  unlock)  ACPI_ARGS="SEPL 0" ;;
  restore) ACPI_ARGS="SEPL 1" ;;
  *)
    echo "usage: $0 [unlock|restore]" >&2
    exit 2
    ;;
esac

# acpi_call exposes /proc/acpi/call. Load the module if it is not loaded yet.
if [ ! -e /proc/acpi/call ]; then
  if ! modprobe acpi_call 2>/dev/null; then
    logger -t dptf-ec-unlock "acpi_call module is not available"
    echo "acpi_call is not available. Install it with:" >&2
    echo "  sudo apt-get update && sudo apt-get install -y acpi-call-dkms" >&2
    exit 1
  fi
fi

# _SB.PCI0.LPCB.EC0.SEPL(0|1)
printf '\\_SB.PCI0.LPCB.EC0.%s\n' "$ACPI_ARGS" > /proc/acpi/call

# Read back the EC mailbox result. Strip NUL bytes; ignore the value.
RESULT="$(tr -d '\000' < /proc/acpi/call 2>/dev/null || true)"
logger -t dptf-ec-unlock "$ACTION -> ${RESULT:-<no result>}"
echo "$ACTION: ${RESULT:-<no result>}"
