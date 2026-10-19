# 松下 CF-SV7 小主机功耗解锁：10 W → 20 W

> 在 Ubuntu 24.04 上，把松下 CF-SV7 小主机（Let's Note 改迷你主机，i5-8350U）被 BIOS/EC 锁死的 **~10 W 持续功耗** 解锁到 **20 W 持续 / 44 W 短时爆发**。  
> 8 线程负载：**~2.0 GHz → ~2.79 GHz**；短时爆发可到 **3.4–3.5 GHz**。  
> 代价：持续温度约 **87 °C**（TjMax 100 °C）；**25 W 不可持续**，会触发 100 °C 热节流并回落到 20 W。

[English summary](README.en.md) · [诊断细节](docs/01-diagnosis.md) · [恢复指南](docs/05-recovery.md) · [FAQ](docs/06-faq.md) · [一键脚本](docs/08-one-click.md)

> 仓库：<https://github.com/loooo139/panasonic-cf-sv7-mini-pc-power-unlock>

---

## TL;DR

| 项目 | 原厂/默认 | 解锁后 |
|---|---|---|
| 8 线程持续功耗 | ~10 W | **~20 W** |
| 8 线程频率 | ~2.0 GHz | **~2.79 GHz** |
| 短时爆发 | ~10 W | **~36–39 W / 3.4–3.5 GHz**（PL2，数秒） |
| 持续温度 | 54–60 °C | **~87 °C** |
| `MSR 0x610` | PL1 25 W / PL2 44 W，**PL2 LOCK=1** | PL1 20 W / PL2 44 W，**LOCK=0** |
| 实际限制来源 | EC/DPTF 独立压到 10 W | EC 限制解除，CPU RAPL 接管 |

**两根支柱，缺一不可：**

1. **BIOS Setup**：`Package Power Limit MSR Lock = 0`（`Setup:0x551=0`），让 BIOS 能把 CPU 的 RAPL 设为 **20 W 自定义档**，并解除 PL2 锁。
2. **EC/DPTF**：Linux 下用 `acpi_call` 调用 `\_SB.PCI0.LPCB.EC0.SEPL 0`，让 EC 把 PL1/PL2 写成 `0xFF`，**解除 EC 独立施加的 10 W 上限**。

> 只做第 1 步：MSR 解锁，但 EC 仍把实际功耗压在 10 W。  
> 只做第 2 步：EC 限制解除，但 MSR 可能仍是 25 W/PL2 锁定，且没有稳定的 20 W 自定义档。  
> **两步都做**，才是本机验证过的 20 W 稳定配置。

---

## 一键使用（推荐小白）

```bash
git clone https://github.com/loooo139/panasonic-cf-sv7-mini-pc-power-unlock.git
cd panasonic-cf-sv7-mini-pc-power-unlock
sudo ./one-click.sh
```

脚本会安装依赖、安装 EC 解锁服务、检查 BIOS MSR；如果 MSR 仍锁定，会准备 UEFI Shell 并提示重启。重启后机器会自动写入并回到 Ubuntu，再运行 `sudo ./one-click.sh --verify` 验证。详见 [docs/08-one-click.md](docs/08-one-click.md)。

---

## 1. 背景

这台 CF-SV7 被改造成了 24/7 的 Ubuntu SSH 服务器。原厂/BIOS 在 **AC 供电、无电池** 状态下把 CPU 持续功耗限制在 **~10 W**：

- 8 线程 `sha256sum` 负载：`PkgWatt ≈ 9.96 W`，`Bzy_MHz ≈ 2.0 GHz`；
- 单线程仍能短时 boost 到 ~3.5 GHz；
- 温度只有 54–60 °C，**离 TjMax 100 °C 很远**——说明不是散热问题，而是**功耗策略**。

目标：在不修改 BIOS 固件、不焊接硬件的前提下，把持续功耗释放到散热能承受的上限。

最终结论：**20 W 是这台机器散热的天花板**。25 W 会瞬间 100 °C，固件动态把 PL1 降回 10–12 W，再恢复到 20 W，平均性能反而没有提升。

---

## 2. 机器与环境

