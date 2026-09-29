#!/usr/bin/env bash
# e2e 测试：换机恢复全旅程自动化（临时目录 + 本地 S3 模拟，不碰真实家目录与云端）
#
#   E2E-1 换机恢复全流程（local 后端 + age vault）
#   E2E-2 换机恢复全流程（真实 rclone 路径: rclone serve s3 + crypt + age）
#   E2E-3 bootstrap 一行命令恢复（curl|bash 等价路径）
#   E2E-4 负面用例（错口令 / 篡改包 / 空云端 / 非交互未确认）
set -uo pipefail

PROJ=$(cd "$(dirname "$0")/.." && pwd)
CLI="$PROJ/bin/omarchy-cfg-backup"
T=$(mktemp -d)
SERVE_PID=""
trap '[ -n "$SERVE_PID" ] && kill "$SERVE_PID" 2>/dev/null; rm -rf "$T"' EXIT

pass=0; fail=0
ok()  { printf '✔ %s\n' "$*"; pass=$((pass + 1)); }
bad() { printf '✘ %s\n' "$*"; fail=$((fail + 1)); }
assert() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
assert_fail() { local d=$1; shift; if "$@" >/dev/null 2>&1; then bad "$d"; else ok "$d"; fi; }

free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

write_fixture() { # home —— 生成机器侧配置文件（含故意存在的 monitors.lua / *.bak 类干扰项）
  local h=$1
  mkdir -p "$h/.config/hypr" "$h/.config/omarchy" "$h/.config/gh"
  echo 'bind = SUPER, RETURN' > "$h/.config/hypr/bindings.lua"
  echo 'monitor = DP-1'       > "$h/.config/hypr/monitors.lua"
  echo '{"shell": true}'      > "$h/.config/omarchy/shell.json"
  echo 'alias ll="ls -l"'     > "$h/.bashrc"
  echo 'oauth_token: FAKE-e2e-secret' > "$h/.config/gh/hosts.yml"
  chmod 600 "$h/.config/gh/hosts.yml"
}

make_age() { # cfgdir → stdout age 公钥
  local cfg=$1
  age-keygen -o "$cfg/age-identity.txt" >/dev/null 2>&1
  chmod 600 "$cfg/age-identity.txt"
  grep -o 'age1[0-9a-z]*' "$cfg/age-identity.txt" | head -1
}

write_includes() { # cfgdir
  cat > "$1/include.txt" <<'EOF'
~/.config/hypr/
~/.config/omarchy/shell.json
~/.bashrc
EOF
  cat > "$1/vault-include.txt" <<'EOF'
~/.config/gh/hosts.yml
EOF
}

echo "== E2E-1 换机恢复全流程（local 后端 + age vault）=="
A_HOME="$T/a-home"; A_CFG="$A_HOME/.config/omarchy-cfg-backup"
B_HOME="$T/b-home"; B_CFG="$B_HOME/.config/omarchy-cfg-backup"
mkdir -p "$A_CFG"
write_fixture "$A_HOME"
write_includes "$A_CFG"
PUB=$(make_age "$A_CFG")
cat > "$A_CFG/config" <<EOF
BACKEND=local
LOCAL_ROOT=$T/cloud
HOST_TAG=oldbox
KEEP_N=5
VAULT_USE_AGE=1
AGE_RECIPIENT=$PUB
AGE_IDENTITY=$A_CFG/age-identity.txt
EOF
chmod 600 "$A_CFG/config"

run_a() { env HOME="$A_HOME" OCB_CONFIG_DIR="$A_CFG" "$CLI" "$@"; }
run_b() { env HOME="$B_HOME" OCB_CONFIG_DIR="$B_CFG" "$CLI" "$@"; }

