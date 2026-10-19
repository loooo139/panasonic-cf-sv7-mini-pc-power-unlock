#!/usr/bin/env bash
# 准备 UEFI Shell 解锁：复制 startup.nsh、创建/复用启动项、设置 BootNext。
# 不自动重启；由 one-click.sh 或用户决定。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ESP="${ESP:-/boot/efi}"

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行: sudo $0" >&2
  exit 1
fi

echo "=== 检查 Secure Boot ==="
if command -v mokutil >/dev/null 2>&1; then
  if mokutil --sb-state 2>/dev/null | grep -qi 'SecureBoot enabled'; then
    echo "Secure Boot 已开启。请先在 BIOS 中关闭：" >&2
    echo "  Security -> Secure Boot -> Disabled" >&2
    exit 1
  fi
  echo "Secure Boot 未开启（或 mokutil 未报告 enabled）。"
else
  echo "mokutil 未安装；跳过检查。请确认 BIOS 里 Secure Boot 已关闭。"
fi

echo
echo "=== 检查 ESP ==="
if ! mountpoint -q "$ESP"; then
  ESP="$(findmnt -n -o TARGET /boot/efi || true)"
  [ -n "$ESP" ] || { echo "找不到 /boot/efi 挂载点" >&2; exit 1; }
fi
echo "ESP: $ESP"

echo
echo "=== 检查 UEFI 工具 ==="
MISSING=0
for f in Shell.efi setup_var.efi; do
  if [ ! -f "$ESP/EFI/tools/$f" ]; then
    echo "缺少: $ESP/EFI/tools/$f" >&2
    MISSING=1
  fi
done
if [ "$MISSING" -ne 0 ]; then
  echo
  echo "请下载并放到 $ESP/EFI/tools/：" >&2
  echo "  Shell.efi:     EDK2 UEFI Shell（Ubuntu efi-shell-x64 包，或 EDK2 构建）" >&2
  echo "  setup_var.efi: https://github.com/datasone/setup_var.efi/releases" >&2
  echo
  echo "放好后重新运行: sudo $ROOT/one-click.sh" >&2
  exit 1
fi
echo "找到 Shell.efi / setup_var.efi。"

echo
echo "=== 复制 startup.nsh 到两个位置 ==="
install -m 644 "$ROOT/uefi/startup.nsh" "$ESP/startup.nsh"
install -m 644 "$ROOT/uefi/startup.nsh" "$ESP/EFI/tools/startup.nsh"
echo "  $ESP/startup.nsh"
echo "  $ESP/EFI/tools/startup.nsh"

echo
echo "=== 创建/复用启动项 ==="
if ! command -v efibootmgr >/dev/null 2>&1; then
  echo "efibootmgr 未安装；请先: sudo apt-get install -y efibootmgr" >&2
  exit 1
fi

BOOTNUM="$(efibootmgr | awk '/UEFI Shell \(DPTF\)/ {gsub(/^Boot/,"",$1); gsub(/\*$/,"",$1); print $1; exit}')"
if [ -n "$BOOTNUM" ]; then
  echo "  复用现有启动项 Boot$BOOTNUM"
else
  SRC="$(findmnt -n -o SOURCE "$ESP")"
  DISK="$(lsblk -no PKNAME "$SRC" | head -1)"
  PART="$(lsblk -no PARTN "$SRC" | head -1)"
  if [ -z "$DISK" ] || [ -z "$PART" ]; then
    echo "无法从 $SRC 推断磁盘/分区号；请手动创建启动项：" >&2
    echo "  sudo efibootmgr -c -d /dev/nvme0n1 -p 1 -L 'UEFI Shell (DPTF)' -l '\\EFI\\tools\\Shell.efi'" >&2
    exit 1
  fi
  efibootmgr -c -d "/dev/$DISK" -p "$PART" -L "UEFI Shell (DPTF)" -l '\EFI\tools\Shell.efi'
  BOOTNUM="$(efibootmgr | awk '/UEFI Shell \(DPTF\)/ {gsub(/^Boot/,"",$1); gsub(/\*$/,"",$1); print $1; exit}')"
  [ -n "$BOOTNUM" ] || { echo "创建启动项失败" >&2; exit 1; }
  echo "  已创建 Boot$BOOTNUM"
fi

efibootmgr -n "$BOOTNUM"
echo
echo "=== 已设置 BootNext=Boot$BOOTNUM ==="
efibootmgr | grep -E "BootNext|UEFI Shell" || true
echo
echo "现在重启即可："
echo "  sudo reboot"
echo
echo "机器会进入 UEFI Shell，自动执行 startup.nsh，然后自动重启回 Ubuntu。"
echo "如果它停在 Shell> 或自动关机，见 docs/05-recovery.md。"
