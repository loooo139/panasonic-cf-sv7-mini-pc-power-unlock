# 08 · 一键脚本（小白友好）

> 目标：不用理解 MSR/DPTF/EC，直接跑一个脚本，按提示重启，就能到 20 W。

## 1. 最快用法

```bash
git clone https://github.com/loooo139/panasonic-cf-sv7-mini-pc-power-unlock.git
cd panasonic-cf-sv7-mini-pc-power-unlock

# 一键：安装依赖、EC 解锁、检查 BIOS、必要时准备 UEFI Shell
sudo ./one-click.sh
```

如果 BIOS MSR 仍锁定，脚本会准备 UEFI Shell 并提示重启。重启后机器会：

1. 进入 UEFI Shell；
2. 自动执行 `startup.nsh`，写入 `Setup(1):0x551=0`；
3. 自动重启回 Ubuntu；
4. 开机后 `dptf-ec-unlock.timer` 自动执行 `SEPL(0)`。

重新 SSH 登录后验证：

```bash
sudo ./one-click.sh --verify
```

## 2. 脚本做了什么

| 步骤 | 动作 |
|---|---|
| 1/4 | 检查/安装 `acpi-call-dkms`、`msr-tools`、`linux-tools` |
| 2/4 | 检查 `our_bios_backup.bin`；没有则警告/确认 |
| 3/4 | 安装 EC 解锁服务（`SEPL 0` + systemd timer + S3 hook） |
| 4/4 | 读 `MSR 0x610`：已解锁 → 直接验证；锁定 → 准备 UEFI Shell |

## 3. 常用参数

```bash
sudo ./one-click.sh --reboot     # 需要 BIOS 步骤时，准备后自动重启
sudo ./one-click.sh --yes        # 跳过“没有备份”确认（谨慎）
sudo ./one-click.sh --verify     # 结束后跑 8 线程验证（默认）
sudo ./one-click.sh --no-verify  # 不跑验证
sudo ./one-click.sh --help
```

## 4. 预期输出

### 4.1 BIOS 已解锁（或已经做过 UEFI 步骤）

```
[4/4] 检查 BIOS MSR 锁...
  MSR 0x610 = 43816000dd80a0
  ✅ BIOS MSR 已解锁，无需 UEFI Shell 步骤。

运行 8 线程验证（约 35 秒）...
...
-    2786     87       87      19.90    19.11
完成。当前应达到 ~20 W 持续 / ~2.79 GHz。
```

### 4.2 BIOS 仍锁定

```
[4/4] 检查 BIOS MSR 锁...
  MSR 0x610 = 8042816000dd80c8
  ⚠ BIOS MSR 仍锁定（PL1/PL2 LOCK 位为 1）。
  需要一次 UEFI Shell 步骤来写入 Setup(1):0x551=0。
...
=== 已设置 BootNext=Boot0003 ===
  已准备好。现在重启即可应用：
      sudo reboot
```

重启后，机器会自动进入 Shell、写入、重启。你不需要在 Shell 里输入任何命令。

## 5. 前置条件

- **Secure Boot 已关闭**（脚本会检查；如果开启会提示去 BIOS 关闭）。
- **ESP 上有 UEFI 工具**：
  - `/boot/efi/EFI/tools/Shell.efi`
  - `/boot/efi/EFI/tools/setup_var.efi`
  - 如果缺失，脚本会打印下载地址并停止（不会自动下载未签名二进制）。
- **BIOS 备份**：建议先做只读备份。脚本会检查 `our_bios_backup.bin`；没有会要求确认。
- **网络**：第一次运行可能需要 `apt-get` 安装依赖。

## 6. 如果没有 UEFI 工具

脚本会提示：

```
缺少: /boot/efi/EFI/tools/Shell.efi
请下载并放到 /boot/efi/EFI/tools/：
  Shell.efi:     EDK2 UEFI Shell（Ubuntu efi-shell-x64 包，或 EDK2 构建）
  setup_var.efi: https://github.com/datasone/setup_var.efi/releases
```

放好后重新运行：

```bash
sudo ./one-click.sh
```

## 7. 失败/回滚

| 现象 | 处理 |
|---|---|
| 提示 Secure Boot 开启 | BIOS → Security → Secure Boot → Disabled |
| 缺少 Shell.efi / setup_var.efi | 按提示放入 `/boot/efi/EFI/tools/` |
| 没有 BIOS 备份 | 先 `flashrom -p internal --ifd -i bios -r ...`，或用 `--yes` 自担风险 |
| 重启后停在 `Shell>` | 见 [05-recovery.md](05-recovery.md)；不要让它空闲 |
| 重启后自动关机 | EC/BIOS 空闲看门狗；重新设置 BootNext，确保 startup.nsh 在正确位置 |
| 仍是 10 W | 确认 `SEPL 0` 生效；`sudo ./scripts/dptf-ec-unlock.sh unlock`；再看 `rdmsr 0x610` |
| 想回滚 | `sudo ./scripts/uninstall.sh` + `uefi/revert.nsh` |

## 8. 安全提醒

- 一键脚本**不会**刷写 BIOS 固件；它只写 Setup NVRAM 和 EC 功耗限制。
- `setup-uefi.sh` 会创建/复用 UEFI 启动项并设置 `BootNext`；这是**一次性**的。
- 如果你在远程 SSH，重启会短暂离线；确保你能接受。
- 第一次跑之前，强烈建议备份 BIOS 并阅读 [05-recovery.md](05-recovery.md)。
- 20 W 是散热上限；25 W 会 100 °C 热节流。不要用 25 W 做 24/7。

## 9. 手动方式

如果你不想用一键脚本，按 [02-bios-setup.md](02-bios-setup.md) + [03-ec-unlock.md](03-ec-unlock.md) 手动操作。
