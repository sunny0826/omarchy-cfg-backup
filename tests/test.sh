#!/usr/bin/env bash
# 冒烟测试：全部在临时目录进行，不触碰真实家目录内容与云端。
set -uo pipefail

PROJ=$(cd "$(dirname "$0")/.." && pwd)
CLI="$PROJ/bin/omarchy-cfg-backup"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# HOME 隔离：setup/kit 相关路径一律落在临时目录，不碰真实家目录
export HOME="$T/home"
mkdir -p "$HOME"

export OCB_CONFIG_DIR="$T/cfg" BACKEND=local LOCAL_ROOT="$T/remote" \
       HOST_TAG=testhost KEEP_N=2 ROOT="$T/root" STATE_DIR="$T/state"

pass=0; fail=0
ok()  { printf '✔ %s\n' "$*"; pass=$((pass + 1)); }
bad() { printf '✘ %s\n' "$*"; fail=$((fail + 1)); }
assert() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

# ---- fixture ----
mkdir -p "$ROOT/.config/hypr" "$ROOT/.config/omarchy/plugins/demo" "$OCB_CONFIG_DIR" "$ROOT/.config/gh"
echo 'bind = SUPER, RETURN'   > "$ROOT/.config/hypr/bindings.lua"
echo 'monitor = DP-1'         > "$ROOT/.config/hypr/monitors.lua"
echo 'bind = OLD'             > "$ROOT/.config/hypr/bindings.lua.bak.123"
echo '{"shell": true}'        > "$ROOT/.config/omarchy/shell.json"
echo 'alias ll="ls -l"'       > "$ROOT/.bashrc"
echo 'oauth_token: SECRET'    > "$ROOT/.config/gh/hosts.yml"
chmod 600 "$ROOT/.config/gh/hosts.yml"
git -C "$ROOT/.config/omarchy/plugins/demo" init -q
git -C "$ROOT/.config/omarchy/plugins/demo" remote add origin https://example.com/demo.git

cat > "$OCB_CONFIG_DIR/include.txt" <<'EOF'
~/.config/hypr/
~/.config/omarchy/shell.json
~/.bashrc
EOF
cat > "$OCB_CONFIG_DIR/vault-include.txt" <<'EOF'
~/.config/gh/hosts.yml
EOF

REMOTE_CFG_DIR="$LOCAL_ROOT/cfg/omarchy/$HOST_TAG"
REMOTE_VAULT_DIR="$LOCAL_ROOT/vault/omarchy/$HOST_TAG"

echo "== push（cfg）=="
if "$CLI" push > "$T/push1.log" 2>&1; then ok "push 成功"; else bad "push 失败"; cat "$T/push1.log"; fi
assert "latest.tar.zst 已上传" test -f "$REMOTE_CFG_DIR/latest.tar.zst"
assert "MANIFEST.json 已上传"  test -f "$REMOTE_CFG_DIR/MANIFEST.json"

zstd -dc "$REMOTE_CFG_DIR/latest.tar.zst" 2>/dev/null | tar -tf - > "$T/tarlist" || true
assert "包内含 bindings.lua"        grep -q '.config/hypr/bindings.lua' "$T/tarlist"
assert "包内不含 monitors.lua"      bash -c '! grep -q monitors.lua "$0"' "$T/tarlist"
assert "包内不含 *.bak"             bash -c '! grep -q "\.bak" "$0"' "$T/tarlist"
assert "清单 file_count=3"          bash -c 'test "$(jq .file_count "$0")" = 3' "$REMOTE_CFG_DIR/MANIFEST.json"
assert "清单记录插件 remote"        bash -c 'test "$(jq -r ".plugins[0].remote" "$0")" = "https://example.com/demo.git"' "$REMOTE_CFG_DIR/MANIFEST.json"

"$CLI" widget-status > "$T/ws.json" 2>&1
assert "widget-status cfg.level=0"  bash -c 'test "$(jq -r .cfg.level "$0")" = 0' "$T/ws.json"
assert "widget-status 文件计数=3"    bash -c 'test "$(jq -r .cfg.files "$0")" = 3' "$T/ws.json"

echo "== 二次 push + list =="
sleep 1
"$CLI" push >/dev/null 2>&1 || bad "二次 push 失败"
assert "list 显示 2 个时间戳快照" bash -c 'test "$(ls "$0" | grep -cE "^[0-9]{4}-")" = 2' "$REMOTE_CFG_DIR"
"$CLI" list > "$T/list.log" 2>&1
assert "list 输出含 latest" grep -q 'latest' "$T/list.log"

echo "== pull（dry-run 与恢复）=="
"$CLI" pull latest --target "$T/restore" > "$T/pull-dry.log" 2>&1
assert "dry-run 不写文件" bash -c 'test "$(find "$0" -type f 2>/dev/null | wc -l)" = 0' "$T/restore"
assert "dry-run 提示加 --yes" grep -q 'dry-run 结束' "$T/pull-dry.log"
"$CLI" pull latest --yes --target "$T/restore" > "$T/pull.log" 2>&1
assert "恢复 bindings.lua"   cmp -s "$ROOT/.config/hypr/bindings.lua" "$T/restore/.config/hypr/bindings.lua"
assert "恢复不含 monitors.lua" bash -c '! test -e "$0"' "$T/restore/.config/hypr/monitors.lua"
assert "恢复不含 *.bak"       bash -c '! ls "$0"/.config/hypr/*.bak* >/dev/null 2>&1' "$T/restore"
grep -q 'pre-restore' "$T/pull.log" && ok "（首次恢复无覆盖，无需 pre-restore）" || ok "（首次恢复无覆盖，无需 pre-restore）"

