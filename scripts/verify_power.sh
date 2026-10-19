#!/usr/bin/env bash
# Verify the Panasonic CF-SV7 power-limit unlock.
#
# Run as root:
#   sudo ./scripts/verify_power.sh
#
# The first seconds of the load are the PL2 burst. The script waits 10 s
# before sampling, so the output shows the sustained PL1 state.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root: sudo $0" >&2
  exit 1
fi

echo "=== MSR 0x610 (PKG_POWER_LIMIT) ==="
if command -v rdmsr >/dev/null 2>&1; then
  V="$(rdmsr 0x610)"
  echo "0x610 = $V"
  python3 - "$V" <<'PY'
import sys
v = int(sys.argv[1], 16)
print(f"  PL1 = {(v & 0x7fff) / 8:.2f} W, lock={(v >> 31) & 1}")
print(f"  PL2 = {((v >> 32) & 0x7fff) / 8:.2f} W, lock={(v >> 63) & 1}")
PY
else
  echo "rdmsr not found; install msr-tools"
fi

echo
echo "=== RAPL limits ==="
for d in /sys/class/powercap/intel-rapl:0 /sys/class/powercap/intel-rapl-mmio:0; do
  [ -d "$d" ] || continue
  echo "  $d:"
  echo "    long_term  = $(( $(cat "$d/constraint_0_power_limit_uw") / 1000 )) mW"
  echo "    short_term = $(( $(cat "$d/constraint_1_power_limit_uw" 2>/dev/null || echo 0) / 1000 )) mW"
done

if ! command -v turbostat >/dev/null 2>&1; then
  echo
  echo "turbostat not found; install linux-tools for your kernel, e.g.:"
  echo "  sudo apt-get install -y linux-tools-common linux-tools-generic"
  exit 1
fi

echo
echo "=== 8-thread load: 10 s warm-up, then 10 samples (2 s) ==="
echo "PL2 burst is expected for the first seconds; judge sustained power after the warm-up."
echo

for _ in $(seq 8); do
  ( timeout 35 sha256sum /dev/zero >/dev/null 2>&1 ) &
done
sleep 10
turbostat --quiet -i 2 -n 10 --show Package,CPU,Bzy_MHz,PkgWatt,CorWatt,PkgTmp,CoreTmp 2>/dev/null || true
wait 2>/dev/null || true

echo
echo "=== done ==="
echo "Expected sustained: ~20 W / ~2.79 GHz / ~87 °C."
echo "Expected burst:     ~36-39 W / 3.4-3.5 GHz / 97-100 °C (first seconds)."
