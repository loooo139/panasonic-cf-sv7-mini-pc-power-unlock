# 03 · EC/DPTF 解锁：`SEPL(0)`

> 这一步解决 **EC 独立施加的 10 W 上限**。没有它，即使 `MSR 0x610` 显示 20 W/44 W 且已解锁，实际功耗仍是 10 W。

## 1. 为什么是 EC

DPTF 的 SSDT（`DptfTabl`）里有一条直接写 EC 的路径：

```
IETM.P589 / P590 / P592
        │
        ▼
EC0.REPL
        │
        ├── EC88(0xB5, 0xCA, PL1, time)
        └── EC88(0xB5, 0xCB, PL2, 0)
        │
        ▼
EC 固件独立执行 PL1/PL2
```

`REPL` 的关键代码：

```asl
Name (EPLE, One)
Method (SEPL, 1, Serialized)
{
    EPLE = Arg0
    REPL ()
}

Method (REPL, 0, Serialized)
{
    Name (EPL1, 0xFF)
    Name (EPL2, 0xFF)
    Name (EPLT, Zero)
    If ((EPLE == One))
    {
        EPL1 = \_SB.IETM.P589
        EPL2 = \_SB.IETM.P592
        EPLT = \_SB.PCI0.B0D4.CTN2 (\_SB.IETM.P591)
        If ((\_SB.PCI0.LPCB.EC0.EC34 () > \_SB.IETM.CTOK (\_SB.IETM.P594)))
        {
            EPL1 = \_SB.IETM.P590
        }
    }

    \_SB.PCI0.LPCB.EC0.EC88 (0xB5, 0xCA, EPL1, EPLT)
    \_SB.PCI0.LPCB.EC0.EC88 (0xB5, 0xCB, EPL2, Zero)
}
```

- `EPLE=1`：写入 `P589`/`P592`（本机 EC PL1 ≈ 10 W）。
- `EPLE=0`：`EPL1`/`EPL2` 保持初始值 `0xFF`，EC 收到“无限制/最大值”。
- `SEPL(0)` 就是设置 `EPLE=0` 并立即执行 `REPL`。
- `SEPL(1)` 恢复。

## 2. 安装 `acpi_call`

```bash
sudo apt-get update
sudo apt-get install -y acpi-call-dkms
sudo modprobe acpi_call
ls -l /proc/acpi/call
```

`acpi_call` 提供 `/proc/acpi/call`，可以从用户态调用任意 ACPI 方法。

> Secure Boot 关闭时 DKMS 模块可以直接加载；如果以后开启 Secure Boot，需要签名或关闭。

## 3. 调用

```bash
echo '\_SB.PCI0.LPCB.EC0.SEPL 0' | sudo tee /proc/acpi/call
sudo cat /proc/acpi/call
```

本机返回：

```
0xffff0000
```

**这是 EC 邮箱的回读错误码，不代表写入失败。** 用 `turbostat` 验证实际功耗。

或者使用仓库脚本：

```bash
sudo ./scripts/dptf-ec-unlock.sh unlock
sudo ./scripts/dptf-ec-unlock.sh restore
```

## 4. 结果

`SEPL(0)` 之后，8 线程负载：

| 阶段 | 功耗 | 频率 | 温度 |
|---|---|---|---|
| PL2 爆发（前几秒） | 36–39 W | 3.4–3.5 GHz | 97–100 °C |
| PL1 稳态（约 10 s 后） | **19.9 W** | **2.79 GHz** | **87 °C** |

- EC 的 10 W 上限消失。
- CPU 的 `MSR 0x610` PL1=20 W / PL2=44 W 成为真正上限。
- 100 °C 是 TjMax，CPU 会安全节流；20 W 稳态在 87 °C。
- **25 W 不可持续**：会 100 °C，固件动态把 PL1 降到 10–12 W，再恢复 20 W。详见 [FAQ](06-faq.md)。

## 5. 持久化

EC 的限制会在以下时机被 BIOS/DPTF 重新施加：

- 开机；
- S3 恢复（`\_SB.IETM.WAK` 调用 `REPL`）；
- AC/电池事件（DPTF `_DSM` 里会调用 `SEPL(0/1)`）。

