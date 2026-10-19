# 04 · 验证

> 验证的目标不是“MSR 显示多少”，而是 **8 线程持续负载下的实际封装功耗**。

## 1. 安装工具

```bash
sudo apt-get install -y msr-tools linux-tools-common linux-tools-generic
```

`turbostat` 可能需要匹配内核版本的包：

```bash
sudo apt-get install -y "linux-tools-$(uname -r)"
```

## 2. 看 MSR

```bash
sudo rdmsr 0x610
```

期望：

```
43816000dd80a0
```

解码：

```
PL1 = 0x0a0 = 20 W
PL2 = 0x160 = 44 W
bit31 = 0  (PL1 未锁)
bit63 = 0  (PL2 未锁)
```

解码脚本：

```bash
V=$(sudo rdmsr 0x610)
python3 - "$V" <<'PY'
import sys
v = int(sys.argv[1], 16)
print(f"PL1 = {(v & 0x7fff)/8:.2f} W, lock={(v>>31)&1}")
print(f"PL2 = {((v>>32)&0x7fff)/8:.2f} W, lock={(v>>63)&1}")
PY
```

### 1.1 常见值对照

| `0x610` | 含义 | 说明 |
|---|---|---|
| `0x8042816000dd80c8` | PL1 25 W / PL2 44 W，PL2 LOCK=1 | 原厂 |
| `0x0043816000dd80a0` | PL1 20 W / PL2 44 W，LOCK=0 | 解锁后 |
| `0x0043811800dd80a0` | PL1 20 W / PL2 35 W | 测试过，未采用 |
| `0x0043816000dd80c8` | PL1 25 W / PL2 44 W，LOCK=0 | 25 W 测试；会热节流 |
| `0x...dd8060` | PL1 12 W | 100 °C 时的动态热保护，不是永久值 |

## 3. 运行验证脚本

```bash
sudo ./scripts/verify_power.sh
```

脚本会：

1. 打印 `MSR 0x610` 和 RAPL 限制；
2. 启动 8 个 `sha256sum /dev/zero`；
3. **先等 10 秒**，避开 PL2 爆发的误导；
4. 用 `turbostat` 每 2 秒采样 10 次。

期望输出（节选）：

```
=== MSR 0x610 (PKG_POWER_LIMIT) ===
0x610 = 43816000dd80a0
  PL1 = 20.00 W, lock=0
  PL2 = 44.00 W, lock=0

=== 8-thread load: 10 s warm-up, then 10 samples (2 s) ===
CPU  Bzy_MHz  CoreTmp  PkgTmp  PkgWatt  CorWatt
-    2786     87       87      19.90    19.11
0    2786     87       87      19.90    19.11
...
```

### 3.1 怎么读

- `PkgWatt`：整个 CPU 封装功耗（核心 + 核显 + uncore）。
- `CorWatt`：核心部分功耗。
- `Bzy_MHz`：实际运行频率。
- `PkgTmp` / `CoreTmp`：封装/核心温度。
- **前几秒 36–39 W 是 PL2 爆发，正常。**
- **10 秒后仍 20 W / 2.79 GHz / 87 °C 才是稳态。**

如果脚本只采样前 4 秒（旧版），会看到 36.85 W / 100 °C，容易误判为“过热”。**不要用前 4 秒判断持续性能。**

## 4. 手动验证

```bash
# 启动 8 线程负载
for i in $(seq 8); do (timeout 60 sha256sum /dev/zero >/dev/null 2>&1) & done

# 等 10 秒
sleep 10

# 采样
turbostat --quiet -i 2 -n 10 --show Package,CPU,Bzy_MHz,PkgWatt,CorWatt,PkgTmp,CoreTmp

wait
```

同时轮询 MSR，观察动态热保护：

```bash
for i in $(seq 20); do
  echo "$(date +%T) $(sudo rdmsr 0x610)"
  sleep 2
done
```

你会看到：

- 开始时 PL1 可能从 20 W 缓慢降到 19.75 / 19 / 18 / 16 / 12 / 10 W（温度到 100 °C）；
- 温度回落到 87 °C 后，PL1 恢复到 20 W；
- 这不是 EC 的 10 W 上限，而是 **固件的动态热保护**。

## 5. 温度 / 风扇

```bash
# 风扇：1 = max
cat /sys/class/thermal/cooling_device4/cur_state

# 温度
for z in /sys/class/thermal/thermal_zone*; do
  echo "$z: $(cat $z/type) = $(cat $z/temp)"
done
```

本机负载时：

```
thermal_zone10 (x86_pkg_temp) ≈ 87 °C
cooling_device4 (Fan) = 1 (max)
```

TjMax 100 °C；87 °C 稳态有约 13 °C 余量。

## 6. 如果结果不对

| 现象 | 可能原因 | 处理 |
|---|---|---|
| 10 W / 2.0 GHz | `SEPL(0)` 没生效 | 重新调用；检查 `/proc/acpi/call` |
| 10 W / 2.0 GHz | BIOS `0x551` 仍是 1 | 重新跑 UEFI 脚本 |
| 25 W 但很快掉到 10–12 W | 100 °C 动态热保护 | 正常；不要用 25 W |
| 20 W 但只有 2.4 GHz | 温度/功耗策略 | 检查风扇、环境温度 |
| MSR 仍是 `0x8042...` | PL2 仍锁 | BIOS 解锁没生效 |
| `rdmsr: command not found` | 没装 `msr-tools` | `apt-get install msr-tools` |
| `turbostat: command not found` | 没装 `linux-tools` | 安装对应内核版本 |

## 7. 长期观察

24/7 运行建议：

```bash
# 每分钟记录一次温度/频率/功耗（需要 turbostat）
while true; do
  date
  turbostat --quiet -i 1 -n 1 --show PkgWatt,CorWatt,PkgTmp,Bzy_MHz
  sleep 60
done
```

或者用 `sensors` / Prometheus node_exporter 监控。保持环境温度 < 30 °C，定期清理风扇和出风口。