if run_a push > "$T/a-push.log" 2>&1; then ok "机器A cfg push"; else bad "机器A cfg push"; cat "$T/a-push.log"; fi
if run_a vault push > "$T/a-vpush.log" 2>&1; then ok "机器A vault push（age）"; else bad "机器A vault push"; cat "$T/a-vpush.log"; fi
assert "vault latest.age 已上传" test -f "$T/cloud/vault/omarchy/oldbox/latest.tar.zst.age"
assert "机器A cfg verify" run_a verify
assert "机器A vault verify" run_a vault verify

printf 'e2e-kit-passphrase' > "$T/pf1"; chmod 600 "$T/pf1"
if run_a kit export --passphrase-file "$T/pf1" --output "$T/kit1.ocbkit" > "$T/kit1.log" 2>&1; then
  ok "kit export 成功"
else
  bad "kit export 成功"; cat "$T/kit1.log"
fi
assert "kit 权限 600" bash -c 'test "$(stat -c %a "$0")" = 600' "$T/kit1.ocbkit"
assert "kit 文件头正确" bash -c 'test "$(head -n1 "$0")" = OCBKITv1' "$T/kit1.ocbkit"

# 机器 B：全新机器预置（自己的 monitors.lua + 一份将被覆盖的旧 bindings.lua）
mkdir -p "$B_HOME/.config/hypr"
echo 'bind = OLD-LOCAL' > "$B_HOME/.config/hypr/bindings.lua"
echo 'monitor = DP-B'   > "$B_HOME/.config/hypr/monitors.lua"

if run_b restore "$T/kit1.ocbkit" --passphrase-file "$T/pf1" --yes > "$T/b-restore.log" 2>&1; then
  ok "机器B 一行恢复成功"
else
  bad "机器B 一行恢复成功"; cat "$T/b-restore.log"
fi
assert "恢复输出含完成标记" grep -q '换机恢复完成' "$T/b-restore.log"
assert "恢复 .bashrc 一致" cmp -s "$A_HOME/.bashrc" "$B_HOME/.bashrc"
assert "恢复 shell.json 一致" cmp -s "$A_HOME/.config/omarchy/shell.json" "$B_HOME/.config/omarchy/shell.json"
assert "恢复 bindings.lua 一致" cmp -s "$A_HOME/.config/hypr/bindings.lua" "$B_HOME/.config/hypr/bindings.lua"
assert "monitors.lua 未被覆盖" bash -c 'test "$(cat "$0")" = "monitor = DP-B"' "$B_HOME/.config/hypr/monitors.lua"
assert "覆盖保护 pre-restore 生成" bash -c 'ls "$0"/.config/hypr/bindings.lua.pre-restore-* >/dev/null 2>&1' "$B_HOME"
assert "vault 恢复且 600" bash -c 'test "$(stat -c %a "$0/.config/gh/hosts.yml")" = 600' "$B_HOME"
assert "vault 内容一致" cmp -s "$A_HOME/.config/gh/hosts.yml" "$B_HOME/.config/gh/hosts.yml"
assert "HOST_TAG 已回填" grep -q '^HOST_TAG=oldbox' "$B_CFG/config"
assert "AGE_IDENTITY 重写为本机路径" grep -q "^AGE_IDENTITY=$B_CFG/age-identity.txt" "$B_CFG/config"
assert "age identity 600" bash -c 'test "$(stat -c %a "$0")" = 600' "$B_CFG/age-identity.txt"
assert "机器B doctor 通过" run_b doctor
assert "机器B list 看到快照（凭据/身份正确）" run_b list

echo
echo "== E2E-2 换机恢复（真实 rclone 路径: rclone serve s3 + crypt + age）=="
if ! command -v rclone >/dev/null 2>&1; then
  bad "rclone 未安装，E2E-2 无法执行（请安装 rclone）"
