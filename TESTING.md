# omarchy-cfg-backup 实测方案

> 目标：验证三条承诺 —— **开箱即用**（curl 到首个加密快照 ≤10 分钟）、
> **可恢复**（任意快照可解密落盘，monitors 永不覆盖）、**安全**（密钥零泄露、权限正确）。
> 每个用例标注：环境 / 损害等级 / 预期。损害等级：🟢无损 🟡轻度（可逆） 🔴破坏性（必须先快照）。

## 自动化优先（tests/，回归以此为准）

**核心旅程已全部自动化，不再依赖手动验证**：

```bash
tests/test.sh      # 单元/冒烟 49 项（打包/vault/轮转/kit/恢复包/setup）
tests/e2e.sh       # e2e 55 项（换机恢复三条真实旅程 + 负面用例）
```

- 全部在临时目录 + 本地模拟 S3（`rclone serve s3`）中进行，不触碰真实家目录与云端
- **E2E-1** 换机全流程（local + age vault）：对应 T4.6 核心路径、T4.1、T4.3、T4.4；
  含备份身份二选一（`--new-identity` 落 config）与 `undo-restore` 撤销身份切换
- **E2E-2** 换机全流程（真实 rclone：serve s3 + crypt + age）：对应 T3.1、T3.5/T3.6 主链路
- **E2E-3** bootstrap 一行命令安装 + `--restore` 恢复：对应 T1.2、T1.4；并用官方
  `omarchy plugin validate` 校验仓库根（plugin add 通道）与部署副本
- **E2E-4** 负面用例：错误口令 / 篡改包 / 空云端 / 非交互未确认（对应 T5 思路）
- **E2E-5** 云端恢复包免携带恢复（stub cf + 模拟 R2）：发布 → 明文清单（备份时间/
  可恢复内容）→ 自动 Cloudflare 授权 → 列表 → 选择 → 恢复；含缺 --select 拒绝、
  恢复机双写老机前缀被前哨拦截、`--force` 接管
- test.sh 另覆盖 T2.2、T2.6、T3.2–T3.4、T4.1–T4.2、恢复包（kit export/import）往返、
  HOST_TAG 防撞默认值（新机短 ID / 老机过渡）、push 前哨（含 vault age 路径）、
  undo-restore（tar 兜底还原 / 用户修改跳过 / dry-run / 重复拒绝）

下表保留给**无法自动化的场景**：真机 UI（T6）、破坏性故障注入（T4.5、T5.1/T5.3）、
timer 行为（T7）、全新 VM 的浏览器授权体验（T2.1/T2.5）。

## 测试环境矩阵

| 环境 | 用途 | 准备 |
|---|---|---|
| E1 本机（真实配置+真实 R2） | 功能回归、恢复预览、UI | 现状即用 |
| E2 干净 VM（Omarchy） | 新用户 onboarding 全旅程 | 虚拟机 + 网络 + 浏览器 |
| E3 假 HOME 沙箱 | setup 幂等/坏态修复 | `HOME=/tmp/ocb-e3` |
| E4 故障注入 | 负面用例 | 断网/错密码/撤销 Token |

## T1 · 安装链路（curl | bash）

| # | 用例 | 等级 | 步骤 | 预期 |
|---|---|---|---|---|
| T1.1 | 站点可用性 | 🟢 | `curl -fsSL https://omarchy-backup.guoxudong.io \| bash -n` | 首行 shebang；语法通过 |
| T1.2 | 干净安装 | 🟢(E2/E3) | `curl -fsSL … \| bash -s -- --no-setup` | CLI/白名单/组件/systemd 全部落位 |
| T1.3 | 版本钉定 | 🟢(E3) | `OCB_VERSION=不存在的tag … \| bash`；再试 `OCB_VERSION=main` | 前者非零退出+清晰报错；后者成功 |
| T1.4 | 重复执行幂等 | 🟢(E3) | 同 T1.2 再跑一次 | 无报错；**不产生新 Token** |
| T1.5 | 升级语义 | 🟡(E3) | 改坏 app 目录一个文件后重跑 | 被下载覆盖还原 |

## T2 · setup 向导

| # | 用例 | 等级 | 步骤 | 预期 |
|---|---|---|---|---|
| T2.1 | 全新全自动 | 🟢(E2) | 干净 VM 执行 setup，计时 | 桶/Token/rclone/age/首推全绿；≤10 分钟 |
| T2.2 | 二次执行跳过 | 🟢 | 重跑 setup | 全部"已存在，跳过"（真机已验证，纳入回归） |
| T2.3 | 半坏态修复 | 🟡(E3) | 删掉 rclone 远端后跑 setup | 重建 Token+远端，恢复正常 |
| T2.4 | 缺依赖 | 🟢(E3) | PATH 去掉 age 跑 setup | 报错含安装命令，非零退出 |
| T2.5 | cf 未登录 | 🟢(E2) | 全新 VM 上 setup 到授权步 | 浏览器弹出授权，完成后继续 |
| T2.6 | 凭据交接单 | 🟢 | 查看 first-run-secrets.txt 与恢复包 | 权限 600；凭据清单 + 恢复口令；提示录入密码管理器；恢复包自动生成 |

## T3 · 备份核心（真实 R2）