| 项目 | 值 |
|---|---|
| 机型 | Panasonic CF-SV7（Let's Note） |
| CPU | Intel Core i5-8350U（4C/8T，Kaby Lake R，15 W 名义 TDP） |
| 内存 | 充足（运行 Ubuntu Desktop + SSH Server） |
| 系统 | Ubuntu 24.04 LTS，内核 7.0.0-38-generic |
| BIOS | V3.00L16（与下载的 CF-SV7RDAVS V3.00L23 IFR 偏移一致） |
| 供电 | AC 常电，**无电池**（`/sys/class/power_supply` 只有 AC 和 USB-C） |
| 散热 | 原厂风扇，负载时 `cooling_device4`（Fan）`cur=1/max=1` |
| TjMax | 100 °C |
| Secure Boot | **Disabled**（UEFI Shell / `setup_var.efi` 未签名） |

> 本机没有电池。CF-SV7 的 EC 在无电池时可能额外保守；建议使用 **90 W** 原厂/足量电源适配器，并保持进出风口畅通。

---

## 3. 最终结果

### 3.1 8 线程持续负载（60 秒）

```
CPU      Bzy_MHz   CoreTmp   PkgWatt   CorWatt
-        2786      87        19.90     19.11
0        2786      87        19.90     19.11
1        2786      80
2        2786      87
3        2786      80
...
```

- **持续 20 W / 2.79 GHz / 87 °C**，MSR 稳定在 `0x43816000dd80a0`。
- 前几秒是 **PL2 44 W** 爆发：`~36–39 W / 3.4–3.5 GHz / 97–100 °C`，随后回落到 PL1 20 W。
- 100 °C 是 TjMax，CPU 会安全节流；**20 W 稳态在 87 °C**，留有约 13 °C 余量。

### 3.2 25 W 测试（不推荐）

把 PL1 写到 25 W 后：

```
33.7 W / 3.34 GHz / 100 °C
...
19.9 W / 2.79 GHz / 87 °C   ← 固件把 PL1 动态降回 20 W
```

- 25 W 一上就 100 °C，固件动态把 PL1 降到 **10–12 W**，等温度回落再恢复 20 W。
- **20 W 就是散热上限**；25 W 只会带来更大的温度波动和更差的平均性能。
- PL2 从 44 W 降到 35 W 也不能避免 100 °C 尖峰（散热热容太小），持续仍是 20 W，所以**保留 BIOS 默认 PL2=44 W**。

---

## 4. 功耗限制链路

```
BIOS Setup (Setup varstore, 0x551 / 0x53C / 0x552 / 0x553 / 0x558 / 0x559)
        │
        ▼
CPU RAPL: MSR 0x610  (PL1 / PL2 / LOCK)
        │
        │  原厂: PL1=25W, PL2=44W, PL2 LOCK=1
        │  解锁后: PL1=20W, PL2=44W, LOCK=0
        ▼
DPTF SSDT (DptfTabl / SSDT1)
        │  IETM.P589 / P590 / P592
        ▼
EC0.REPL  ──EC88(0xB5, 0xCA, EPL1, EPLT)──▶  EC 固件
          ──EC88(0xB5, 0xCB, EPL2, 0)────▶  EC 固件
        │
        ▼
EC 独立施加 ~10 W 上限（与 CPU MSR 无关）
```

关键点：**EC 不看 CPU 的 MSR 0x610**。即使 MSR 显示 20 W/44 W 且已解锁，EC 仍能把实际功耗压在 10 W。`SEPL(0)` 的作用就是把 EC 内部的 PL1/PL2 写成 `0xFF`（无限制），让 CPU RAPL 成为真正的上限。

---

## 5. 诊断摘要

完整过程见 [`docs/01-diagnosis.md`](docs/01-diagnosis.md)。核心证据：

| 证据 | 值 | 含义 |
|---|---|---|
| `MSR 0x610`（原厂） | `0x8042816000dd80c8` | PL1 25 W，PL2 44 W，**PL2 LOCK=1** |
| `MSR 0x610`（解锁后） | `0x0043816000dd80a0` | PL1 20 W，PL2 44 W，**LOCK=0** |
| `MSR 0x64B` | `0` | cTDP level 0（`0x565=2` 没有改变它） |
| `MSR 0x64F` | `0x0c200000` → `0x0c200800` | 与封装功耗信息相关 |
| RAPL MSR / MMIO PL1 | 20 W / 20 W | Linux 看到的限制 |
| 实际 8 线程功耗 | **9.96 W** | 低于 RAPL，说明还有 EC 限制 |
| GNVS `MPL0/MPL1/MPL2` | `10000 / 7000 / 10000` mW | DPTF 策略值 |
| PNVS `CLVL / CBMI` | `3 / 0` | 当前使用自定义档 |
| PNVS 三档 | 20/44、15/29、25/44 W | 自定义 / 名义 / cTDP Up |
| ACPI `DptfTabl` | `IETM.P589/P590/P592` → `EC0.REPL` → `EC88` | **EC 限功率的直接路径** |
| `SEPL(0)` 返回 | `0xffff0000` | EC 邮箱回读报错，但写入生效（用功耗验证） |