else
  S3_PORT=$(free_port)
  mkdir -p "$T/s3root/omarchy-cfg-backup" "$T/s3root/omarchy-secret-vault"
  rclone serve s3 "$T/s3root" --addr "127.0.0.1:$S3_PORT" --auth-key "testkey,testsecret" \
    --log-level ERROR > "$T/serve.log" 2>&1 &
  SERVE_PID=$!
  port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
  for _ in $(seq 1 50); do
    port_open "$S3_PORT" && break
    sleep 0.1
  done
  assert "S3 模拟服务就绪" port_open "$S3_PORT"

  A2_HOME="$T/a2-home"; A2_CFG="$A2_HOME/.config/omarchy-cfg-backup"
  B2_HOME="$T/b2-home"; B2_CFG="$B2_HOME/.config/omarchy-cfg-backup"
  mkdir -p "$A2_CFG" "$A2_HOME/.config/rclone"
  write_fixture "$A2_HOME"
  write_includes "$A2_CFG"
  PUB2=$(make_age "$A2_CFG")
  cat > "$A2_CFG/config" <<EOF
BACKEND=rclone
REMOTE_CFG=r2-crypt
REMOTE_VAULT=r2-vault-crypt
HOST_TAG=oldbox
KEEP_N=5
VAULT_USE_AGE=1
AGE_RECIPIENT=$PUB2
AGE_IDENTITY=$A2_CFG/age-identity.txt
EOF
  chmod 600 "$A2_CFG/config"
  PWC=$(rclone obscure 'e2e-cfg-pass'); PWC2=$(rclone obscure 'e2e-cfg-pass2')
  PWV=$(rclone obscure 'e2e-vault-pass'); PWV2=$(rclone obscure 'e2e-vault-pass2')
  cat > "$A2_HOME/.config/rclone/rclone.conf" <<EOF
[r2]
type = s3
provider = Other
access_key_id = testkey
secret_access_key = testsecret
endpoint = http://127.0.0.1:$S3_PORT
no_check_bucket = true

[r2-vault]
type = s3
provider = Other
access_key_id = testkey
secret_access_key = testsecret
endpoint = http://127.0.0.1:$S3_PORT
no_check_bucket = true

[r2-crypt]
type = crypt
remote = r2:omarchy-cfg-backup
password = $PWC
password2 = $PWC2

[r2-vault-crypt]
type = crypt
remote = r2-vault:omarchy-secret-vault
password = $PWV
password2 = $PWV2

[other]
type = local
n = /tmp/should-not-travel
EOF
  chmod 600 "$A2_HOME/.config/rclone/rclone.conf"

  run_a2() { env HOME="$A2_HOME" OCB_CONFIG_DIR="$A2_CFG" RCLONE_CONFIG="$A2_HOME/.config/rclone/rclone.conf" "$CLI" "$@"; }
  run_b2() { env HOME="$B2_HOME" OCB_CONFIG_DIR="$B2_CFG" RCLONE_CONFIG="$B2_HOME/.config/rclone/rclone.conf" "$CLI" "$@"; }

  if run_a2 push > "$T/a2-push.log" 2>&1; then ok "机器A2 cfg push（S3+crypt）"; else bad "机器A2 cfg push"; cat "$T/a2-push.log"; fi
  if run_a2 vault push > "$T/a2-vpush.log" 2>&1; then ok "机器A2 vault push（S3+crypt+age）"; else bad "机器A2 vault push"; cat "$T/a2-vpush.log"; fi
  # crypt 会加密目录名，故只断言桶内确有对象，不检查明文路径
  assert "S3 上有加密对象" bash -c 'test "$(find "$0/omarchy-cfg-backup" -type f | wc -l)" -gt 0' "$T/s3root"

  printf 'e2e-kit2-passphrase' > "$T/pf2"; chmod 600 "$T/pf2"
  if run_a2 kit export --passphrase-file "$T/pf2" --output "$T/kit2.ocbkit" > "$T/kit2.log" 2>&1; then
    ok "kit export 成功（含 rclone 凭据）"
  else
    bad "kit export 成功（含 rclone 凭据）"; cat "$T/kit2.log"
  fi

  # 机器 B2：全新 HOME，只带恢复包 + 口令；预置一个无关远端验证合并语义
  mkdir -p "$B2_HOME/.config/rclone"
  cat > "$B2_HOME/.config/rclone/rclone.conf" <<'EOF'
