# omarchy-cfg-backup

Omarchy 配置与密钥的**单向加密备份** CLI：打包白名单 → zstd →（age）→ rclone crypt → Cloudflare R2。
恢复永远是人工确认的动作，机器不自作主张。


## 特性

- **两仓两管线**：普通配置（A 类）与密钥保险库（B 类）分开、分开密码、分开限权 Token
- **白名单 + fail-safe 排除**：`monitors.lua`、`*.bak*`、缓存永不进包、永不被恢复
- **不可变快照**：时间戳对象 + `latest` + `MANIFEST.json`（逐文件 sha256 + 插件清单）
- **vault scan**：三层信号（名称/权限/内容特征）自动发现应加密的文件，人工确认后入库
- **恢复包**：`kit export` 一个加密文件收走全部凭据（rclone / age 私钥 / 配置），自动托管云端恢复包库
- **一行恢复**：新机器 `curl … | bash -s -- --restore`，授权 → 选包（备份时间/可恢复内容）→ 输口令 → 完成
- **安全恢复**：pull 默认 dry-run 预览；覆盖前原文件改名 `.pre-restore-<时间>`；vault 文件强制 600
- **可验证**：`verify` 定期完整解开核对 sha256，防备份静默腐烂
- **双后端**：`rclone`（上云）/ `local`（本地目录，离线测试全链路）

## 快速开始（开箱即用）

```bash
curl -fsSL https://omarchy-backup.guoxudong.io | bash
```

一条命令完成安装 + 配置向导。选项：`bash -s -- --no-setup` 只装不配；
`OCB_VERSION=v1.0.0` 钉版本（默认 main）。重新执行即升级/修复（幂等）。
手动方式：下载仓库解压后 `./install.sh`，再跑 `omarchy-cfg-backup setup`。

`setup` 向导内容（幂等，可重复执行）：

1. 依赖检查（tar/zstd/jq/openssl/rclone/age）
2. 安装默认白名单（include.txt / vault-include.txt，零配置）
3. 自动开通 Cloudflare：登录（浏览器授权一次）→ 建两个桶 → 建限权 Token → 配 rclone 四远端
4. 自动生成 age 密钥对并启用内层加密
5. 首次备份两仓 + 完整校验
6. 自动生成**恢复包**（换机一行恢复的钥匙）

**唯一需要人做的两件事**：浏览器里授权一次 Cloudflare；保管好恢复口令（恢复包自动托管云端）。
其余全部自动。`setup --dry-run` 可先看计划；`setup --auto` 跳过交互提问。

日常使用只有两条命令：改完配置 `omarchy-cfg-backup push`，出问题 `omarchy-cfg-backup pull`（dry-run 预览）。
换机恢复也是一条命令（见下节）。状态栏云朵图标：左键开面板，右键立即同步。

## 安装（手动分步，可选）

```bash
./install.sh                 # 链接 CLI + 安装配置（不覆盖已有）
omarchy-cfg-backup doctor    # 体检
```

上云前置（一次性）：

```bash
sudo pacman -S rclone age    # age 可选，vault 内层加密用
rclone config                # 建 r2 / r2-vault 远端（S3 + Cloudflare provider，限权 Token）
```

Cloudflare 侧建 bucket / Token 可用新的 `cf` CLI 完成（控制面），
但备份数据面固定走 rclone + S3 API——理由见讲解文档第九部分。

## 快速上手

```bash
omarchy-cfg-backup push --dry-run    # 看会打包什么（不上传）
omarchy-cfg-backup push              # 上传快照 + latest + MANIFEST
omarchy-cfg-backup list              # 云端快照列表
omarchy-cfg-backup status            # 本地 vs 上次快照差异
omarchy-cfg-backup pull              # dry-run 覆盖预览（默认不写文件）
omarchy-cfg-backup pull --yes        # 确认恢复（monitors.lua 永不覆盖）
omarchy-cfg-backup verify            # 下载 latest 完整校验一遍

omarchy-cfg-backup vault scan        # 发现应加密的文件（只读）
omarchy-cfg-backup vault push|pull|verify|status

omarchy-cfg-backup kit export        # 生成加密恢复包并发布云端（新机免携带）
omarchy-cfg-backup kit list          # 查看云端恢复包（备份时间/可恢复内容）
omarchy-cfg-backup restore           # 换机恢复向导（授权 → 选包 → 输口令 → 落盘）
omarchy-cfg-backup undo-restore      # 撤销恢复（dry-run 预览 → --yes 执行）
```

## 换机恢复（新 Omarchy 一行命令 · 免携带）

**老机器**只需正常备份：`kit export`（`setup` 会自动执行）会把加密恢复包
**自动发布到云端恢复包库**（R2 `ocbkits/` 前缀，附明文清单：备份时间/可恢复内容）。