### 5.1 走过的弯路（均已排除）

- **RAPL MSR 写入**：PL2 LOCK=1 时写入无效。
- **MMIO RAPL 覆盖**：实际功耗仍 10 W。
- **`thermald`**：停止后仍 10.00 W。
- **governor / EPP / `hwp_dynamic_boost`**：不影响 10 W 上限。
- **降压（undervolting）**：`OC_LOCK` 阻止。
- **`OemDptfVariable`**：把 MPL0 10 W 改成 20 W，变量持久化，但 GNVS `MPL0` 仍是 10000，功耗仍 10 W；已恢复原文件。
- **BIOS 菜单**：`Advanced` 里没有可用的 `Package Power Limit MSR Lock` / `Configurable TDP` / `Platform PL1/PL2` 选项（隐藏或未暴露）。

---

## 6. 操作步骤

### 6.0 一键脚本（推荐）

```bash
sudo ./one-click.sh
```

它会完成依赖、EC 解锁、BIOS MSR 检查和 UEFI Shell 准备。详见 [docs/08-one-click.md](docs/08-one-click.md)。下面是手动步骤。

> **风险提示**：涉及 BIOS Setup 变量和 EC 命令。请先完整备份 BIOS，确认你能接受“变砖/需要拆机恢复”的风险。本文记录的是本机验证过的路径，不保证所有 CF-SV7 批次完全一致。

### 6.1 备份（必做）

```bash
# 只读备份 BIOS 区域（整片 16 MB 读取可能在 0x3000 失败）
sudo flashrom -p internal --ifd -i bios -r /path/to/our_bios_backup.bin

# 备份 OemDptfVariable（如果之前动过）
ls -l /path/to/oemdptf_original.bin
```

把 `our_bios_backup.bin`、`oemdptf_original.bin`、本文档和 UEFI 脚本复制到 U 盘（下面的 `/path/to/` 换成你的实际路径）：

```bash
sudo mkdir -p /mnt/usb/DPTF_BACKUP_$(date +%Y%m%d)
sudo cp /path/to/our_bios_backup.bin /mnt/usb/DPTF_BACKUP_*/
sudo cp /path/to/oemdptf_original.bin /mnt/usb/DPTF_BACKUP_*/
```

> 仓库**不包含** BIOS dump（机器相关、版权原因）。请只在自己的本地/U 盘保留。

### 6.2 BIOS Setup：解除 MSR 锁（UEFI Shell）

完整步骤见 [`docs/02-bios-setup.md`](docs/02-bios-setup.md)。摘要：

1. **关闭 Secure Boot**（BIOS → Security → Secure Boot → Disabled）。
2. 准备 UEFI Shell 和 `setup_var.efi`：
   - `Shell.efi`：EDK2 / `efi-shell-x64`；
   - `setup_var.efi`：<https://github.com/datasone/setup_var.efi/releases>。
3. 复制到 ESP：
   ```bash
   sudo mkdir -p /boot/efi/EFI/tools
   sudo cp Shell.efi setup_var.efi /boot/efi/EFI/tools/
   ```
4. 添加 UEFI 启动项（设备/分区按 `lsblk` 调整）：
   ```bash
   sudo efibootmgr -c -d /dev/nvme0n1 -p 1 -L "UEFI Shell (DPTF)" -l '\EFI\tools\Shell.efi'
   sudo efibootmgr -n 0003   # 用上一步输出的 BootXXXX 编号
   ```
