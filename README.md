<h1><img src="Sources/AgentBar/Resources/AgentBarLogo.png" alt="AgentBar logo" width="64" height="64" align="middle"> AgentBar</h1>

[![release](https://img.shields.io/github/v/release/terrytan95/AgentBar?style=flat-square&label=release&labelColor=555555&color=111111)](https://github.com/terrytan95/AgentBar/releases/latest)
![macOS](https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&labelColor=555555)
[![brew](https://img.shields.io/badge/brew-terrytan95%2Ftap%2Fagentbar-ff6b2b?style=flat-square&labelColor=555555)](https://github.com/terrytan95/homebrew-tap)

A native macOS menu bar companion for Codex, Claude Code, and Grok usage, quotas, accounts, tasks, and local audits.

原生 macOS 菜单栏工具，用于查看 Codex、Claude Code 与 Grok 的用量、额度、账户、任务及本地审计数据。

[English](#english) · [简体中文](#zh-cn) · [Install / 安装](#install--安装) · [Build / 构建](#build-from-source--从源码构建)

## Screenshots / 截图

<table>
  <tr>
    <th width="50%">简体中文</th>
    <th width="50%">English</th>
  </tr>
  <tr>
    <td colspan="2" align="center"><strong>Overview / 概览</strong></td>
  </tr>
  <tr>
    <td><img src="screenshots/overview-zh.png" alt="AgentBar 中文概览"></td>
    <td><img src="screenshots/overview-en.png" alt="AgentBar overview in English"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><strong>Settings / 设置</strong></td>
  </tr>
  <tr>
    <td><img src="screenshots/settings-zh.png" alt="AgentBar 中文设置"></td>
    <td><img src="screenshots/settings-en.png" alt="AgentBar settings in English"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><strong>Weekly quota / 每周额度</strong></td>
  </tr>
  <tr>
    <td><img src="screenshots/weekly-quota-zh.png" alt="AgentBar 中文每周额度详情"></td>
    <td><img src="screenshots/weekly-quota-en.png" alt="AgentBar weekly quota details in English"></td>
  </tr>
</table>

<a id="english"></a>

## English

AgentBar turns the usage data already available on your Mac into a compact menu bar view and a detailed dashboard. Codex supplies account and quota data, Claude Code supplies local session usage, and an existing Grok CLI login supplies subscription quota and billing details.

### Highlights

- **Menu bar at a glance:** show the active account's 5-hour and weekly windows, the lowest remaining quota, total tokens, or Codex-only remaining quota. The popover is vertically resizable.
- **Codex accounts:** view, sort, switch, add, remove, and recover local accounts. Optional automatic rotation switches away from a low-quota account while avoiding a Codex restart during active CLI work.
- **CLIProxyAPI auth reuse:** optionally reuse valid Codex access and ID tokens from an existing CLIProxyAPI installation for quota monitoring and account switching, avoiding another browser login while those tokens remain valid.
- **Quota visibility:** track 5-hour and weekly windows, reset times, reset credits, quota pressure, capacity history, and access-token expiry.
- **Grok subscription usage:** use the existing Grok CLI login to show the plan, included-credit usage, reset timing, prepaid balance, and on-demand spend. No xAI Management API key or team ID is required.
- **Codex sidebar widget:** attach a quota card to the Codex sidebar or use it as an independent floating panel. See the active quota window's remaining percentage, progress, exact reset time and countdown, reset credits, and access-token expiry at a glance. The widget supports edge snapping, resizing, and a configurable global shortcut.
- **Usage dashboard:** inspect tokens, estimated cost, complete service/model breakdowns, and ranked high-usage views for sessions, projects, dates, and models. Choose 1-9 ranking rows in Settings, and compare activity across today, yesterday, this week, this month, this year, rolling 7/30 days, all time, or a custom range.
- **Live Task Center:** follow working, waiting, completed, and interrupted Codex tasks with repository, elapsed time, and token totals.
- **Projects and budgets:** group usage by repository, review model and cost trends, and set daily or weekly token/cost budgets globally or per project.
- **Local audit:** review threads and tasks by model, reasoning effort, time to first token, duration, throughput, token breakdown, and estimated cost. Export aggregate CSV or JSON reports.
- **Notifications:** opt in to quota-reset, task-completion, and Codex access-token expiry notifications.
- **Native preferences:** English and Simplified Chinese, system or dark appearance, launch at login, configurable refresh intervals, and built-in verified updates from GitHub Releases.

### Data sources and privacy

AgentBar has no separate analytics backend. Network access is limited to the ChatGPT usage endpoints for configured Codex accounts, the same Grok CLI proxy endpoints used by the official CLI for subscription usage, and GitHub for update checks and downloads.

- `~/.codex/sessions/**/*.jsonl` supplies local usage, task, model, token, and performance records. Source session files are not modified.
- `~/.claude/projects/**/*.jsonl` supplies Claude Code model, token, project, and estimated-cost records. Prompts, replies, tool output, and credentials are not extracted or retained.
- `~/.grok/auth.json` supplies the existing Grok CLI OAuth session used to request subscription quota and plan settings. AgentBar does not log or persist the token contents.
- `~/.codex/accounts/registry.json`, `~/.codex/auth.json`, and per-account auth snapshots supply account identity, quota state, authentication health, and credential expiry. Token contents are used only when required for quota sync or account actions and are not retained in AgentBar reports.
- With explicit opt-in, AgentBar scans CLIProxyAPI Codex credentials during quota refresh and uses valid access tokens in place. When switching accounts, it can write a short-lived access and ID token lease to Codex's own `~/.codex/auth.json`; CLIProxyAPI auth files stay read-only and refresh tokens are never copied. Select the account again after the lease expires.
- Quota refresh and account-management actions can update Codex's local registry and auth snapshots. Parsed session metrics are cached under `~/Library/Caches/AgentBar/` for faster refreshes.
- Audit exports contain aggregate metrics and derived thread labels, not full prompts, replies, or tool output.
- Claude subscription quota and billing totals are not exposed by local session files; AgentBar reports local tokens and price-table estimates instead.
- Grok subscription retrieval depends on the private protocol used by the official Grok CLI. If that upstream protocol changes, AgentBar marks the source unavailable without affecting Codex or Claude data.

### Requirements

- macOS 14 Sonoma or later
- A local Codex installation and login for Codex account/quota features
- An existing CLIProxyAPI installation with valid Codex auth files for optional auth reuse
- The official Grok CLI installed and signed in with `grok login` for Grok subscription usage (optional)
- Accessibility permission only when attaching the quota widget to the Codex window; independent floating mode does not require it

### Getting started

1. Sign in to Codex with `codex login` if needed.
2. Sign in with `grok login` if you want Grok subscription usage.
3. Install and open AgentBar.
4. Click the menu bar item to review accounts and quota windows.
5. Open **Settings** to choose a language, display mode, refresh interval, notifications, budgets, dashboard ranking length, or the Codex sidebar widget. If you use CLIProxyAPI, enable **Reuse CLIProxyAPI auth** under **Account behavior**; leave its directory blank for automatic discovery.

<a id="zh-cn"></a>

## 简体中文

AgentBar 将 Mac 上已有的用量数据整理为简洁的菜单栏视图和完整仪表盘。Codex 提供账户与额度数据，Claude Code 提供本机会话用量，已有的 Grok CLI 登录则提供订阅额度与账单信息。

### 主要功能

- **菜单栏概览：** 可显示当前账户的 5 小时与每周额度、最低剩余额度、Token 总量，或仅显示 Codex 剩余额度；弹窗支持垂直调整大小。
- **Codex 多账户：** 查看、排序、切换、添加、移除和恢复本地账户。可选的自动轮换会在当前账户额度偏低时切换账户，并在 CLI 任务运行期间避免重启 Codex。
- **CLIProxyAPI 授权复用：** 可选择复用现有 CLIProxyAPI 安装中的有效 Codex 访问令牌和 ID 令牌来监控额度并切换账号；令牌有效期间无需再次通过浏览器登录。
- **额度追踪：** 查看 5 小时与每周额度窗口、重置时间、重置额度、额度压力、容量历史，以及访问令牌到期时间。
- **Grok 订阅用量：** 使用已有的 Grok CLI 登录，查看套餐、包含额度用量、重置时间、预付余额和按量付费消耗；无需配置 xAI Management API Key 或 Team ID。
- **Codex 侧边栏小组件：** 将额度卡片附加到 Codex 侧边栏，或作为独立悬浮面板使用；可一眼查看当前额度窗口的剩余百分比、进度、准确重置时间与倒计时、重置额度，以及访问令牌到期时间，并支持贴边、调整大小和自定义全局快捷键。
- **用量仪表盘：** 查看 Token、预估费用、完整的服务与模型分布，以及按会话、项目、日期和模型排列的高消耗榜单；可在设置中选择显示 1-9 条排名，并支持今天、昨天、本周、本月、本年、近 7/30 天、全部和自定义日期范围。
- **实时任务中心：** 跟踪工作中、等待中、已完成和已中断的 Codex 任务，并查看仓库、耗时与 Token 总量。
- **项目与预算：** 按仓库汇总用量，查看模型和费用趋势，并设置全局或单项目的每日/每周 Token 与费用预算。
- **本地审计：** 按线程和任务查看模型、推理强度、首 Token 延迟、耗时、吞吐量、Token 明细和预估费用；支持导出聚合后的 CSV 或 JSON 报告。
- **通知：** 可选择开启额度重置、任务完成和 Codex 访问令牌到期通知。
- **原生设置：** 支持英文与简体中文、跟随系统或深色外观、登录时启动、自定义刷新间隔，以及来自 GitHub Releases 的内置校验更新。

### 数据来源与隐私

AgentBar 没有独立的分析后端。网络访问仅用于通过已配置的 Codex 账户请求 ChatGPT 用量接口、通过 Grok 官方 CLI 使用的代理接口读取订阅用量，以及通过 GitHub 检查和下载更新。

- `~/.codex/sessions/**/*.jsonl` 提供本地用量、任务、模型、Token 与性能记录；AgentBar 不会修改这些会话源文件。
- `~/.claude/projects/**/*.jsonl` 提供 Claude Code 的模型、Token、项目与预估费用记录；AgentBar 不提取或保留 prompt、回复、工具输出与凭证。
- `~/.grok/auth.json` 提供已有的 Grok CLI OAuth 会话，用于请求订阅额度和套餐设置；AgentBar 不会记录或持久化其中的 Token 内容。
- `~/.codex/accounts/registry.json`、`~/.codex/auth.json` 和各账户的认证快照用于识别账户、读取额度状态、认证健康状态与凭证到期时间。Token 内容只在同步额度或执行账户操作时使用，不会写入 AgentBar 报告。
- 明确启用后，AgentBar 会在刷新额度时扫描 CLIProxyAPI 的 Codex 凭证，并直接使用仍然有效的访问令牌。切换账号时，AgentBar 可向 Codex 自己的 `~/.codex/auth.json` 写入短期的访问令牌与 ID 令牌租约；CLIProxyAPI 授权文件始终保持只读，且绝不复制刷新令牌。租约到期后重新选择该账号即可。
- 额度刷新和账户管理操作可能更新 Codex 的本地注册表与认证快照。解析后的会话指标会缓存在 `~/Library/Caches/AgentBar/`，用于加快后续刷新。
- 审计导出仅包含聚合指标和派生的线程标题，不包含完整 prompt、回复或工具输出。
- Claude 订阅额度与账单总额不会写入本机会话文件；AgentBar 仅展示本地 Token 和按内置价格表计算的预估费用。
- Grok 订阅数据依赖官方 Grok CLI 使用的私有协议；如果上游协议发生变化，AgentBar 会将该数据源标记为不可用，不会影响 Codex 或 Claude 数据。

### 系统要求

- macOS 14 Sonoma 或更高版本
- 如需使用 Codex 账户与额度功能，需要已在本机安装并登录 Codex
- 如需选择性复用授权，需要已有 CLIProxyAPI 安装及有效的 Codex 授权文件
- 如需查看 Grok 订阅用量，需要安装官方 Grok CLI 并运行 `grok login` 登录（可选）
- 只有将额度小组件附加到 Codex 窗口时才需要“辅助功能”权限；独立悬浮模式不需要

### 快速开始

1. 如尚未登录，运行 `codex login`。
2. 如需查看 Grok 订阅用量，运行 `grok login`。
3. 安装并打开 AgentBar。
4. 点击菜单栏图标，查看账户与额度窗口。
5. 打开**设置**，调整语言、显示模式、刷新间隔、通知、预算、榜单条数或 Codex 侧边栏小组件。如使用 CLIProxyAPI，请在**账户行为**中启用**复用 CLIProxyAPI 授权**；目录留空即可自动发现。

## Install / 安装

### Homebrew (recommended / 推荐)

```bash
brew install --cask terrytan95/tap/agentbar
```

Upgrade later with / 后续升级：

```bash
brew upgrade --cask agentbar
```

### Manual download / 手动下载

Download the latest archive from [GitHub Releases](https://github.com/terrytan95/AgentBar/releases/latest), unzip it, and move `AgentBar.app` to `/Applications`.

从 [GitHub Releases](https://github.com/terrytan95/AgentBar/releases/latest) 下载最新压缩包，解压后将 `AgentBar.app` 移至 `/Applications`。

## Build from source / 从源码构建

Requirements: Xcode Command Line Tools with Swift 6.1 or later.

需要安装包含 Swift 6.1 或更高版本的 Xcode Command Line Tools。

```bash
git clone https://github.com/terrytan95/AgentBar.git
cd AgentBar
swift test
./script/build_and_run.sh --verify
```

The verified development app is staged under the system temporary directory. To create `dist/AgentBar.app`, use `./script/build_and_run.sh --package`; packaging requires a stable code-signing identity unless explicitly enabled for a throwaway local build.

验证后的开发版 App 会生成在系统临时目录。若要创建 `dist/AgentBar.app`，请运行 `./script/build_and_run.sh --package`；除非明确启用仅供临时使用的本地构建，否则打包需要稳定的代码签名身份。

## Feedback / 反馈

Found a bug or have a focused feature request? Open a [GitHub Issue](https://github.com/terrytan95/AgentBar/issues).

如果发现问题或有明确的功能建议，请提交 [GitHub Issue](https://github.com/terrytan95/AgentBar/issues)。
