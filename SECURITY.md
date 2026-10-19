# Security Policy

## Scope

This repository contains documentation and helper scripts for changing firmware/EC power limits on a Panasonic CF-SV7. It is **not** a network service and does not process untrusted input.

## Secrets

**Never commit** any of the following:

- GitHub OAuth/PAT tokens (any token starting with `gh`)
- SSH private keys or passwords
- Wi-Fi/Ethernet credentials, IP addresses, MAC addresses
- BIOS dumps or machine-specific NVRAM backups
- Personal paths or hostnames

`.gitignore` excludes `*.bin`, `*.token`, `*.key`, `*.pem`, `secrets*`, and similar patterns, but this is not a substitute for reviewing `git status`.

## Reporting

If you find a security issue (for example, a script that could damage hardware or leak credentials), please open a **private security advisory** on GitHub or contact the repository owner directly. Do not include exploit details in a public issue.

## Hardware risk

The scripts modify BIOS Setup variables and EC power limits. This can cause overheating, instability, data loss, or a bricked machine. Back up your BIOS and understand the risks before running anything. See [docs/05-recovery.md](docs/05-recovery.md).