5. 把 `uefi/startup.nsh` 放到 **ESP 根目录** 和 **`\EFI\tools\`** 两处（Shell 的工作目录可能是其中之一）：
   ```bash
   sudo cp uefi/startup.nsh /boot/efi/startup.nsh
   sudo cp uefi/startup.nsh /boot/efi/EFI/tools/startup.nsh
   ```
6. 重启，Shell 会自动执行并重启：
   ```
   \EFI\tools\setup_var.efi -r Setup(1):0x551=0 Setup(1):0x565=2 Setup(1):0x566=0 Setup(1):0x603=1 Setup(1):0x604=1
   ```

**为什么是 `Setup(1)`：** `setup_var.efi` 会把同名变量按 GUID 排序；本机有两个 `Setup`：

- `Setup(0)`：11 字节小变量（GUID `80E1202E-2697-4264-9CC9-80762C3E5863`）；
- `Setup(1)`：主变量，`0x11CA` 字节（GUID `EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9`）——**这才是 BIOS Setup 的主 varstore**。

如果 `Setup(1)` 不适用，先在 Shell 里探测：

```
\EFI\tools\setup_var.efi Setup:0x551
```

按提示选择能读到值的 ID。

**实际效果说明（诚实记录）：**

- `0x551=0`（Package Power Limit MSR Lock）**确实生效**：`MSR 0x610` 从 `0x804281600000...` 变成 `0x0043816000dd80a0`，PL1=20 W、PL2=44 W、两个 LOCK 位都为 0。
- `0x565=2`（cTDP Up）**没有改变** `MSR 0x64B`（仍为 0）。`0x566` / `0x603` / `0x604` 可能位于其他 varstore，或本机固件不接受；不要把它们当作已生效。
- **决定性的 BIOS 改动是 `0x551=0`**。其余偏移保留在脚本里，方便其他批次尝试。

**Shell 空闲关机问题：** 如果 `startup.nsh` 没有被找到，Shell 会停在 `Shell>` 提示符，过一会 EC/BIOS 的空闲看门狗会**直接关机**。把 `startup.nsh` 同时放到 ESP 根目录和 `\EFI\tools\`，并让脚本执行完自动 `reset`，即可避免。

### 6.3 Linux：解除 EC/DPTF 10 W 限制

```bash
# 1) 安装 acpi_call（DKMS，内核升级后会自动重建）
sudo apt-get update
sudo apt-get install -y acpi-call-dkms
sudo modprobe acpi_call

# 2) 一次性解除 EC 限制
echo '\_SB.PCI0.LPCB.EC0.SEPL 0' | sudo tee /proc/acpi/call

# 3) 回读（返回 0xffff0000 是 EC 邮箱回读错误，但写入通常已生效）
sudo cat /proc/acpi/call

