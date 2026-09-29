#!/usr/bin/env bash
# 安装：把 CLI 链接到 ~/.local/bin，配置装到 ~/.config/omarchy-cfg-backup（不覆盖已有）
set -euo pipefail

PROJ=$(cd "$(dirname "$0")" && pwd)
BIN="$HOME/.local/bin/omarchy-cfg-backup"
CFG="$HOME/.config/omarchy-cfg-backup"

mkdir -p "$HOME/.local/bin" "$CFG"
ln -sf "$PROJ/bin/omarchy-cfg-backup" "$BIN"
echo "✔ $BIN → $PROJ/bin/omarchy-cfg-backup"

for f in include.txt vault-include.txt config; do
  src="$PROJ/config/$f"
  [ "$f" = config ] && src="$PROJ/config/config.example"
  if [ -e "$CFG/$f" ]; then
    echo "· 已存在，跳过: $CFG/$f"
  else
    cp "$src" "$CFG/$f"
    echo "✔ 安装: $CFG/$f"
  fi
done
chmod 600 "$CFG/config" 2>/dev/null || true

# 状态栏组件（Omarchy shell 插件）
# 部署布局与 manifest.json 的 entryPoints 一致（widget/CfgBackup.qml），
# 与 `omarchy plugin add` 克隆整仓的布局等价，两条安装通道互通。
PLUGIN_DIR="$HOME/.config/omarchy/plugins/ocb.status"
rm -rf "$PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR/widget"
cp "$PROJ/manifest.json" "$PLUGIN_DIR/"
cp "$PROJ/widget/CfgBackup.qml" "$PLUGIN_DIR/widget/"
echo "✔ 状态栏组件: $PLUGIN_DIR"

# systemd user 单元（自动同步 timer；开关由面板/omarchy-cfg-backup auto-sync 控制）
UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"
cp "$PROJ/systemd/omarchy-cfg-backup.service" "$PROJ/systemd/omarchy-cfg-backup.timer" "$UNIT_DIR/"
systemctl --user daemon-reload >/dev/null 2>&1 || true
echo "✔ systemd 单元: $UNIT_DIR/omarchy-cfg-backup.{service,timer}"

echo
echo "下一步:"
echo "  1. omarchy-cfg-backup doctor"
echo "  2. 装 rclone（pacman -S rclone）并配置 R2 远端后，把 config 里 BACKEND 保持 rclone"
echo "  3. omarchy-cfg-backup push --dry-run 先看打包结果"