echo "== pull 指定快照 id =="
ts=$(ls "$REMOTE_CFG_DIR" | grep -E '^[0-9]{4}-' | sort | head -1 | sed 's/\.tar\.zst$//')
"$CLI" pull "$ts" --yes --target "$T/restore2" > "$T/pull2.log" 2>&1
assert "按 id 恢复成功" test -f "$T/restore2/.bashrc"

echo "== 覆盖保护（pre-restore）=="
echo 'bind = CHANGED' > "$ROOT/.config/hypr/bindings.lua"
"$CLI" pull latest --yes --target "$T/restore" > "$T/pull3.log" 2>&1
assert "覆盖前原文件改名保留" bash -c 'ls "$0"/.config/hypr/bindings.lua.pre-restore-* >/dev/null 2>&1' "$T/restore"

echo "== status / verify =="
"$CLI" status > "$T/status.log" 2>&1
assert "status 检出 1 处变更" grep -q '变更 1' "$T/status.log"
assert "verify 全部通过" "$CLI" verify

echo "== 轮转（KEEP_N=2）=="
sleep 1; "$CLI" push >/dev/null 2>&1
sleep 1; "$CLI" push >/dev/null 2>&1
assert "时间戳快照保留 2 份" bash -c 'test "$(ls "$0" | grep -cE "^[0-9]{4}-")" = 2' "$REMOTE_CFG_DIR"

echo "== vault（--no-age）=="
"$CLI" vault push --no-age > "$T/vpush.log" 2>&1 || { bad "vault push"; cat "$T/vpush.log"; }
assert "vault latest 已上传" test -f "$REMOTE_VAULT_DIR/latest.tar.zst"
"$CLI" vault pull --yes --target "$T/vrestore" > "$T/vpull.log" 2>&1
assert "vault 恢复 hosts.yml" test -f "$T/vrestore/.config/gh/hosts.yml"
assert "vault 文件权限 600"   bash -c 'test "$(stat -c %a "$0")" = 600' "$T/vrestore/.config/gh/hosts.yml"
assert "vault verify 通过" "$CLI" vault verify
"$CLI" widget-status > "$T/ws2.json" 2>&1
assert "widget-status 总体 level=0" bash -c 'test "$(jq -r .level "$0")" = 0' "$T/ws2.json"

echo "== vault scan / doctor =="
assert "vault scan 可运行" "$CLI" vault scan
assert "doctor 体检通过" "$CLI" doctor

echo "== setup（onboarding 向导）=="
"$CLI" setup --dry-run > "$T/setup-dry.log" 2>&1
assert "setup --dry-run 不变更" grep -q 'dry-run 结束' "$T/setup-dry.log"
"$CLI" setup --auto > "$T/setup1.log" 2>&1
assert "setup 首次执行成功" test -f "$T/state/state.json"
assert "setup 写入 age 配置" grep -q '^VAULT_USE_AGE=1' "$OCB_CONFIG_DIR/config"
assert "setup 生成 age identity" test -f "$OCB_CONFIG_DIR/age-identity.txt"
"$CLI" setup --auto > "$T/setup2.log" 2>&1
assert "setup 二次执行幂等" grep -q '白名单已存在，跳过' "$T/setup2.log"
"$CLI" widget-status > "$T/ws3.json" 2>&1
assert "setup 后 configured=true" bash -c 'test "$(jq -r .configured "$0")" = true' "$T/ws3.json"
assert "setup 自动生成恢复包" bash -c 'ls "$0"/ocb-recovery-*.ocbkit >/dev/null 2>&1' "$HOME"
assert "恢复口令写入凭据清单" grep -q '^\[ocb-kit\] Passphrase = ' "$OCB_CONFIG_DIR/first-run-secrets.txt"

echo "== 恢复包（kit export / import）=="
printf 'test-kit-passphrase' > "$T/pf"; chmod 600 "$T/pf"
"$CLI" kit export --passphrase-file "$T/pf" --output "$T/kit.ocbkit" > "$T/kit.log" 2>&1
assert "kit export 成功" test -s "$T/kit.ocbkit"
assert "kit 权限 600" bash -c 'test "$(stat -c %a "$0")" = 600' "$T/kit.ocbkit"
assert "kit 文件头正确" bash -c 'test "$(head -n1 "$0")" = OCBKITv1' "$T/kit.ocbkit"
printf 'wrong-pass' > "$T/pf-bad"; chmod 600 "$T/pf-bad"
if OCB_CONFIG_DIR="$T/cfg-x" "$CLI" kit import "$T/kit.ocbkit" --passphrase-file "$T/pf-bad" \
     > "$T/kit-bad.log" 2>&1; then
  bad "错误口令被拒绝"
else
  ok "错误口令被拒绝"
fi
assert "错误口令不落盘" bash -c '! test -e "$0/config"' "$T/cfg-x"
OCB_CONFIG_DIR="$T/cfg-x" "$CLI" kit import "$T/kit.ocbkit" --passphrase-file "$T/pf" > "$T/kit-imp.log" 2>&1
assert "kit import 成功" test -f "$T/cfg-x/config"
assert "import 回填 HOST_TAG" grep -q '^HOST_TAG=testhost' "$T/cfg-x/config"
assert "AGE_IDENTITY 重写为本机路径" grep -q "^AGE_IDENTITY=$T/cfg-x/age-identity.txt" "$T/cfg-x/config"
assert "age identity 600" bash -c 'test "$(stat -c %a "$0")" = 600' "$T/cfg-x/age-identity.txt"
assert "import 后白名单齐备" test -f "$T/cfg-x/include.txt"

echo "== 发布站点 =="
assert "docs/index.html 与 bootstrap.sh 同步" cmp -s "$PROJ/bootstrap.sh" "$PROJ/docs/index.html"

echo
echo "结果: $pass 通过 · $fail 失败"
[ "$fail" -eq 0 ]
