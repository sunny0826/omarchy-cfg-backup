# omarchy-cfg-backup

Omarchy 配置与密钥的**单向加密备份** CLI：打包白名单 → zstd →（age）→ rclone crypt → Cloudflare R2。
恢复永远是人工确认的动作，机器不自作主张。


## 特性

- **两仓两管线**：普通配置（A 类）与密钥保险库（B 类）分开、分开密码、分开限权 Token
- **白名单 + fail-safe 排除**：`monitors.lua`、`*.bak*`、缓存永不进包、永不被恢复
- **不可变快照**：时间戳对象 + `latest` + `MANIFEST.json`（逐文件 sha256 + 插件清单）
- **vault scan**：三层信号（名称/权限/内容特征）自动发现应加密的文件，人工确认后入库
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

**唯一需要人做的两件事**：浏览器里授权一次 Cloudflare；把生成的凭据清单录入密码管理器。
其余全部自动。`setup --dry-run` 可先看计划；`setup --auto` 跳过交互提问。

日常使用只有两条命令：改完配置 `omarchy-cfg-backup push`，出问题 `omarchy-cfg-backup pull`（dry-run 预览）。
状态栏云朵图标：左键开面板，右键立即同步。

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
```

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

`widget/` 目录是 Omarchy 状态栏组件（Quickshell 插件），`install.sh` 会自动部署到
`~/.config/omarchy/plugins/ocb.status/` 并保持同步。

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
tests/test.sh      # 全部在临时目录进行，不触碰真实家目录与云端
```

覆盖：打包排除断言（monitors/bak 不进包）、MANIFEST 与插件清单、dry-run、按 id 恢复、
覆盖保护（pre-restore）、status 差异、verify、轮转、vault 全链路与 600 权限。

## 安全须知

- `rclone.conf` 同时含 R2 key 与 crypt 密码——务必 `chmod 600`，且 crypt 密码另存密码管理器 + 离线副本
- vault 启用 `VAULT_USE_AGE=1` 后多一道独立口令保护；age 私钥（`AGE_IDENTITY`）同样需要异地保管
- 各类 agent 的 OAuth 登录态会轮转：换机后重新登录是**预期行为**，不是恢复失败
- `vault scan` 是发现工具不是裁决工具：B 类清单必须人工过目
