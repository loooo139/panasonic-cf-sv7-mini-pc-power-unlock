# Changelog

## 2026-10-19 (boot reliability)

- Fixed the unlock service being blocked by `After=multi-user.target` when `plymouth-quit-wait.service` hangs (observed on the test machine: `multi-user.target` stayed inactive for 10 min, so the EC limit was re-applied and the service never ran).
- Service now uses `After=systemd-modules-load.service`; timer uses `OnActiveSec=10s` + `OnUnitActiveSec=60s`.
- Added 2 s timeouts around the `acpi_call` write/read so a busy EC cannot wedge the oneshot unit.
- Masked `plymouth-quit-wait.service` on the test machine; improved postboot verification (90 s delay + 10 s warmup).
- SSD SMART check: PASSED, 0 reallocated sectors, 0 CRC errors; the boot-time ATA log-page timeouts are benign.

## 2026-10-19 (cooling)

- Added `docs/09-cooling.md` with hardware cooling options: cleaning, PTM7950 repaste, thermal putty, airflow/ducting, external 120 mm fan, and a 25 W feasibility test plan.

## 2026-10-19 (benchmark)

- Added stress-ng `matrixprod` A/B results: 2911.5 → 4073.6 bogo ops/s (+39.9%) for 8 threads, 10 W vs 20 W.

## 2026-10-19 (repo rename)

- Renamed the repository to `panasonic-cf-sv7-mini-pc-power-unlock` and updated the README titles to "松下 CF-SV7 小主机".

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