**新机器**一行命令，全程只需两样东西：**浏览器里授权一次 Cloudflare + 恢复口令**：

```bash
curl -fsSL https://omarchy-backup.guoxudong.io | bash -s -- --restore
```

向导流程（除标注外全自动）：

1. 缺失依赖自动安装（pacman；cf CLI 缺失时 npm 自动补装）
2. **自动打开浏览器**完成 Cloudflare 授权
3. 列出云端恢复包——每条展示**备份时间 · 主机 · 可恢复内容**（配置 N 项/密钥 M 项/age）：

   ```
   [1] 2026-09-29T20-40-38+0800 · omarchy · 配置 12 项 · 密钥 3 项 · age:开 · 24KB
       可恢复内容: ~/.config/hypr/  ~/.config/omarchy/shell.json  ~/.bashrc …
   ```

4. **你选择**一个恢复包（编号）
5. 输一次**恢复口令** → 回填 rclone 凭据 / age 私钥 / HOST_TAG → dry-run 预览 → 确认落盘

安全兜底不变：`monitors.lua` 永不覆盖、覆盖前改名 `.pre-restore-*`、vault 强制 600、**绝不 push**。

其他形态：

```bash
omarchy-cfg-backup kit list           # 只看云端恢复包（不下载）
omarchy-cfg-backup restore            # 不装 CLI，直接进云端向导
omarchy-cfg-backup restore <恢复包>    # 离线/兜底：指定本地恢复包
curl … | bash -s -- --restore ~/ocb-recovery-xxx.ocbkit   # 离线一行命令
```

脚本化：`--select N`（选包）、`--yes`（跳过确认）、`--passphrase-file F`（口令）。
恢复包仍可导出到本地（`kit export --output …`），口令丢失即包作废，建议 ≥12 位。

恢复后手动两步：`hyprctl reload`、`omarchy restart shell`；各 agent 登录态
重新登录即可（**预期行为，不是恢复失败**）。

**备份身份二选一**（恢复收尾会问）：老机器停用 → 沿用；与老机器并行共存 →
改用新身份（`--new-identity` 可脚本化），此后 push 走独立前缀。

## 冲突处理（多机同名 / 双写防护）

| 冲突场景 | 防护机制 |
|---|---|
| 两台机器 hostname 相同 | `HOST_TAG` 默认带机器短 ID（`/etc/machine-id` 前 8 位）；老机器（有 state.json）平滑沿用历史身份，升级不换前缀 |
| 异机双写同一备份前缀 | **push 前哨**：比对 latest MANIFEST 的 `machine_id`，不是本机即拦截；确认接管用 `push --force` |
| 恢复机与老机器并行 | restore 收尾身份二选一（沿用 / 新身份） |
| 文件覆盖 | dry-run 预览 + `.pre-restore-*` 改名保留 + `monitors.lua` 防火墙，零丢失 |

旧快照 MANIFEST 无 `machine_id` 字段时不拦截（向后兼容）；自动同步被拦截时会大声失败并留待人工处理，绝不静默混写。

## 撤销恢复（undo-restore）

每次 `restore` / `pull --yes` 都会写**恢复日志**并保存恢复前状态，随时可反悔：

- `~/.local/state/omarchy-cfg-backup/restore-journal-<时间>.json` —— 逐文件动作
  （新增/覆盖）+ 内容指纹 + 备份身份前值
- `pre-restore-<时间>.tar.zst` —— 覆盖前内容整体快照（tar 兜底）
- 目录里的 `.pre-restore-*` —— 逐文件改名留底（原有机制）

```bash
omarchy-cfg-backup undo-restore              # dry-run 预览最近一次恢复的逆操作
omarchy-cfg-backup undo-restore --yes        # 执行撤销
omarchy-cfg-backup undo-restore <id> --yes   # 撤销指定某次恢复
```

撤销 = 删除恢复新增的文件 + 还原被覆盖的文件（`.pre-restore-*` 优先、缺失则 tar 快照兜底）
+ 还原备份身份（HOST_TAG）。安全兜底：**恢复后被你修改过的文件一律跳过**（先比对内容
指纹），撤销本身默认 dry-run，重复撤销会被拒绝。

## 配置

`~/.config/omarchy-cfg-backup/`：

| 文件 | 作用 |
|---|---|
| `config` | 后端/远端/保留份数/age 开关（见 `config/config.example`，权限 600） |
| `include.txt` | A 类白名单（普通配置） |
| `vault-include.txt` | B 类白名单（密钥） |

对象布局：`<remote>:omarchy/<HOST_TAG>/{latest.tar.zst, <时间戳>.tar.zst, MANIFEST.json}`，
保留最近 `KEEP_N` 份时间戳快照，轮转自动清理。

## 状态栏组件（Omarchy shell 插件）