> **重要：** 服务**不能**写 `After=multi-user.target`。本机曾因 `plymouth-quit-wait` 卡死，`multi-user.target` 永远不激活，解锁服务因此一直排队、EC 重新压回 10 W。服务只依赖 `systemd-modules-load.service`，这样即使图形/桌面启动卡住，功耗解锁仍然执行。

所以仓库安装：

| 文件 | 作用 |
|---|---|
| `/etc/modules-load.d/acpi_call.conf` | 开机加载 `acpi_call` |
| `/usr/local/sbin/dptf-ec-unlock.sh` | 执行 `SEPL 0` / `SEPL 1`（ACPI 写入/回读带 2 s 超时） |
| `/etc/systemd/system/dptf-ec-unlock.service` | oneshot 服务；`After=systemd-modules-load.service`，**不依赖** `multi-user.target` |
| `/etc/systemd/system/dptf-ec-unlock.timer` | 定时器激活 10 s 后 + 每 60 秒重试（`OnActiveSec`） |
| `/usr/lib/systemd/system-sleep/dptf-ec-unlock` | S3 恢复后立即执行 |

安装：

```bash
sudo ./scripts/install.sh
```

验证：

```bash
systemctl list-timers --all | grep dptf
journalctl -u dptf-ec-unlock.service -n 20 --no-pager
```

### 5.1 为什么是 60 秒，不是 15 秒

- 第一次 `SEPL(0)` 就生效；EC 只会在**开机、S3 恢复、AC/电池事件**时重新施加限制。
- 60 秒是安全网：即使 EC/DPTF 在启动后重新压回 10 W，也能在一分钟内纠正。
- 不需要 15 秒级的高频调用；那只会多写 EC 邮箱。
- 如果你经常插拔 AC，可以把定时器再改短，或加 udev 规则（本仓库未包含，保持简单）。

## 6. 恢复

```bash
sudo /usr/local/sbin/dptf-ec-unlock.sh restore   # SEPL 1
sudo systemctl disable --now dptf-ec-unlock.timer
```

或直接：

```bash
echo '\_SB.PCI0.LPCB.EC0.SEPL 1' | sudo tee /proc/acpi/call
```

恢复后 EC 重新使用 `P589`/`P592`（约 10 W PL1），实际功耗回到 10 W 左右。

## 7. 故障排查

| 现象 | 检查 |
|---|---|
| `/proc/acpi/call` 不存在 | `modprobe acpi_call`；安装 `acpi-call-dkms` |
| 调用报错 `No such device` | ACPI 路径不对；确认 `\_SB.PCI0.LPCB.EC0.SEPL` 存在 |
| 返回 `0xffff0000` | 正常，继续用 `turbostat` 看功耗 |
| 功耗仍 10 W | 确认 BIOS `0x551=0` 已生效；`rdmsr 0x610` 应为 `43816000dd80a0` |
| 功耗 20 W 但很快掉到 10–12 W | 温度到 100 °C，触发了固件动态热保护；不是 EC 的 10 W 上限 |
| 重启后失效 | 检查 `dptf-ec-unlock.timer` 是否 enabled；`journalctl`；确认 service 里**没有** `After=multi-user.target` |
| 服务不执行 / `NEXT -` | 检查 `systemctl is-active multi-user.target`；若卡在 `plymouth-quit-wait`，执行 `systemctl start plymouth-quit.service`，并 `systemctl mask plymouth-quit-wait.service` 防止下次再卡 |
| S3 恢复后失效 | 检查 `/usr/lib/systemd/system-sleep/dptf-ec-unlock` 是否可执行 |

## 8. 不推荐的替代方案

可以尝试直接用 `EC88` 写具体值，例如按 1 W 单位写 PL1=20 W：

```
\_SB.PCI0.LPCB.EC0.EC88 0xB5 0xCA 0x14 0x00
\_SB.PCI0.LPCB.EC0.EC88 0xB5 0xCB 0x2C 0x00
```

但 **EC 的单位没有确认**（可能是 0.5 W / 1 W），而且不同固件可能不同。`SEPL(0)` 是已验证的路径，优先使用它。

## 9. 无电池 / 适配器

- 本机没有电池；EC 可能更保守。
- 建议使用 **90 W** 足量适配器，保持进出风口畅通。
- 无电池不是 `SEPL(0)` 失效的原因；它只是让 EC 的默认策略更保守。
- 如果你装上电池后功耗更高，以实际散热为准；本机 20 W 已是散热上限。
