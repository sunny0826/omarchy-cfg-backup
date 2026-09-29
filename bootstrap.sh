#!/usr/bin/env bash
# omarchy-cfg-backup 一键安装（无需 git）
#
#   curl -fsSL https://omarchy-backup.guoxudong.io | bash
#   curl -fsSL https://omarchy-backup.guoxudong.io | bash -s -- --no-setup
#   OCB_VERSION=v1.2.3 curl -fsSL ... | bash     # 固定版本（默认 main）
#
# 幂等：重复执行=升级/修复。密钥只写本地 600 文件，不经终端输出。
set -euo pipefail

REPO="sunny0826/omarchy-cfg-backup"
VERSION="${OCB_VERSION:-main}"
APP_ROOT="$HOME/.local/share/omarchy-cfg-backup"
APP_DIR="$APP_ROOT/app"

say() { printf '✔ %s\n' "$*"; }
step() { printf '· %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

NO_SETUP=0
for a in "$@"; do
  case "$a" in
    --no-setup) NO_SETUP=1 ;;
    --version=*) VERSION="${a#--version=}" ;;
    *) die "未知参数: $a（支持 --no-setup / --version=x.y.z）" ;;
  esac
done

command -v curl >/dev/null || die "需要 curl"
command -v tar >/dev/null || die "需要 tar"

step "下载 omarchy-cfg-backup（版本: $VERSION）"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$VERSION" -o "$tmp/src.tar.gz" \
  || die "下载失败（检查网络，或 OCB_VERSION 指定的版本是否存在）"

step "安装到 $APP_DIR"
mkdir -p "$APP_ROOT"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
tar -xzf "$tmp/src.tar.gz" -C "$APP_DIR" --strip-components=1
[ -f "$APP_DIR/install.sh" ] || die "包内容异常：缺少 install.sh"

bash "$APP_DIR/install.sh"

if [ "$NO_SETUP" != 1 ]; then
  echo
  step "运行配置向导（setup：自动开通 R2、生成密钥、首次备份）"
  if { : < /dev/tty; } 2>/dev/null; then
    omarchy-cfg-backup setup < /dev/tty || die "setup 未完成（可稍后运行 omarchy-cfg-backup setup 重试）"
  else
    omarchy-cfg-backup setup --auto < /dev/null || die "setup 未完成（可稍后运行 omarchy-cfg-backup setup 重试）"
  fi
else
  step "跳过 setup（--no-setup）。之后运行: omarchy-cfg-backup setup"
fi

echo
say "安装完成！"
note() { printf '    %s\n' "$*"; }
note "日常: omarchy-cfg-backup push（备份） / pull（恢复，先 dry-run）"
note "状态栏: 云朵图标左键开面板 · 右键立即同步"
note "升级: 重新执行本命令即可（幂等）"
