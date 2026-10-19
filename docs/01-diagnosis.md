# 01 · 诊断：10 W 限制到底在哪一层

## 1. 现象

机器：Panasonic CF-SV7，i5-8350U，Ubuntu 24.04，AC 常电，无电池。

8 线程 `sha256sum /dev/zero` 负载下：

```
PkgWatt ≈ 9.96 W
Bzy_MHz ≈ 2.0 GHz
CoreTmp ≈ 54–60 °C
```

单线程仍能短时到 ~3.5 GHz；TjMax 100 °C，温度远未到顶。**这不是散热问题，是功耗策略。**

## 2. 第一层：CPU RAPL / MSR

### 2.1 `MSR 0x610`（PKG_POWER_LIMIT）

原厂值：

```
0x610 = 0x8042816000dd80c8
```

解码：

| 字段 | 值 | 含义 |
|---|---|---|
| PL1 (bits 14:0) | `0xC8` = 200/8 | 25.00 W |
| PL1 enable (bit 15) | 1 | 使能 |
| PL1 clamp (bit 16) | 1 | clamp |
| PL1 time window (bits 23:17) | `0x6E` | 110 × 0.25 s = 27.5 s |
| PL1 lock (bit 31) | 0 | 未锁 |
| PL2 (bits 46:32) | `0x160` = 352/8 | 44.00 W |
| PL2 enable (bit 47) | 1 | 使能 |
| PL2 clamp (bit 48) | 1 | clamp |
| PL2 time window (bits 55:49) | `0x21` | 33 × 0.25 s = 8.25 s |
| **PL2 lock (bit 63)** | **1** | **锁定** |

所以 CPU 侧并不是 10 W；而是 **PL1 25 W / PL2 44 W，PL2 被锁**。实际却只有 10 W，说明还有第二层限制。

### 2.2 RAPL sysfs

```bash
cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw        # 20000000
cat /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw        # 44000000
cat /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw   # 20000000
```

MSR 和 MMIO 都显示 20 W / 44 W，但实际 10 W。**RAPL 不是最终限制。**

### 2.3 为什么不是 cTDP

- `MSR 0x64B`（cTDP level）= **0**。
- `PNVS` 里有三档：

| 偏移 | PL1 / PL2 |
|---|---|
| `PNVS+0x10` | 20 W / 44 W（自定义） |
| `PNVS+0x18` | 15 W / 29 W（名义） |
| `PNVS+0x20` | 25 W / 44 W（cTDP Up） |

- `CLVL=3`、`CBMI=0`：BIOS 当前使用自定义档（20 W / 44 W）。
- 即使 `MSR 0x610` 是 25 W，实际仍 10 W；所以 cTDP 也不是 10 W 的来源。

## 3. 第二层：ACPI / DPTF / EC

### 3.1 反编译 DPTF SSDT

```bash
sudo cp /sys/firmware/acpi/tables/SSDT1 /tmp/SSDT1.dat
sudo chmod 644 /tmp/SSDT1.dat
iasl -d /tmp/SSDT1.dat
```

`SSDT1` 的 header 是 `DptfTabl`（`DptfTa` / `DptfTabl`，92100 字节），即 Intel DPTF 的策略表。

搜索关键词：

```bash
grep -n -iE 'MPL0|MPL1|MPL2|PLCS|PLVL|PPCC|EC0_|_DSM|RPOW|POWL|power limit' SSDT1.dsl
```

关键结果：

```
External (_SB_.PCI0.LPCB.EC0_.EC88, MethodObj)    // 4 Arguments
External (MPL0, IntObj)
External (MPL1, IntObj)
External (MPL2, IntObj)
```

### 3.2 `EC0.REPL`：EC 限功率的直接路径

在 `Scope (\_SB.PCI0.LPCB.EC0)` 中：

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

解释：

- `EPLE` 默认 **1**（限制启用）。
- `EPL1` / `EPL2` 最终来自 **`IETM.P589` / `P592`**（EC 的 PL1 / PL2）。
- 如果 `EC34()`（温度/电池相关）超过阈值，`EPL1` 回退到 `P590`。
- 通过 **`EC88(0xB5, 0xCA, PL1, time)`** 和 **`EC88(0xB5, 0xCB, PL2, 0)`** 写进 EC 邮箱。
- **EC 固件独立执行这个限制，不读取 CPU 的 `MSR 0x610`。**