# 4) 验证
sudo ./scripts/verify_power.sh
```

**原理：** DPTF SSDT 的 `\_SB.PCI0.LPCB.EC0.REPL` 会把 `IETM.P589`（PL1）和 `IETM.P592`（PL2）通过 `EC88(0xB5, 0xCA/0xCB, ...)` 写进 EC。`SEPL(0)` 把 `EPLE` 设为 0，`REPL` 随即把 **0xFF** 写入 EC 的 PL1/PL2；`SEPL(1)` 恢复 `P589/P592`。详见 [`docs/03-ec-unlock.md`](docs/03-ec-unlock.md)。

> **不要**每 15 秒反复调用 `SEPL(0)`。第一次调用就生效；EC 只会在开机、S3 恢复、AC/电池事件时重新施加限制。仓库使用 **开机一次 + 5 分钟安全定时器 + S3 恢复钩子**。

### 6.4 持久化（推荐）

仓库提供一键安装：

```bash
sudo ./scripts/install.sh
```

它会：

- 安装 `acpi_call` 模块加载配置；
- 安装 `/usr/local/sbin/dptf-ec-unlock.sh`（支持 `unlock` / `restore`）；
- 安装 `dptf-ec-unlock.service` 和 `dptf-ec-unlock.timer`（开机 10 秒后执行，之后每 5 分钟一次）；
- 安装 S3 恢复钩子 `/usr/lib/systemd/system-sleep/dptf-ec-unlock`；
- 立即执行一次 `SEPL 0`。

验证：

```bash
systemctl list-timers --all | grep dptf
journalctl -u dptf-ec-unlock.service -n 20 --no-pager
```

手动卸载/恢复：

```bash
sudo ./scripts/uninstall.sh
```

---

## 7. 验证

### 7.1 看 MSR

```bash
sudo rdmsr 0x610
# 期望: 43816000dd80a0
#   PL1 = 0x0a0 = 20 W
#   PL2 = 0x160 = 44 W
#   bit31 / bit63 = 0  (未锁)
```

解码：

```bash
python3 - <<'PY'
v = int(input("0x610 = "), 16)
print(f"PL1 = {(v & 0x7fff)/8:.2f} W, lock={ (v>>31)&1 }")
print(f"PL2 = {((v>>32)&0x7fff)/8:.2f} W, lock={ (v>>63)&1 }")
PY
```

### 7.2 负载测试

```bash
sudo ./scripts/verify_power.sh
```

脚本会：

1. 打印 `MSR 0x610` 和 RAPL 限制；
2. 启动 8 个 `sha256sum /dev/zero`；
3. **先等 10 秒**（避开 PL2 爆发的误导）；
4. 用 `turbostat` 采样 10 次（每 2 秒）。

期望：

- 前几秒：`PkgWatt ≈ 36–39 W`，`Bzy_MHz ≈ 3.4–3.5 GHz`，`CoreTmp ≈ 97–100 °C`（PL2 爆发，正常）；
- 10 秒后：`PkgWatt ≈ 20 W`，`Bzy_MHz ≈ 2.79 GHz`，`CoreTmp ≈ 87 °C`（PL1 稳态）。
- 如果 10 秒后仍是 10 W / 2.0 GHz，说明 `SEPL(0)` 没有生效或 EC 重新施加了限制。
- 如果 10 秒后是 25 W 但很快掉到 10–12 W，说明 CPU 到了 100 °C，触发了固件的动态热保护——这不是 EC 的 10 W 上限。

> 旧的 `power_verify_after_boot.log` 只采样前 4 秒，所以会看到 36.85 W / 100 °C。**不要用前 4 秒判断持续性能。**

### 7.3 看温度/风扇

```bash
turbostat --quiet -i 1 -n 5 --show Package,Bzy_MHz,PkgWatt,CorWatt,PkgTmp,CoreTmp
cat /sys/class/thermal/cooling_device4/cur_state   # Fan: 1 = max
```

---

## 8. 恢复 / 回滚

### 8.1 恢复 EC 限制（10 W）

```bash
sudo /usr/local/sbin/dptf-ec-unlock.sh restore   # 调用 SEPL 1
sudo systemctl disable --now dptf-ec-unlock.timer
```

或者直接：

```bash
echo '\_SB.PCI0.LPCB.EC0.SEPL 1' | sudo tee /proc/acpi/call
```

### 8.2 恢复 BIOS Setup

重启进入 UEFI Shell，运行：

```
\EFI\tools\setup_var.efi -r Setup(1):0x551=1 Setup(1):0x565=0 Setup(1):0x566=0 Setup(1):0x603=0 Setup(1):0x604=1
```

即 [`uefi/revert.nsh`](uefi/revert.nsh)。这会把：

- `0x551=1`：重新锁定 Package Power Limit MSR；
- `0x565=0`：cTDP Boot Mode = Nominal；
- `0x566=0`：cTDP Lock = 0；
- `0x603=0`：EC Turbo Control = Disabled；
- `0x604=1`：AC Brick = 90 W（**请按你自己的原始备份确认**；有些批次原厂是 2=65 W）。

> `revert.nsh` 里的 `0x604=1` 是沿用本机早期脚本的假设。恢复前请先读一遍你备份的 Setup 值；不确定时，只恢复 `0x551=1` 也能重新锁上 MSR。

### 8.3 完整 BIOS 恢复

**没有执行过 BIOS 写入**，所以通常不需要。若真的需要：

- 保留 `/path/to/our_bios_backup.bin`（16 MB）；
- 优先使用**外部编程器**（CH341A 等）恢复；
- 不要在未确认备份完整、供电稳定的情况下用 `flashrom -w` 写内部 BIOS——写坏可能变砖。

### 8.4 卸载持久化

```bash
sudo ./scripts/uninstall.sh
```

---

## 9. 注意事项 / FAQ

更完整的 FAQ 见 [`docs/06-faq.md`](docs/06-faq.md)。

**Q: 为什么 25 W 不稳定？**  
A: 这台机器的散热只能稳定耗散约 20 W。25 W 会让封装瞬间到 100 °C，固件动态把 PL1 降到 10–12 W，等温度回落再恢复 20 W。平均性能并不比 20 W 高。

**Q: 为什么 `SEPL(0)` 返回 `0xffff0000`？**  
A: EC 邮箱命令的回读错误码，不代表写入失败。用 `turbostat` 看实际功耗：从 10 W 变 20 W 就说明生效了。仓库脚本会忽略该返回值并记录日志。

**Q: 需要每 15 秒调用一次吗？**  
A: 不需要。EC 只在开机、S3 恢复、AC/电池事件时重新施加限制。仓库使用 **开机一次 + 5 分钟安全定时器 + S3 恢复钩子**。反复调用不会更稳，只会多写 EC。

**Q: 没有电池会有影响吗？**  
A: 本机没有电池，EC 可能更保守。解锁在 AC 下有效。建议使用 **90 W** 足量适配器，并保持通风。

**Q: 重启后还会生效吗？**  
A: BIOS 的 `0x551=0` 存在 NVRAM，重启保留；EC 的解限由 systemd 定时器/恢复钩子重新施加。

**Q: BIOS 升级后会失效吗？**  
A: 可能会。升级后 Setup 变量可能重置，需要重新跑 UEFI 脚本；EC 路径也可能变化。

**Q: Secure Boot 必须关闭吗？**  
A: 是。`Shell.efi` 和 `setup_var.efi` 未签名，Secure Boot 开启时会被拒绝。

**Q: 风扇很吵 / 温度高？**  
A: 20 W 持续时风扇会接近满载，87 °C 是正常稳态。确保进出风口不被遮挡；24/7 运行建议环境温度 < 30 °C。

**Q: 能降压吗？**  
A: 本机 `OC_LOCK` 阻止 undervolting；不需要，也没成功。

**Q: `thermald` 呢？**  
A: 停掉 `thermald` 后仍是 10 W，说明限制在 EC/DPTF，不在 Linux 热管理。

**Q: `OemDptfVariable` 改 MPL0 有用吗？**  
A: 本机试过：变量持久化了，但 GNVS `MPL0` 仍是 10000，功耗仍 10 W。已恢复原文件。不要重复这条路。

**Q: cTDP `0x565=2` 为什么没生效？**  
A: `MSR 0x64B` 仍是 0。这个偏移可能不在主 `Setup` varstore，或本机固件忽略。真正有效的是 `0x551=0` + `SEPL(0)`。

**Q: 可以套用到别的 CF-SV7 吗？**  
A: 同 BIOS/同 EC 的批次大概率可以，但必须自行验证：`MSR 0x610`、ACPI `SEPL` 路径、Setup varstore/GUID 可能不同。风险自负。

---

## 10. 仓库结构

```
panasonic-cf-sv7-mini-pc-power-unlock/
├── one-click.sh                  # 小白一键入口
├── README.md                     # 本文
├── README.en.md                  # 英文摘要
├── LICENSE                       # MIT
├── .gitignore
├── CONTRIBUTING.md
├── SECURITY.md
├── CHANGELOG.md
├── docs/
│   ├── 01-diagnosis.md           # MSR / RAPL / GNVS / PNVS / DPTF 诊断
│   ├── 02-bios-setup.md          # UEFI Shell + setup_var.efi 详细步骤
│   ├── 03-ec-unlock.md           # SEPL / REPL / EC88 原理
│   ├── 04-verification.md        # 验证方法与预期数据
│   ├── 05-recovery.md            # 恢复/回滚
│   ├── 06-faq.md                 # 常见问题
│   ├── 07-timeline.md            # 本次调试时间线
│   └── 08-one-click.md           # 一键脚本使用说明
├── scripts/
│   ├── setup-uefi.sh             # 准备 UEFI Shell / BootNext
│   ├── install.sh                # 安装持久化
│   ├── uninstall.sh              # 卸载并恢复 EC 限制
│   ├── dptf-ec-unlock.sh         # unlock / restore
│   ├── dptf-ec-unlock.service
│   ├── dptf-ec-unlock.timer
│   ├── dptf-ec-unlock-sleep      # S3 恢复钩子
│   ├── acpi_call.conf
│   └── verify_power.sh
└── uefi/
    ├── README.md
    ├── startup.nsh               # 自动执行 + 重启
    ├── apply_min.nsh
    ├── apply_full.nsh
    └── revert.nsh