[keepme]
type = local
n = /tmp/keepme
EOF
  chmod 600 "$B2_HOME/.config/rclone/rclone.conf"

  if run_b2 restore "$T/kit2.ocbkit" --passphrase-file "$T/pf2" --yes > "$T/b2-restore.log" 2>&1; then
    ok "机器B2 一行恢复成功（仅凭恢复包+口令）"
  else
    bad "机器B2 一行恢复成功（仅凭恢复包+口令）"; cat "$T/b2-restore.log"
  fi
  assert "恢复输出含完成标记" grep -q '换机恢复完成' "$T/b2-restore.log"
  assert "恢复 .bashrc 一致" cmp -s "$A2_HOME/.bashrc" "$B2_HOME/.bashrc"
  assert "vault 恢复且 600" bash -c 'test "$(stat -c %a "$0/.config/gh/hosts.yml")" = 600' "$B2_HOME"
  assert "rclone.conf 已回填 crypt 远端" grep -q '^\[r2-crypt\]' "$B2_HOME/.config/rclone/rclone.conf"
  assert "rclone.conf 已回填底层远端" grep -q '^\[r2-vault\]' "$B2_HOME/.config/rclone/rclone.conf"
  assert "无关远端不外泄" bash -c '! grep -q "^\[other\]" "$0"' "$B2_HOME/.config/rclone/rclone.conf"
  assert "已有远端 keepme 保留" grep -q '^\[keepme\]' "$B2_HOME/.config/rclone/rclone.conf"
  assert "rclone.conf 权限 600" bash -c 'test "$(stat -c %a "$0")" = 600' "$B2_HOME/.config/rclone/rclone.conf"
  assert "机器B2 list 可用（凭据链有效）" run_b2 list
  assert "机器B2 vault verify 全链路（crypt+age+sha256）" run_b2 vault verify

  kill "$SERVE_PID" 2>/dev/null; SERVE_PID=""
fi

echo
echo "== E2E-3 bootstrap 一行命令恢复 =="
if tar -czf "$T/src.tar.gz" -C "$PROJ" --exclude=.git --exclude=.cloudflare \
     --transform 's,^\.,omarchy-cfg-backup-main,' . 2>/dev/null; then
  ok "源码包构建成功"
else
  bad "源码包构建成功"
fi

C_HOME="$T/c-home"
mkdir -p "$C_HOME"
if env HOME="$C_HOME" OCB_TARBALL="$T/src.tar.gz" PATH="$C_HOME/.local/bin:$PATH" \
     bash "$PROJ/bootstrap.sh" --restore "$T/kit1.ocbkit" --passphrase-file "$T/pf1" --yes \
     > "$T/bootstrap-restore.log" 2>&1; then
  ok "bootstrap --restore 成功"
else
  bad "bootstrap --restore 成功"; tail -20 "$T/bootstrap-restore.log"
fi
assert "bootstrap 恢复输出含完成标记" grep -q '换机恢复完成' "$T/bootstrap-restore.log"
assert "CLI 已安装到 ~/.local/bin" test -x "$C_HOME/.local/bin/omarchy-cfg-backup"
assert "状态栏组件已部署" test -f "$C_HOME/.config/omarchy/plugins/ocb.status/CfgBackup.qml"
assert "bootstrap 恢复 .bashrc 一致" cmp -s "$A_HOME/.bashrc" "$C_HOME/.bashrc"
assert "bootstrap 恢复 vault 600" bash -c 'test "$(stat -c %a "$0/.config/gh/hosts.yml")" = 600' "$C_HOME"

D_HOME="$T/d-home"
mkdir -p "$D_HOME"
if env HOME="$D_HOME" OCB_TARBALL="$T/src.tar.gz" PATH="$D_HOME/.local/bin:$PATH" \
     bash "$PROJ/bootstrap.sh" --no-setup > "$T/bootstrap-install.log" 2>&1; then
  ok "bootstrap --no-setup 安装成功"
