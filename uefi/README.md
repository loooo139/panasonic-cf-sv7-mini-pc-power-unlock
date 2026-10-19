# UEFI Shell：BIOS Setup 解锁

本目录的 `.nsh` 脚本用于在 **UEFI Shell** 里通过 `setup_var.efi` 修改 BIOS Setup 变量。  
本机 BIOS 菜单没有暴露 `Package Power Limit MSR Lock` / cTDP / PL1/PL2 选项，所以只能走这条路。

> **先读 [../docs/02-bios-setup.md](../docs/02-bios-setup.md)。** 这里只放脚本和速查。

## 1. 需要的东西

| 文件 | 说明 |
|---|---|
| `Shell.efi` | EDK2 UEFI Shell（Ubuntu `efi-shell-x64` 包，或 EDK2 构建） |
| `setup_var.efi` | <https://github.com/datasone/setup_var.efi/releases>（本机 0.3.1） |

本仓库**不包含**这两个二进制文件。

## 2. 放到 ESP

```bash
sudo mkdir -p /boot/efi/EFI/tools
sudo cp Shell.efi setup_var.efi /boot/efi/EFI/tools/
```

## 3. 添加启动项

```bash
sudo efibootmgr -c -d /dev/nvme0n1 -p 1 \
  -L "UEFI Shell (DPTF)" \
  -l '\EFI\tools\Shell.efi'

# 用上一步输出的 BootXXXX，例如 0003
sudo efibootmgr -n 0003
```

> `BootNext` 是一次性的；如果进 BIOS 再退出，可能会被清掉。重新执行 `efibootmgr -n` 即可。

## 4. 复制 `startup.nsh` 到两个位置

```bash
sudo cp startup.nsh /boot/efi/startup.nsh
sudo cp startup.nsh /boot/efi/EFI/tools/startup.nsh
```

Shell 的工作目录可能是 ESP 根目录，也可能是 `\EFI\tools\`；两处都放，避免找不到。

## 5. 脚本选择

| 脚本 | 用途 |
|---|---|
| `startup.nsh` | 开机自动执行「最小解锁」并重启（推荐） |
| `apply_min.nsh` | 手动执行最小解锁：`0x551=0` + cTDP/EC Turbo/90 W |
| `apply_full.nsh` | 额外写 PL1=20 W / PL2=30 W（本机未单独验证） |
| `revert.nsh` | 恢复原厂值 |

**最小解锁：**

```
\EFI\tools\setup_var.efi -r Setup(1):0x551=0 Setup(1):0x565=2 Setup(1):0x566=0 Setup(1):0x603=1 Setup(1):0x604=1
```

- `-r`：写入成功后自动重启。
- `Setup(1)`：主 Setup 变量（`0x11CA` 字节）。`Setup(0)` 是 11 字节小变量，写 `0x551` 会 `OffsetOverflow`。
- 如果 `Setup(1)` 不适用，先在 Shell 里探测：
  ```
  \EFI\tools\setup_var.efi Setup:0x551
  ```
  按提示选择能读到值的 ID。

## 6. 本机实际效果

- `0x551=0`：**生效**，`MSR 0x610` 变成 `0x0043816000dd80a0`（PL1 20 W / PL2 44 W / LOCK=0）。
- `0x565=2`（cTDP Up）：**未生效**，`MSR 0x64B` 仍为 0。
- `0x603` / `0x604`：未单独验证。
- **决定性的 BIOS 改动是 `0x551=0`**。

## 7. 空闲关机

如果 `startup.nsh` 没被执行，Shell 会停在 `Shell>`。过一会 EC/BIOS 的空闲看门狗会**直接关机**（不是重启）。  
所以：

- 把 `startup.nsh` 放到 Shell 能找到的目录；
- 脚本执行完自动 `reset`；
- 不要长时间停在 `Shell>` 提示符。

## 8. 验证

回到 Linux：

```bash
sudo rdmsr 0x610
# 期望 43816000dd80a0
```

如果还是 `0x8042816000dd80c8`（PL2 LOCK=1），检查 Secure Boot、`Setup(1)`、`startup.nsh` 和 `BootNext`。

## 9. 恢复

```
\EFI\tools\setup_var.efi -r Setup(1):0x551=1 Setup(1):0x565=0 Setup(1):0x566=0 Setup(1):0x603=0 Setup(1):0x604=1
```

或 `revert.nsh`。`0x604=1` 是早期脚本的假设（90 W）；如果你的原厂是 `2`（65 W），改成 `2`。不确定时至少恢复 `0x551=1`。

## 10. 风险

- `setup_var.efi` 直接写 NVRAM，没有厂商校验；
- 写错偏移可能改变无关设置；
- 请先做完整 BIOS 备份；
- 写坏可能需要外部编程器恢复。