```

---

## 11. 关键寄存器 / 偏移速查

### 11.1 MSR

| MSR | 原厂 | 解锁后 | 说明 |
|---|---|---|---|
| `0x610` | `0x8042816000dd80c8` | `0x0043816000dd80a0` | PKG_POWER_LIMIT：PL1/PL2/LOCK |
| `0x64B` | `0` | `0` | cTDP level（未变） |
| `0x64F` | `0x0c200000` | `0x0c200800` | 封装功耗信息相关 |
| `0x614` | `0x78` | `0x78` | PKG_POWER_INFO（TDP 15 W） |
| `0x1AD` | `0x24242424` | `0x24242424` | TURBO_RATIO_LIMIT（3.6 GHz） |
| `0x19C` | `0x88340c00` | — | THERM_STATUS（无 PROCHOT） |

### 11.2 BIOS Setup varstore

- GUID：`EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9`
- Name：`Setup`
- Size：`0x11CA`
- `setup_var.efi` ID：**`Setup(1)`**（主变量；`Setup(0)` 是 11 字节小变量）

| Offset | 含义 | 原厂 | 解锁值 |
|---|---|---|---|
| `0x551` | Package Power Limit MSR Lock | 1 | **0** |
| `0x565` | Configurable TDP Boot Mode | 0 | 2（本机未生效） |
| `0x566` | Configurable TDP Lock | 0 | 0 |
| `0x53C` | PL1 Override | 0 | 1（full 脚本） |
| `0x552` | Platform PL1 Enable | 0 | 1（full 脚本） |
| `0x553(4)` | Platform PL1 (mW) | — | 20000（full 脚本） |
| `0x557` | PL1 Time Window | — | 28（full 脚本） |
| `0x558` | Platform PL2 Enable | 0 | 1（full 脚本） |
| `0x559(4)` | Platform PL2 (mW) | — | 30000（full 脚本） |
| `0x603` | EC Turbo Control Mode | 0 | 1（本机未验证生效） |
| `0x604` | AC Brick Capacity | 1/2 | 1（90 W；按备份确认） |

### 11.3 ACPI / DPTF

| 对象 | 说明 |
|---|---|
| `\_SB.PCI0.LPCB.EC0.SEPL(0/1)` | 0 = EC 解除限制；1 = 恢复 |
| `\_SB.PCI0.LPCB.EC0.REPL()` | 把 `IETM.P589/P592` 写入 EC |
| `EC88(0xB5, 0xCA, PL1, time)` | EC 邮箱命令：写 PL1 |
| `EC88(0xB5, 0xCB, PL2, 0)` | EC 邮箱命令：写 PL2 |
| `IETM.P589` | EC PL1（本机 ~10 W） |
| `IETM.P590` | 高温/低电时的 PL1 回退值 |
| `IETM.P592` | EC PL2 |
| `GNVS MPL0/MPL1/MPL2` | 10000 / 7000 / 10000 mW |
| `PNVS CLVL/CBMI` | 3 / 0 |

---

## 12. 参考

- Intel SDM：`MSR_PKG_POWER_LIMIT (0x610)`、`MSR_PKG_POWER_INFO (0x614)`、`MSR_CONFIG_TDP_*`
- Linux `intel_rapl` / `intel_pstate` / `acpi-call-dkms`
- `datasone/setup_var.efi`：<https://github.com/datasone/setup_var.efi>
- EDK2 UEFI Shell
- ACPICA `iasl` / `acpidump`

---

## 隐私与安全

- 本仓库**不包含** GitHub token、SSH 密码/私钥、IP/MAC、本机用户名/主机名、个人绝对路径。
- 本仓库**不包含** BIOS dump 或 `OemDptfVariable`；这些只保留在本地/U 盘。
- `.gitignore` 已排除 `*.bin`、`*.token`、`*.key`、`*.pem`、`secrets*` 等。
- 如果你 fork/提交，请先 `git status`，不要把凭据或 BIOS dump 加进去。
- 安全报告方式见 [SECURITY.md](SECURITY.md)。

## 贡献

欢迎 issue/PR，尤其是其他 CF-SV7 批次的 IFR/ACPI 差异、不同的 `SEPL` 路径、散热数据。请勿提交 BIOS dump、凭据或个人路径。见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 13. 免责声明

本项目是**单机实验记录**，不是官方工具。修改 BIOS Setup 变量、EC 寄存器、功耗限制可能导致：

- 过热、降频、死机、数据损坏；
- 电池/适配器/VRM 过载；
- BIOS 变砖（需要拆机/编程器恢复）。

**请先备份、先理解、再操作。** 作者不对任何硬件损坏、数据丢失或保修失效负责。

## 14. License

MIT License，见 [LICENSE](LICENSE)。  
文档中的 BIOS/EC 逆向信息仅用于本机维护与学习；BIOS 固件本身不包含在本仓库中。
