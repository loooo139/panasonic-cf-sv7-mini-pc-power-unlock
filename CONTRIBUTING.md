# Contributing

Thanks for your interest in this project. It is a single-machine field note, so hardware-specific reports are especially valuable.

## Before you open a PR

1. **Do not commit credentials or machine-specific binaries.**  
   This includes BIOS dumps (`*.bin`), `OemDptfVariable`, SSH keys, tokens, passwords, IP/MAC addresses, and personal paths. `.gitignore` covers common cases, but check `git status` before committing.
2. **Test on real hardware.**  
   If your change affects the BIOS/UEFI scripts or the EC unlock, state the model, BIOS version, and observed `MSR 0x610` / `turbostat` results.
3. **Keep the two-step model clear.**  
   The project relies on both the BIOS Setup unlock (`0x551=0`) and the EC unlock (`SEPL(0)`). Do not present one as sufficient for a stable 20 W result.

## Useful reports

- Other CF-SV7 / Let's Note batches with a different Setup varstore layout.
- Different `SEPL` / `EC88` ACPI paths.
- Thermal results at 20 W / 25 W with different cooling setups.
- Kernel/Ubuntu versions where `acpi-call-dkms` needs a different install path.

## Style

- Markdown: Chinese main docs, keep commands copy-pasteable.
- Shell: `#!/usr/bin/env bash`, `set -euo pipefail`, no personal paths.
- UEFI scripts: `@echo -off`, absolute `\EFI\tools\...` paths, auto-reboot on failure.

## License

By contributing, you agree that your contributions are licensed under the MIT License.
