# 02 · BIOS Setup：用 UEFI Shell 解锁 MSR

> 目标：把 `Setup:0x551`（Package Power Limit MSR Lock）设为 **0**，并让 BIOS 使用 **20 W / 44 W** 的自定义档。  
> 本机 BIOS 菜单里没有暴露这些选项，所以走 UEFI Shell + `setup_var.efi`。

## 1. 前提

- **Secure Boot 必须关闭**：`Shell.efi` 和 `setup_var.efi` 未签名。
  ```bash
  mokutil --sb-state
  # SecureBoot disabled
  ```
- 已做 **BIOS 只读备份**：
  ```bash
  sudo flashrom -p internal --ifd -i bios -r /path/to/our_bios_backup.bin
  ```
- 知道 ESP 的设备/分区（`lsblk` / `efibootmgr -v`）。

## 2. 准备工具

需要两个文件：

| 文件 | 来源 |
|---|---|
| `Shell.efi` | EDK2 UEFI Shell（Ubuntu 的 `efi-shell-x64` 包，或 EDK2 构建） |
| `setup_var.efi` | <https://github.com/datasone/setup_var.efi/releases>（本机用 0.3.1） |

复制到 ESP：

```bash
sudo mkdir -p /boot/efi/EFI/tools
sudo cp Shell.efi setup_var.efi /boot/efi/EFI/tools/
```

确认：

```bash
ls -l /boot/efi/EFI/tools/
```

## 3. 添加 UEFI 启动项

先看当前启动项：

```bash
sudo efibootmgr
```

添加（设备/分区按实际情况改；示例为 `/dev/nvme0n1` 的第 1 个分区）：

```bash
sudo efibootmgr -c -d /dev/nvme0n1 -p 1 \
  -L "UEFI Shell (DPTF)" \
  -l '\EFI\tools\Shell.efi'
```

输出会给出新的 `BootXXXX`（例如 `Boot0003`）。设置下一次启动：

```bash
sudo efibootmgr -n 0003
sudo efibootmgr | grep -E 'BootNext|UEFI Shell'
```

> `BootNext` 是**一次性**的；进入 BIOS 再退出可能会被清掉。如果没进 Shell，重新设置 `-n` 并直接重启。

## 4. `startup.nsh`

