# Changelog

## 2026-10-19

- Initial public release.
- Documented the two-layer 10 W limit: BIOS `Setup:0x551` MSR lock + DPTF/EC `SEPL(0)`.
- Added UEFI Shell scripts (`startup.nsh`, `apply_min.nsh`, `apply_full.nsh`, `revert.nsh`).
- Added `acpi_call` unlock script, systemd service/timer, S3 resume hook, installer, uninstaller, and verifier.
- Added `one-click.sh` and `scripts/setup-uefi.sh` for beginner-friendly setup, plus `docs/08-one-click.md`.
- Verified on a Panasonic CF-SV7 (i5-8350U, Ubuntu 24.04):
  - 8-thread sustained: ~20 W / ~2.79 GHz / ~87 °C.
  - PL2 burst: ~36–39 W / 3.4–3.5 GHz / 97–100 °C.
  - 25 W is not sustainable (100 °C thermal throttling).
