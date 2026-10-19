# 05 · 恢复 / 回滚

> 所有改动都是可逆的：BIOS Setup 写的是 NVRAM，EC 限制可以用 `SEPL(1)` 恢复，systemd 服务可以卸载。

## 1. 恢复 EC 限制（回到 ~10 W）

```bash
# 方法 A：使用仓库脚本
sudo /usr/local/sbin/dptf-ec-unlock.sh restore

# 方法 B：直接调用 ACPI
echo '\_SB.PCI0.LPCB.EC0.SEPL 1' | sudo tee /proc/acpi/call

# 停掉定时器，防止再次解锁
sudo systemctl disable --now dptf-ec-unlock.timer
```

恢复后：

- EC 重新使用 `IETM.P589` / `P592`（约 10 W PL1）；
- 8 线程实际功耗回到 ~10 W；
- `MSR 0x610` 可能仍是 20 W/44 W（BIOS 已解锁），但 EC 会把它压回 10 W。

## 2. 卸载持久化

```bash
sudo ./scripts/uninstall.sh
```

它会：

1. 先调用 `restore`（`SEPL 1`）；
2. 停止并禁用定时器；
3. 删除 service/timer/脚本/sleep hook/modules-load 配置；
4. 保留 `acpi-call-dkms` 包（需要的话手动 `apt-get remove`）。

## 3. 恢复 BIOS Setup

重启进入 UEFI Shell，运行：

```
\EFI\tools\setup_var.efi -r Setup(1):0x551=1 Setup(1):0x565=0 Setup(1):0x566=0 Setup(1):0x603=0 Setup(1):0x604=1
```

或 `uefi/revert.nsh`。

| Offset | 恢复值 | 含义 |
|---|---|---|
| `0x551` | 1 | 重新锁定 Package Power Limit MSR |
| `0x565` | 0 | cTDP Boot Mode = Nominal |
| `0x566` | 0 | cTDP Lock = 0 |
| `0x603` | 0 | EC Turbo Control = Disabled |
| `0x604` | 1 | AC Brick = 90 W（按你的原厂备份确认） |

> **`0x604` 的不确定性：** 早期脚本假设原厂是 1（90 W）；有些批次可能是 2（65 W）。恢复前先读一遍你备份的 Setup 值；不确定时，至少恢复 `0x551=1`，重新锁上 MSR。

验证：

```bash
sudo rdmsr 0x610
# 期望回到 0x8042816000dd80c8（PL2 LOCK=1）
```

## 4. 完整 BIOS 恢复

**本项目的操作没有写入 BIOS 固件**（只写了 Setup NVRAM），所以通常不需要重刷。

如果确实需要：

1. 确认备份完整：
   ```bash
   ls -lh /path/to/our_bios_backup.bin
   sha256sum /path/to/our_bios_backup.bin
   ```
2. 优先使用**外部编程器**（CH341A 等）恢复；内部 `flashrom -w` 风险更高。
3. 不要在供电不稳、电量不足、写入过程中断电的情况下刷写。
4. 如果只是 Setup 变量写错，通常可以通过 UEFI Shell 改回，或清除 CMOS/NVRAM（具体方法因机型而异，谨慎操作）。

## 5. 备份清单

| 文件 | 说明 |
|---|---|
| `/path/to/our_bios_backup.bin` | 16 MB BIOS 区域只读备份 |
| `/path/to/oemdptf_original.bin` | 原始 `OemDptfVariable`（735 B） |
| U 盘 `DPTF_BACKUP_*` | 上述文件 + 文档 + UEFI 脚本 |

> 仓库不包含这些文件；请自己保留多份（本机 + U 盘）。

## 6. 紧急情况

### 6.1 开机进不了 Ubuntu

- 进入 BIOS，检查启动顺序；
- 用 UEFI Shell 手动启动 `\EFI\ubuntu\shimx64.efi`；
- 如果只是 `BootNext` 指向 Shell，改为 Ubuntu：
  ```bash
  sudo efibootmgr -n 0000
  ```
  （在能进入系统的情况下）

### 6.2 Shell 停在 `Shell>` 然后关机

- 这是 EC/BIOS 空闲看门狗，不是硬件故障；
- 重新设置 `BootNext`，确保 `startup.nsh` 在 Shell 能找到的目录；
- 或手动执行 `\EFI\tools\revert.nsh`。

### 6.3 功耗/温度异常

- 立即恢复 EC 限制：`SEPL 1`；
- 恢复 BIOS `0x551=1`；
- 检查风扇/出风口；
- 如果温度持续 100 °C，关机冷却。

### 6.4 机器完全不开机

- 断开电源，等待 30 秒；
- 检查是否有外部编程器恢复条件；
- 不要盲目短接/清 CMOS，先查机型资料。

## 7. 恢复后的确认

```bash
# EC 限制恢复
sudo ./scripts/verify_power.sh
# 期望回到 ~10 W / ~2.0 GHz

# MSR 重新锁定
sudo rdmsr 0x610
# 期望 0x8042816000dd80c8
```

如果只想临时回到 10 W，不卸载服务，可以：

```bash
sudo systemctl stop dptf-ec-unlock.timer
echo '\_SB.PCI0.LPCB.EC0.SEPL 1' | sudo tee /proc/acpi/call
```

下次开机定时器还会解锁；要永久恢复，执行 `uninstall.sh` + `revert.nsh`。