把脚本放到 **两个位置**（Shell 的工作目录可能是 ESP 根目录，也可能是 `\EFI\tools\`）：

```bash
sudo cp uefi/startup.nsh /boot/efi/startup.nsh
sudo cp uefi/startup.nsh /boot/efi/EFI/tools/startup.nsh
```

`uefi/startup.nsh`：

```bat
@echo -off
echo ============================================
echo  Applying DPTF unlock (Setup(1))...
echo ============================================
\EFI\tools\setup_var.efi -r Setup(1):0x551=0 Setup(1):0x565=2 Setup(1):0x566=0 Setup(1):0x603=1 Setup(1):0x604=1
echo.
echo Write failed. Rebooting...
stall 3000000
reset
```

- `-r`：写入成功后**自动重启**。
- `stall 3000000`：失败时等 3 秒再 `reset`，避免停在 Shell 被空闲看门狗关机。
- 使用绝对路径 `\EFI\tools\setup_var.efi`，不依赖当前目录。

## 5. 为什么是 `Setup(1)`，不是 `Setup`

`setup_var.efi` 会把**同名变量**按 GUID 排序，然后要求用 `变量名(ID)` 区分。本机有两个 `Setup`：

| ID | 大小 | GUID | 说明 |
|---|---|---|---|
| `Setup(0)` | 11 字节 | `80E1202E-2697-4264-9CC9-80762C3E5863` | 小变量，写 `0x551` 会 `OffsetOverflow` |
| **`Setup(1)`** | **`0x11CA`** | **`EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9`** | **BIOS Setup 主 varstore** |

如果直接写 `Setup:0x551`，工具会报“Multiple variables with same name detected”，并列出 ID。

### 5.1 探测

在 Shell 里：

```
\EFI\tools\setup_var.efi Setup:0x551
```

如果报多变量，再试：

```
\EFI\tools\setup_var.efi Setup(0):0x551
\EFI\tools\setup_var.efi Setup(1):0x551
```

- 能读到值、且不报 `OffsetOverflow` 的，就是主变量。
- 本机确认是 `Setup(1)`。

## 6. 执行

1. 设置 `BootNext` 后重启。
2. 屏幕会出现 UEFI Shell（黑底白字），自动执行 `startup.nsh`，写入并自动重启。
3. 如果脚本没找到，Shell 会停在 `Shell>`；**不要让它空闲**，否则 EC/BIOS 看门狗会关机。手动执行：
   ```
   fs0:
   \EFI\tools\startup.nsh
   ```
   或直接：
   ```
   \EFI\tools\setup_var.efi -r Setup(1):0x551=0
   ```

## 7. 验证

回到 Ubuntu 后：

```bash
sudo rdmsr 0x610
# 期望: 43816000dd80a0
```

解码：

```
PL1 = 0x0a0 = 20 W
PL2 = 0x160 = 44 W
bit31 = 0 (PL1 未锁)
bit63 = 0 (PL2 未锁)
```

如果仍是 `0x8042816000dd80c0/0x...c8`（PL2 LOCK=1），说明 BIOS 写入没生效：

- 检查 `Setup(1)` 是否正确；
- 检查 Secure Boot 是否关闭；
- 检查 `startup.nsh` 是否被执行；
- 检查 `efibootmgr` 的路径；
- 重新设置 `BootNext`。

**注意：** 此时 EC 仍然把功耗压在 10 W。`MSR 0x610` 显示 20 W 不等于实际 20 W，必须继续做 [EC 解锁](03-ec-unlock.md)。

## 8. 偏移说明（本机 IFR）

| Offset | 名称 | 原厂 | 本机解锁值 | 本机是否生效 |
|---|---|---|---|---|
| `0x551` | Package Power Limit MSR Lock | 1 | **0** | ✅ 是（关键） |
| `0x565` | Configurable TDP Boot Mode | 0 | 2 | ❌ 否（`MSR 0x64B` 仍 0） |
| `0x566` | Configurable TDP Lock | 0 | 0 | — |
| `0x53C` | PL1 Override | 0 | 1（full） | 未单独验证 |
| `0x552` | Platform PL1 Enable | 0 | 1（full） | 未单独验证 |
| `0x553(4)` | Platform PL1 (mW) | — | 20000（full） | 未单独验证 |
| `0x557` | PL1 Time Window | — | 28（full） | 未单独验证 |
| `0x558` | Platform PL2 Enable | 0 | 1（full） | 未单独验证 |
| `0x559(4)` | Platform PL2 (mW) | — | 30000（full） | 未单独验证 |
| `0x603` | EC Turbo Control Mode | 0 | 1 | 未验证 |
| `0x604` | AC Brick Capacity | 1/2 | 1（90 W） | 未验证 |

> 诚实记录：`0x565`（cTDP Up）在本机没有改变 `MSR 0x64B`。这些偏移可能位于其他 varstore，或本机固件不接受。**真正起决定作用的是 `0x551=0`。**

## 9. 恢复

在 Shell 里运行：

```
\EFI\tools\setup_var.efi -r Setup(1):0x551=1 Setup(1):0x565=0 Setup(1):0x566=0 Setup(1):0x603=0 Setup(1):0x604=1
```

或使用 `uefi/revert.nsh`。

> `0x604=1` 是沿用早期脚本的假设（90 W）。如果你的原厂值是 `2`（65 W），改成 `2`。不确定时，至少恢复 `0x551=1`，重新锁上 MSR。

## 10. 风险

- 写错 varstore/偏移可能改变无关的 BIOS 设置。
- `setup_var.efi` 直接写 NVRAM，没有厂商校验。
- 断电/重启过程中写入可能造成 NVRAM 不一致。
- 请确保 BIOS 备份可用；必要时用外部编程器恢复。

下一步：[EC/DPTF 解锁](03-ec-unlock.md)。
