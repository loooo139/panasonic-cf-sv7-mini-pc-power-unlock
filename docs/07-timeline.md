# 07 · 调试时间线

> 2026-10-19，本地时间（CST）。只记录技术动作，不含主机名/IP/凭据。

| 时间 | 动作 | 结果 |
|---|---|---|
| 18:xx | Ubuntu 24.04 SSH 服务器就绪；关闭合盖休眠/电源键关机 | 24/7 可远程 |
| 19:xx | 8 线程负载测量 | ~9.96 W / ~2.0 GHz / 54–60 °C |
| 19:xx | 读 `MSR 0x610` / `0x64B` / `0x64F` | PL1 25 W / PL2 44 W，PL2 LOCK=1；cTDP 0 |
| 19:xx | RAPL MSR/MMIO、governor/EPP、`hwp_dynamic_boost` | 均不改变 10 W |
| 19:xx | 停 `thermald` | 仍 10.00 W |
| 19:xx | 尝试 RAPL MSR 写入 / MMIO 覆盖 | PL2 锁定/无效 |
| 19:xx | 尝试 undervolting | `OC_LOCK` 阻止 |
| 20:04 | 备份 `OemDptfVariable`；修改 MPL0 10→20 W | 变量持久化，GNVS `MPL0` 仍 10000，功耗仍 10 W；恢复原文件 |
| 20:29 | `flashrom -p internal --ifd -i bios -r` 只读备份 | 成功，16 MB；整片读取在 0x3000 失败 |
| 20:33 | 准备 UEFI Shell + `setup_var.efi` | `Shell.efi`、`setup_var.efi` 放到 ESP |
| 20:34 | 写 `startup.nsh` / `apply_min.nsh` / `apply_full.nsh` / `revert.nsh` | 准备就绪 |
| 20:42 | 第一次 Shell 探测 | 未执行 `startup.nsh`；Shell 空闲后被看门狗关机 |
| 20:47 | 改为自动执行 + 自动重启；脚本放到 `\EFI\tools\` | 仍需要确认 `Setup` 变量 ID |
| 20:51 | 用 `Setup(1)` 写入 `0x551=0` 等 | **MSR 解锁**：`0x610=0x0043816000dd80a0`（PL1 20 W / PL2 44 W / LOCK=0） |
| 20:51 | 负载复测 | 实际仍 ~9.97 W；说明还有 EC 限制 |
| 20:53 | 反编译 `DptfTabl`/SSDT1，找到 `IETM.P589` → `EC0.REPL` → `EC88(0xB5,0xCA/0xCB)` | 确认 EC 独立限功率 |
| 20:56 | 安装 `acpi-call-dkms` | `/proc/acpi/call` 可用 |
| 20:57 | 调用 `\_SB.PCI0.LPCB.EC0.SEPL 0` | **成功**：PL2 爆发 39.5 W / 3.52 GHz / 97 °C；持续 19.86 W / 2.79 GHz / 76–87 °C |
| 20:59 | 创建 `dptf-ec-unlock.service` + 15 秒定时器 | 自动执行 |
| 21:00 | 测试 PL1=25 W | 100 °C 热节流，固件把 PL1 降到 10–12 W，再恢复 20 W |
| 21:01 | 60 秒负载 + MSR 轮询 | 确认动态热保护；稳态 20 W / 2.79 GHz / 87 °C |
| 21:03 | 测试 PL2=35 W | 仍 100 °C 尖峰；无明显收益 |
| 21:04 | 定时器改为 5 分钟；加 S3 恢复钩子 | 减少不必要的 EC 写入 |
| 21:06 | 重启验证 | 服务开机 6 秒自动执行；MSR 解锁；功耗 20 W 档 |
| 21:08 | 创建本地 Git 仓库、整理文档/脚本/UEFI | 隐私扫描通过 |
| 21:xx | `stress-ng matrixprod` A/B（10 W vs 20 W，8 线程 15 秒） | 2911.5 → 4073.6 bogo ops/s（+39.9%） |

## 关键结论

- **10 W 是两层限制**：BIOS MSR 锁 + EC/DPTF 独立限功率。
- **BIOS `0x551=0`** 解锁 MSR，让 BIOS 使用 20 W/44 W 自定义档。
- **`SEPL(0)`** 解除 EC 的 10 W；CPU RAPL 接管。
- **20 W 是散热上限**；25 W 会 100 °C 热节流，不推荐。
- **PL2=44 W** 保留，短时爆发有益；持续由 PL1=20 W 限制。
- **持久化**：开机一次 + 5 分钟安全定时器 + S3 恢复钩子。
