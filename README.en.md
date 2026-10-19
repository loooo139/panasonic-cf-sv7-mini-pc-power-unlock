# Panasonic CF-SV7 Power Limit Unlock: 10 W → 20 W

> A field note / reproducible guide for unlocking the firmware-enforced ~10 W package power limit on a Panasonic CF-SV7 (Intel i5-8350U) running Ubuntu 24.04 as a 24/7 SSH server.

[中文完整文档](README.md) · [Diagnosis](docs/01-diagnosis.md) · [Recovery](docs/05-recovery.md) · [FAQ](docs/06-faq.md) · [One-click](docs/08-one-click.md)

> Repository: <https://github.com/loooo139/cf-sv7-power-unlock>

## TL;DR

| Item | Stock | Unlocked |
|---|---|---|
| 8-thread sustained package power | ~10 W | **~20 W** |
| 8-thread frequency | ~2.0 GHz | **~2.79 GHz** |
| Short burst | ~10 W | **~36–39 W / 3.4–3.5 GHz** (PL2, seconds) |
| Sustained temperature | 54–60 °C | **~87 °C** |
| `MSR 0x610` | PL1 25 W / PL2 44 W, **PL2 LOCK=1** | PL1 20 W / PL2 44 W, **LOCK=0** |
| Real limiter | EC/DPTF enforces 10 W | EC limit lifted; CPU RAPL takes over |

**Two independent steps are required:**

1. **BIOS Setup**: set `Package Power Limit MSR Lock = 0` (`Setup:0x551=0`) via a UEFI Shell and `setup_var.efi`. This unlocks the RAPL MSR and lets the BIOS apply the 20 W custom TDP level.
2. **EC/DPTF**: from Linux, call `\_SB.PCI0.LPCB.EC0.SEPL 0` through `acpi_call`. This makes the EC write `0xFF` to its internal PL1/PL2, removing the EC's independent 10 W cap.

Doing only step 1 leaves the EC 10 W cap in place. Doing only step 2 may leave the MSR at 25 W/locked. **Both steps together** produce the verified 20 W configuration.

## One-click (beginner-friendly)

```bash
git clone https://github.com/loooo139/cf-sv7-power-unlock.git
cd cf-sv7-power-unlock
sudo ./one-click.sh
```

It installs dependencies, installs the EC unlock service, checks the MSR, and prepares the UEFI Shell step if needed. See [docs/08-one-click.md](docs/08-one-click.md).

## Why 20 W and not 25 W?

The CF-SV7 cooling system can dissipate about **20 W** sustainably. At 25 W the package hits **100 °C (TjMax)** within seconds; the firmware dynamically drops PL1 to 10–12 W until the temperature falls, then restores 20 W. The average performance is not better than a stable 20 W. Reducing PL2 from 44 W to 35 W does not avoid the 100 °C spike; the thermal mass is simply too small. **Keep the BIOS default PL1=20 W / PL2=44 W.**

## Quick start

> Prerequisites: Secure Boot disabled, a full BIOS backup, and a UEFI Shell + `setup_var.efi` on the ESP. See [docs/02-bios-setup.md](docs/02-bios-setup.md).

```bash
# 1) BIOS step (one-time, via UEFI Shell):
#    \EFI\tools\setup_var.efi -r Setup(1):0x551=0 Setup(1):0x565=2 Setup(1):0x566=0 Setup(1):0x603=1 Setup(1):0x604=1

# 2) Linux EC step:
sudo apt-get install -y acpi-call-dkms
sudo modprobe acpi_call
echo '\_SB.PCI0.LPCB.EC0.SEPL 0' | sudo tee /proc/acpi/call

# 3) Persist:
sudo ./scripts/install.sh

# 4) Verify (8 threads, 10 s warm-up, then 10 samples):
sudo ./scripts/verify_power.sh
```

Expected: first seconds show a PL2 burst around 36–39 W / 3.4–3.5 GHz / 97–100 °C; after ~10 s the package settles at **~20 W / ~2.79 GHz / ~87 °C**.

## How it works

```
BIOS Setup (0x551 / 0x53C / 0x552 / 0x553 / 0x558 / 0x559)
        │
        ▼
CPU RAPL: MSR 0x610 (PL1 / PL2 / LOCK)
        │
        ▼
DPTF SSDT (DptfTabl / SSDT1)
        │  IETM.P589 / P590 / P592
        ▼
EC0.REPL ── EC88(0xB5, 0xCA, PL1, time) ──▶ EC firmware
         ── EC88(0xB5, 0xCB, PL2, 0) ─────▶ EC firmware
        │
        ▼
EC enforces ~10 W independently of the CPU MSR
```

`SEPL(0)` sets `EPLE=0`; `REPL` then writes `0xFF` to both EC power-limit registers. `SEPL(1)` restores the firmware values. The call returns `0xffff0000` (EC mailbox read-back error) on this machine, but the write takes effect — verify with `turbostat`, not with the return value.

## Recovery

```bash
# Restore the EC limit:
sudo /usr/local/sbin/dptf-ec-unlock.sh restore
sudo systemctl disable --now dptf-ec-unlock.timer

# Restore the BIOS Setup values via UEFI Shell:
# \EFI\tools\setup_var.efi -r Setup(1):0x551=1 Setup(1):0x565=0 Setup(1):0x566=0 Setup(1):0x603=0 Setup(1):0x604=1
```

See [docs/05-recovery.md](docs/05-recovery.md).

## Repository layout

```
one-click.sh   beginner-friendly entry point
docs/          detailed diagnosis, BIOS, EC, verification, recovery, FAQ, timeline, one-click guide
scripts/       UEFI setup helper, acpi_call unlock service, timer, sleep hook, installer, verifier
uefi/          startup.nsh, apply_min.nsh, apply_full.nsh, revert.nsh
```

## What is not included

- The 16 MB BIOS dump and the `OemDptfVariable` backup are **not** in this repository: they are machine-specific and may contain copyrighted firmware. Keep them locally / on a USB drive.
- No credentials, IP addresses, or SSH keys are included.

## Disclaimer

This is a single-machine experiment, not an official tool. Modifying BIOS Setup variables, EC registers, or power limits can cause overheating, instability, data loss, or a bricked machine. Back up first, understand the risks, and proceed at your own risk. The author is not responsible for any damage.

## License

MIT, see [LICENSE](LICENSE).
