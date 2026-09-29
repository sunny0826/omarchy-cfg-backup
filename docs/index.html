#!/usr/bin/env bash
# omarchy-cfg-backup 一键安装 / 一行恢复（无需 git）
#
# 全新机器安装 + 首次配置:
#   curl -fsSL https://omarchy-backup.guoxudong.io | bash
#
# 全新机器一键恢复（免携带恢复包：浏览器授权 Cloudflare → 选包 → 输口令 → 完成）:
#   curl -fsSL https://omarchy-backup.guoxudong.io | bash -s -- --restore
#
# 全新机器从本地恢复包恢复（离线/兜底）:
#   curl -fsSL https://omarchy-backup.guoxudong.io | bash -s -- --restore ~/ocb-recovery-xxx.ocbkit
#
# 其他用法:
#   ... | bash -s -- --no-setup                  只装不配
#   ... | bash -s -- --restore --yes --select N  非交互恢复（配合 --passphrase-file）
#   ... | bash -s -- --restore KIT --yes         离线恢复并跳过确认
#   OCB_VERSION=v1.2.3 ... | bash                钉版本（默认 main）
#   OCB_TARBALL=/path/src.tar.gz ... | bash      从本地包安装（离线/测试）
#
# 幂等：重复执行=升级/修复。密钥只写本地 600 文件，不经终端输出。
set -euo pipefail

REPO="sunny0826/omarchy-cfg-backup"
VERSION="${OCB_VERSION:-main}"
TARBALL="${OCB_TARBALL:-}"
APP_ROOT="$HOME/.local/share/omarchy-cfg-backup"
APP_DIR="$APP_ROOT/app"

say() { printf '✔ %s\n' "$*"; }
step() { printf '· %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

NO_SETUP=0
RESTORE_MODE=0
RESTORE_KIT=""
RESTORE_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --no-setup) NO_SETUP=1; shift ;;
    --version=*) VERSION="${1#--version=}"; shift ;;
    --restore=*) RESTORE_MODE=1; RESTORE_KIT="${1#--restore=}"; shift ;;
    --restore)
      RESTORE_MODE=1
      if [ $# -ge 2 ] && [[ "$2" != -* ]]; then RESTORE_KIT=$2; shift 2; else shift; fi
      ;;
    --select=*) RESTORE_ARGS+=(--select "${1#--select=}"); shift ;;
    --select) [ $# -ge 2 ] || die "--select 缺参数"; RESTORE_ARGS+=(--select "$2"); shift 2 ;;
    --passphrase-file=*) RESTORE_ARGS+=(--passphrase-file "${1#--passphrase-file=}"); shift ;;
    --passphrase-file) [ $# -ge 2 ] || die "--passphrase-file 缺参数"; RESTORE_ARGS+=(--passphrase-file "$2"); shift 2 ;;
    --yes) RESTORE_ARGS+=(--yes); shift ;;
    *) die "未知参数: $1（支持 --no-setup / --restore [KIT] / --select N / --passphrase-file F / --yes / --version=x.y.z）" ;;
  esac
done

ensure_deps() {
  # 恢复路径的依赖兜底：缺什么装什么（Arch/pacman）
  local missing=() c
  for c in tar zstd jq openssl rclone age; do
    command -v "$c" >/dev/null || missing+=("$c")
  done
  [ "${#missing[@]}" -eq 0 ] && return 0
  step "安装缺失依赖: ${missing[*]}"
  if command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --needed "${missing[@]}" || die "依赖安装失败: ${missing[*]}"
  else
    die "缺少依赖: ${missing[*]}（请手动安装后重试）"
  fi
}

ensure_cf() {
  command -v cf >/dev/null 2>&1 && return 0
  step "安装 Cloudflare CLI（cf，用于浏览器授权发现云端恢复包）"
  if command -v npm >/dev/null 2>&1; then
    npm i -g cf || die "cf 安装失败（可手动: npm i -g cf 后重试）"
  else
    die "需要 Cloudflare CLI（cf）：请先安装 node/npm，再 npm i -g cf"
  fi
}

command -v tar >/dev/null || die "需要 tar"
if [ -z "$TARBALL" ]; then
  command -v curl >/dev/null || die "需要 curl"
fi

if [ "$RESTORE_MODE" = 1 ]; then
  ensure_deps
  [ -n "$RESTORE_KIT" ] || ensure_cf
fi

step "获取 omarchy-cfg-backup（版本: $VERSION）"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if [ -n "$TARBALL" ]; then
  step "使用本地安装包: $TARBALL"
  case "$TARBALL" in
    http://*|https://*) curl -fsSL "$TARBALL" -o "$tmp/src.tar.gz" || die "下载失败: $TARBALL" ;;
    *) cp "$TARBALL" "$tmp/src.tar.gz" || die "读取失败: $TARBALL" ;;
  esac
else
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$VERSION" -o "$tmp/src.tar.gz" \
    || die "下载失败（检查网络，或 OCB_VERSION 指定的版本是否存在）"
fi

step "安装到 $APP_DIR"
mkdir -p "$APP_ROOT"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
tar -xzf "$tmp/src.tar.gz" -C "$APP_DIR" --strip-components=1
[ -f "$APP_DIR/install.sh" ] || die "包内容异常：缺少 install.sh"

bash "$APP_DIR/install.sh"

if [ "$RESTORE_MODE" = 1 ]; then
  echo
  step "一键恢复（只做恢复，绝不 push）"
  if [ -n "$RESTORE_KIT" ]; then
    [ -f "$RESTORE_KIT" ] || die "恢复包不存在: $RESTORE_KIT"
  else
    step "即将打开浏览器进行 Cloudflare 授权（用于发现云端恢复包）"
  fi
  restore_cmd=(omarchy-cfg-backup restore)
  [ -n "$RESTORE_KIT" ] && restore_cmd+=("$RESTORE_KIT")
  restore_cmd+=("${RESTORE_ARGS[@]}")
  if { : < /dev/tty; } 2>/dev/null; then
    "${restore_cmd[@]}" < /dev/tty || die "恢复未完成（可稍后运行 omarchy-cfg-backup restore 重试）"
  else
    "${restore_cmd[@]}" < /dev/null || die "恢复未完成（可稍后运行 omarchy-cfg-backup restore 重试）"
  fi
elif [ "$NO_SETUP" != 1 ]; then
  echo
  step "运行配置向导（setup：自动开通 R2、生成密钥、首次备份、恢复包）"
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
note "换机: 新机器一行命令 --restore 即可（云端恢复包 + 口令，无需携带文件）"
note "状态栏: 云朵图标左键开面板 · 右键立即同步"
note "升级: 重新执行本命令即可（幂等）"
