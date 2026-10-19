#!/usr/bin/env bash
# 松下 CF-SV7 小主机一键功耗解锁（小白友好）
#
# 它会：
#   1. 检查/安装依赖（acpi-call-dkms、msr-tools、linux-tools）
#   2. 检查 BIOS 备份
#   3. 安装 EC 解锁服务（SEPL 0 + systemd timer + S3 hook）
#   4. 检查 MSR 0x610：已解锁则直接验证；仍锁定则准备 UEFI Shell 步骤
#
# 用法：
#   sudo ./one-click.sh              # 交互式，不自动重启
#   sudo ./one-click.sh --reboot     # 需要 BIOS 步骤时，准备后自动重启
#   sudo ./one-click.sh --yes        # 跳过“没有备份”确认（谨慎）
#   sudo ./one-click.sh --verify     # 结束后运行 8 线程验证（默认开启）
#   sudo ./one-click.sh --no-verify  # 不运行验证
#   sudo ./one-click.sh --help
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REBOOT=0
ASSUME_YES=0
VERIFY=1

usage() {
  cat <<'EOF'
用法: sudo ./one-click.sh [选项]

  --reboot       如果 BIOS MSR 仍锁定，准备 UEFI Shell 后自动重启
  --yes, -y      跳过“没有找到 BIOS 备份”的确认
  --verify       结束后运行 8 线程验证（默认）
  --no-verify    不运行验证
  --help, -h     显示帮助

说明:
  - 已解锁的机器重复运行是安全的（幂等）。
  - BIOS 步骤需要一次重启；机器会自动进入 UEFI Shell、写入 Setup(1):0x551=0、
    然后自动重启回 Ubuntu。
  - 如果你在远程 SSH，确保能接受重启/短暂离线。
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --reboot) REBOOT=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --verify) VERIFY=1 ;;
    --no-verify) VERIFY=0 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行: sudo $0" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "需要 python3 来解析 MSR；请先安装 python3。" >&2
  exit 1
fi

echo "============================================"
echo " 松下 CF-SV7 小主机一键功耗解锁"
echo "============================================"

# ---------------------------------------------------------------------------
# 1) 依赖
# ---------------------------------------------------------------------------
echo
echo "[1/4] 检查依赖..."
NEED_APT=0
command -v rdmsr >/dev/null 2>&1 || NEED_APT=1
command -v turbostat >/dev/null 2>&1 || NEED_APT=1
[ -e /proc/acpi/call ] || NEED_APT=1

if [ "$NEED_APT" -eq 1 ]; then
  echo "  安装 acpi-call-dkms / msr-tools / linux-tools ..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y acpi-call-dkms msr-tools linux-tools-common linux-tools-generic || true
  # 尝试精确内核版本的 linux-tools
  apt-get install -y "linux-tools-$(uname -r)" 2>/dev/null || true
  modprobe acpi_call 2>/dev/null || true
else
  echo "  依赖已安装。"
fi

if ! command -v rdmsr >/dev/null 2>&1; then
  echo "  ⚠ 仍找不到 rdmsr；请手动安装 msr-tools 后重试。" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2) 备份检查
# ---------------------------------------------------------------------------
echo
echo "[2/4] 检查 BIOS 备份..."
USER_HOME="$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6 || true)"
[ -n "$USER_HOME" ] || USER_HOME="$HOME"

BACKUP="$(find "$USER_HOME" "$ROOT" -maxdepth 2 -name 'our_bios_backup.bin' -print -quit 2>/dev/null || true)"
if [ -n "$BACKUP" ]; then
  echo "  找到备份: $BACKUP"
else
  echo "  ⚠ 没有找到 our_bios_backup.bin。"
  echo "    BIOS 操作有风险；建议先做只读备份："
  echo "      sudo flashrom -p internal --ifd -i bios -r \"\$HOME/our_bios_backup.bin\""
  if [ "$ASSUME_YES" -ne 1 ]; then
    if ! read -r -p "  没有备份也继续？[y/N] " ans; then
      echo "  已取消。"
      exit 1
    fi
    case "$ans" in
      y|Y|yes|YES) ;;
      *) echo "  已取消。"; exit 1 ;;
    esac
  fi
fi

# ---------------------------------------------------------------------------
# 3) EC 解锁 + 持久化
# ---------------------------------------------------------------------------
echo
echo "[3/4] 安装 EC 解锁服务..."
"$ROOT/scripts/install.sh"

# ---------------------------------------------------------------------------
# 4) MSR 检查
# ---------------------------------------------------------------------------
echo
echo "[4/4] 检查 BIOS MSR 锁..."
V="$(rdmsr 0x610 2>/dev/null || true)"
if [ -z "$V" ]; then
  echo "  无法读取 MSR 0x610；请确认 msr-tools 已安装并且以 root 运行。" >&2
  exit 1
fi
echo "  MSR 0x610 = $V"

LOCK="$(python3 - "$V" <<'PY'
import sys
v = int(sys.argv[1], 16)
print(((v >> 31) & 1) | ((v >> 63) & 1))
PY
)"

if [ "$LOCK" -eq 0 ]; then
  echo "  ✅ BIOS MSR 已解锁，无需 UEFI Shell 步骤。"
  if [ "$VERIFY" -eq 1 ]; then
    echo
    echo "运行 8 线程验证（约 35 秒）..."
    "$ROOT/scripts/verify_power.sh" || true
  fi
  echo
  echo "完成。当前应达到 ~20 W 持续 / ~2.79 GHz。"
  echo "如果结果不是 20 W，运行: sudo $ROOT/scripts/verify_power.sh"
  exit 0
fi

echo "  ⚠ BIOS MSR 仍锁定（PL1/PL2 LOCK 位为 1）。"
echo "  需要一次 UEFI Shell 步骤来写入 Setup(1):0x551=0。"
echo "  EC 解锁已经安装；BIOS 步骤完成前，实际功耗可能仍受限制。"

if ! "$ROOT/scripts/setup-uefi.sh"; then
  echo
  echo "  UEFI Shell 准备失败。EC 解锁已经生效，但 BIOS 步骤未完成。"
  echo "  请按上面的提示放置 Shell.efi / setup_var.efi，然后重新运行本脚本。"
  exit 1
fi

if [ "$REBOOT" -eq 1 ]; then
  echo
  echo "  即将重启进入 UEFI Shell。机器会自动执行并重启回 Ubuntu。"
  echo "  重启后重新 SSH 登录，运行: sudo $ROOT/one-click.sh --verify"
  echo "  ⚠ 如果你在远程 SSH，确保能接受短暂离线。"
  sleep 3
  systemctl reboot
else
  echo
  echo "  已准备好。现在重启即可应用："
  echo "      sudo reboot"
  echo
  echo "  机器会进入 UEFI Shell，自动执行 startup.nsh，然后自动重启回 Ubuntu。"
  echo "  重启后运行: sudo $ROOT/one-click.sh --verify"
  echo
  echo "  如果它停在 Shell> 或自动关机，见 docs/05-recovery.md。"
fi