`EC88` 的实现（DSDT）：

```asl
Method (EC88, 4, NotSerialized)
{
    If ((ECST == Zero))
    {
        Local0 = EC86 (Arg0, Arg1, Arg2, Arg3)
    }
    Else
    {
        Local0 = EC87 (Arg0, Arg1, Arg2, Arg3)
    }
    Return (Local0)
}
```

`EC87` 把 `Arg0..Arg3` 写入 `ER04..ER07`（EC 邮箱），等待 `ER04` 完成，再拼出返回值。`SEPL(0)` 的回读是 `0xffff0000`，但写入已经发生。

### 3.3 `SEPL(0)` 的语义

- `SEPL(1)`：`EPLE=1`，`REPL` 写入 `P589` / `P592`（本机约 10 W / 44 W）。
- `SEPL(0)`：`EPLE=0`，`EPL1` / `EPL2` 保持初始值 **`0xFF`**，`REPL` 把 **`0xFF`** 写进 EC 的 PL1/PL2。
- `0xFF` 在这里被 EC 解释为“无限制/最大值”，于是 EC 不再压 10 W；CPU 的 RAPL（20 W / 44 W）成为真正上限。

### 3.4 GNVS / PNVS 读数

本机（地址是示例，重启后可能变化）：

```bash
GNVS=0x7B454000
PNVS=0x763DC000

dd if=/dev/mem bs=1 skip=$((GNVS+0x2a3)) count=2 2>/dev/null | od -An -tu2
dd if=/dev/mem bs=1 skip=$((GNVS+0x379)) count=2 2>/dev/null | od -An -tu2
dd if=/dev/mem bs=1 skip=$((GNVS+0x37b)) count=2 2>/dev/null | od -An -tu2
```

结果：

```
MPL0 (Level0 min) = 10000 mW
MPL1 (Level1 min) =  7000 mW
MPL2 (Level2 min) = 10000 mW
PLCS=0  PLVL=4500 mW
```

`MPL0=10000` 与观察到的 10 W 上限一致。DPTF 策略把“最低功耗”设为 10 W，EC 执行。

## 4. 排除项（走过的弯路）

| 尝试 | 结果 | 结论 |
|---|---|---|
| `wrmsr 0x610` 写 PL1/PL2 | PL2 LOCK=1，写入无效 | 必须先解 BIOS 锁 |
| MMIO RAPL 覆盖 | 实际仍 10 W | 不是 MMIO 层 |
| 停 `thermald` | 仍 10.00 W | 不是 Linux 热管理 |
| governor / EPP / `hwp_dynamic_boost` | 无变化 | 不是调频策略 |
| undervolting | `OC_LOCK` 阻止 | 不做 |
| `OemDptfVariable` MPL0 10→20 W | 变量持久化，GNVS `MPL0` 仍 10000，功耗仍 10 W；已恢复原文件 | 不是这个变量 |
| BIOS 菜单找选项 | `Advanced` 下没有可用的 MSR Lock / cTDP / PL1/PL2 | 隐藏，走 UEFI Shell |

## 5. 结论

10 W 是 **两层叠加**：

1. **BIOS Setup** 把 `MSR 0x610` 设成 PL1 25 W / PL2 44 W，但 **PL2 锁定**；需要通过 `Setup:0x551=0` 解锁，让 BIOS 使用 **20 W 自定义档**。
2. **DPTF/EC** 通过 `IETM.P589` → `EC0.REPL` → `EC88(0xB5,0xCA/0xCB)` 独立压到 **10 W**；需要 `SEPL(0)` 把 EC 的 PL1/PL2 写成 `0xFF`。

两步都完成后，实测：

- 持续 **20 W / 2.79 GHz / 87 °C**；
- PL2 爆发 **36–39 W / 3.4–3.5 GHz / 97–100 °C**；
- 25 W 会 100 °C 热节流并回落到 20 W，**不推荐**。

下一步：[BIOS Setup 操作](02-bios-setup.md) → [EC 解锁](03-ec-unlock.md)。