组件即**标准 Omarchy 插件**：`manifest.json` 在仓库根（entryPoint `widget/CfgBackup.qml`），
符合官方 manifest schema（可 `omarchy plugin validate` 校验），带 MIT LICENSE。
两条安装方式产出等价布局：

```bash
# 方式一：随 install.sh 自动部署（curl|bash 默认，CLI + 组件一起装）
./install.sh                                            # → ~/.config/omarchy/plugins/ocb.status/

# 方式二：官方插件通道（只装状态栏组件）
omarchy plugin add https://github.com/sunny0826/omarchy-cfg-backup.git --enable
```

启用与布局：

```bash
omarchy plugin enable ocb.status --before io.github.manateelazycat.tray-bar
omarchy plugin list                    # 确认 enabled
omarchy bar move ocb.status ...    # 调整位置
```

交互与状态：

| 状态 | 图标 | 含义 |
|---|---|---|
| 新鲜 | 云朵（默认色） | 两仓备份 ≤24h |
| 偏旧 | 云朵（主题强调色） | 最老一仓 >24h |
| 过期/无记录 | 叹号（红色） | >72h 或从未备份 |
| 进行中 | 旋转刷新图标 | 正在同步/校验 |

- **左键**：开合面板（打开时自动拉取最新数据）
- **右键**：立即同步两仓（快路径，完成后桌面通知）
- **悬停 tooltip**：两仓新鲜度、文件数、操作提示

面板内容：

| 区块 | 展示 |
|---|---|
| 最近同步 | 两仓各自的相对时间、文件数、绝对时间 |
| 同步统计 | 累计同步次数、最近完整校验结果、云端保留份数 |
| 自动同步 | 每 24 小时 systemd timer 开关 + 下次运行时间 |
| 动作 | 立即同步 / 完整校验 / 查看差异（终端）/ 密钥扫描（终端） |

自动同步（也可命令行操作）：

```bash
omarchy-cfg-backup auto-sync on      # 启用 systemd user timer（每 24 小时）
omarchy-cfg-backup auto-sync off
omarchy-cfg-backup auto-sync status
```

数据源 `omarchy-cfg-backup widget-status`（单行 JSON，无网络）；
`push`/`verify` 后通过 `qs ipc call ocb.status refresh` 即时刷新，兜底 60s 轮询。
- ⚠️ 开发提示：改 QML 后热重载只更新代码，bar 槽位几何不重建——需
  `omarchy restart shell`；根组件必须显式给 `implicitWidth/implicitHeight`，
  否则槽位渲染为 0×0（现象：IPC 通但栏上不可见）

## 测试

```bash
tests/test.sh      # 单元/冒烟（49 项断言）
tests/e2e.sh       # e2e：换机恢复全旅程（55 项断言）
```

全部在临时目录 + 本地模拟 S3（`rclone serve s3`）中进行，不触碰真实家目录与云端。

`tests/test.sh` 覆盖：打包排除断言（monitors/bak 不进包）、MANIFEST 与插件清单、
dry-run、按 id 恢复、覆盖保护（pre-restore）、status 差异、verify、轮转、
vault 全链路与 600 权限、kit export/import 往返、错误口令拒绝、setup 恢复包。

`tests/e2e.sh` 覆盖（与手动测试说再见）：

- **E2E-1** 换机全流程（local 后端 + age vault）：push → kit export → 全新机器
  `restore` → 逐文件一致 / 600 / monitors 防火墙 / pre-restore / HOST_TAG 回填 /
  AGE_IDENTITY 路径重写 / doctor / list
- **E2E-2** 换机全流程（真实 rclone 路径：serve s3 + crypt + age）：凭据链有效性
  （`list`、`vault verify` 全链路）、rclone.conf 合并语义（保留已有远端、无关远端不外泄）
- **E2E-3** bootstrap 一行命令（`--restore`），打包产物全链路（CLI/组件落位 + 恢复）
- **E2E-4** 负面用例：错误口令、篡改包、空云端、非交互未确认——全部必须干净失败、零落盘

## 安全须知

- **恢复包 = 整套钥匙**（rclone 凭据 + age 私钥 + 配置）：云端托管的是口令加密后的密文
  （R2 `ocbkits/`），拿到密文也需恢复口令才能解开；口令单独放密码管理器，丢失即作废，建议 ≥12 位
- `rclone.conf` 同时含 R2 key 与 crypt 密码——务必 `chmod 600`，且 crypt 密码另存密码管理器 + 离线副本
- vault 启用 `VAULT_USE_AGE=1` 后多一道独立口令保护；age 私钥（`AGE_IDENTITY`）同样需要异地保管
- 各类 agent 的 OAuth 登录态会轮转：换机后重新登录是**预期行为**，不是恢复失败
- `vault scan` 是发现工具不是裁决工具：B 类清单必须人工过目