else
  bad "bootstrap --no-setup 安装成功"; tail -10 "$T/bootstrap-install.log"
fi
assert "仅安装不配置" test -x "$D_HOME/.local/bin/omarchy-cfg-backup"

echo
echo "== E2E-4 负面用例 =="
printf 'wrong-pass' > "$T/pf-bad"; chmod 600 "$T/pf-bad"
N1_HOME="$T/n1-home"; mkdir -p "$N1_HOME"
assert_fail "错误口令被拒绝" env HOME="$N1_HOME" OCB_CONFIG_DIR="$N1_HOME/.config/omarchy-cfg-backup" \
  "$CLI" kit import "$T/kit1.ocbkit" --passphrase-file "$T/pf-bad"
assert "错误口令不落盘" bash -c '! test -e "$0/config"' "$N1_HOME/.config/omarchy-cfg-backup"

python3 - "$T/kit1.ocbkit" "$T/kit-tampered.ocbkit" <<'PYEOF'
import sys
data = bytearray(open(sys.argv[1], 'rb').read())
data[len(data) // 2] ^= 0xFF
open(sys.argv[2], 'wb').write(bytes(data))
PYEOF
N2_HOME="$T/n2-home"; mkdir -p "$N2_HOME"
assert_fail "篡改包被拒绝" env HOME="$N2_HOME" OCB_CONFIG_DIR="$N2_HOME/.config/omarchy-cfg-backup" \
  "$CLI" kit import "$T/kit-tampered.ocbkit" --passphrase-file "$T/pf1"

# 空云端：口令正确、包正确，但云端没有任何快照
E_HOME="$T/e-home"; E_CFG="$E_HOME/.config/omarchy-cfg-backup"; mkdir -p "$E_CFG"
cat > "$E_CFG/config" <<EOF
BACKEND=local
LOCAL_ROOT=$T/empty-cloud
HOST_TAG=nosnap
KEEP_N=5
VAULT_USE_AGE=0
EOF
chmod 600 "$E_CFG/config"
cat > "$E_CFG/include.txt" <<'EOF'
~/.bashrc
EOF
: > "$E_CFG/vault-include.txt"
printf 'empty-kit-passphrase' > "$T/pf3"; chmod 600 "$T/pf3"
if env HOME="$E_HOME" OCB_CONFIG_DIR="$E_CFG" "$CLI" kit export \
     --passphrase-file "$T/pf3" --output "$T/kit3.ocbkit" >/dev/null 2>&1; then
  ok "空云端 kit export 成功"
else
  bad "空云端 kit export 成功"
fi
N3_HOME="$T/n3-home"; mkdir -p "$N3_HOME"
assert_fail "空云端 restore 失败" env HOME="$N3_HOME" OCB_CONFIG_DIR="$N3_HOME/.config/omarchy-cfg-backup" \
  "$CLI" restore "$T/kit3.ocbkit" --passphrase-file "$T/pf3" --yes
env HOME="$N3_HOME" OCB_CONFIG_DIR="$N3_HOME/.config/omarchy-cfg-backup" \
  "$CLI" restore "$T/kit3.ocbkit" --passphrase-file "$T/pf3" --yes > "$T/n3.log" 2>&1 || true
assert "空云端报错含提示" grep -q '云端没有 cfg 快照' "$T/n3.log"

# 非交互且未加 --yes → 拒绝落盘
N4_HOME="$T/n4-home"; mkdir -p "$N4_HOME"
assert_fail "非交互未确认被拒绝" env HOME="$N4_HOME" OCB_CONFIG_DIR="$N4_HOME/.config/omarchy-cfg-backup" \
  "$CLI" restore "$T/kit1.ocbkit" --passphrase-file "$T/pf1"
assert "拒绝后未写入 .bashrc" bash -c '! test -e "$0/.bashrc"' "$N4_HOME"

echo
echo "e2e 结果: $pass 通过 · $fail 失败"
[ "$fail" -eq 0 ]