| # | 用例 | 等级 | 步骤 | 预期 |
|---|---|---|---|---|
| T3.1 | push→list→verify 闭环 | 🟢 | 三连命令 | 快照+latest+MANIFEST；verify 全过 |
| T3.2 | 变更检测 | 🟢 | 临时改一个配置文件 → status | 显示"变更 1"；改回后归零 |
| T3.3 | 轮转 | 🟢 | 快速连推 12 次（或手工塞对象） | 保留 10 份 + latest |
| T3.4 | 排除断言 | 🟢 | 解开 latest 清点 | 无 monitors.lua / *.bak / sandman.json / plugins 源码 |
| T3.5 | vault 双层加解密 | 🟢 | 拉回 vault 包分层解 | age+crypt 正确解开；**错误 age 私钥必须失败** |
| T3.6 | MANIFEST 完整性 | 🟢 | jq 核对 | file_count 一致；plugins URL 正确 |

## T4 · 恢复（先无损后破坏）

| # | 用例 | 等级 | 步骤 | 预期 |
|---|---|---|---|---|
| T4.1 | 恢复到临时目录 | 🟢 | `pull --yes --target /tmp/restore-t` | 与本地逐文件一致 |
| T4.2 | 单文件回滚 | 🟢 | 模拟改坏 → 拉快照 → 只拷回一个文件 | 精确恢复 |
| T4.3 | 覆盖保护 | 🟢 | 对已有目录二次 pull --yes | 生成 `.pre-restore-*` |
| T4.4 | monitors 防火墙 | 🟢 | 手工构造含 monitors.lua 的包 → pull | **永不落盘**（安全过滤计数） |
| T4.5 | 真实目录恢复 | 🔴 | 先 tar 快照家目录 → pull --yes 覆盖真实配置 | 配置生效；pre-restore 齐全 |
| T4.6 | 换机全旅程 | 🟡(E2) | 干净 VM 走旅程 B 全 10 步，计时（核心路径已由 E2E-1/2/3 自动覆盖） | ≤40 分钟到可用；OAuth 重登 ≤3 次 |

## T5 · 故障注入（负面）

| # | 用例 | 等级 | 步骤 | 预期 |
|---|---|---|---|---|
| T5.1 | 断网 push | 🟡 | 断网后 push | 大声失败；远端无残包 |
| T5.2 | crypt 密码错 | 🟡 | 临时改 rclone 远端密码 → pull | 明确报错，本地零写入 |
| T5.3 | Token 失效 | 🟡 | 撤销一个测试 Token → push | 403 有清晰提示 |
| T5.4 | 损坏快照 | 🟡 | 手工截断 latest → verify | 检出并报 sha256/zstd 失败 |
| T5.5 | state.json 损坏 | 🟢 | 写入非法 JSON → widget-status | 输出兜底 JSON，不崩溃 |
| T5.6 | 半上传 | 🟢 | 远端放伪 .partial 对象 | list 忽略/轮转清理，latest 不受影响 |

## T6 · 状态栏 UI

| # | 用例 | 等级 | 步骤 | 预期 |
|---|---|---|---|---|
| T6.1 | 三态图标 | 🟢 | 改 state 时间戳 →24h/72h 边界 | 云朵默认色→强调色→红色叹号（截图） |
| T6.2 | 面板数据 | 🟢 | 面板 vs CLI 输出对照 | 时间/次数/校验完全一致 |
| T6.3 | 交互 | 🟢 | 左键/右键/悬停 | 面板开合 / 快速同步+通知 / tooltip 正确 |
| T6.4 | onboarding 态 | 🟢(E3) | 未配置环境打开面板 | 引导卡 + ▶ 启动 setup |
| T6.5 | 自动同步开关 | 🟢 | 面板 toggle on/off | systemctl timer 联动正确 |
| T6.6 | 打开即刷新 | 🟢 | push 后立刻开面板 | 显示新数据（非缓存） |

## T7 · 自动同步

| # | 用例 | 等级 | 步骤 | 预期 |
|---|---|---|---|---|
| T7.1 | 开关与触发 | 🟢 | `auto-sync on` → `systemctl --user start` 手动触发 | state 更新 + 通知 |
| T7.2 | 错过补跑 | 🟢 | （可选）改 timer 时间验证 Persistent | 开机补执行 |

## 数据安全护栏（红线，全程适用）

1. 恢复类测试先 `--target /tmp/...`；🔴 用例动手前先 tar 快照目标目录
2. 测试凭据一律假值（`fake-secret-*`）；绝不把真实 first-run-secrets 拿来当测试数据
3. 测试产生的 Token 撤销回收（`cf user tokens delete`），结束后 `cf user tokens list` 核对
4. 每轮结束跑 `doctor` + `vault scan` 对比基线，确认无新增泄露面

## 建议执行顺序

- **第零步（每次提交前，自动）**：`tests/test.sh` + `tests/e2e.sh` 全绿
- **第一波（现在，本机，无损）**：T1.1 · T3.* · T4.1–4.4 · T5.5–5.6 · T6.* · T7.1 —— 约 30 分钟
- **第二波（干净 VM）**：T1.2–1.5 · T2.1/T2.5 · T4.6 —— 约 45 分钟，产出《新用户实测报告》
- **第三波（破坏性，护栏下）**：T4.5 · T5.1–5.4 —— 约 20 分钟

## 通过标准

- `tests/test.sh` + `tests/e2e.sh` 全绿 = 回归底线（必须）
- 第一波全绿 = 本机发布就绪
- 第二波全绿 = "开箱即用"承诺成立，可对外宣传
- 第三波全绿 = "可恢复"承诺成立（备份的最终测试是恢复）
