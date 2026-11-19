# ARTEXX iOS

把 [ARTEXX](https://github.com/imxv/ARTEXX)（AI 自主渗透测试系统，Go + Next.js）完整搬到 iPhone / iPad，
并内置 **319 条渗透技能库** 与 **201,607 条 CVE 知识库**（2023-01 ~ 2026-11，中危及以上），
每条 CVE 都带「针对什么 / 怎么使用 / 怎么实现 / 真实案例」四段式作战指引。

## 产物

| 文件 | 说明 |
| --- | --- |
| `dist/ARTEXX-unsigned.ipa` | 未签名 ipa（约 84 MB），自签后可装 |
| `ios/ARTEXX.xcodeproj` | 可直接用 Xcode 打开的工程 |
| `ios/ARTEXX/Resources/webui/` | **原版前端整站**（370 文件 / 27 条路由，与官方 `web/out` 逐字节一致） |
| `ios/ARTEXX/Resources/cve.sqlite.gz` | 内置 CVE 知识库（解压 395 MB，压缩 78.5 MB） |
| `ios/ARTEXX/Resources/skills.json` | 319 条技能 |
| `ios/ARTEXX/Resources/exploits.json` | ExploitDB 25,095 条 CVE → 公开 EXP 映射 |
| `build-ipa.cmd` | Windows 双击一键：生成工程 → 自检 → 推送 → 云端编译 → 下载 ipa |

## 界面 = 原版前端（不是仿写）

App 启动时在 **127.0.0.1:8787** 起一个内置 HTTP 服务，做两件事：

1. **托管原版 Web UI**：把 `web/out` 整站塞进 ipa，`WKWebView` 从 `http://127.0.0.1:8787/` 加载。
   前端跑在真实 origin 上，`/_next/static/...` 绝对路径、客户端路由、RSC 预取全部天然可用，**一行前端代码都不用改**。
2. **实现 `/api/*`**：`APICompat.swift` 按 `web/src/lib/types.ts` 的字段定义逐条返回，
   数据源换成 App 内的本地库（LocalTaskStore / SkillLibrary / CVEDatabase / LLMClient）。

所以界面和电脑上一模一样，但**不需要电脑**：飞行模式也能开，任务、发现、技能、CVE 全在手机上。

> 首次进入时前端需要登录态，App 会在页面脚本执行前把 token 注入 `localStorage.artex_token`，不会停在登录页。
> 想切回原生 SwiftUI 版本：右上角小手机图标，或改 `UserDefaults` 里的 `artex.useWebUI`。


## 已实现：桌面端全部功能

| 桌面端页面 | iOS 实现 |
| --- | --- |
| 仪表盘（总览 / Token / 活动流） | `DashboardView` + SSE 实时流 |
| 任务（列表 / 详情 / 目标 / 范围 / 覆盖图） | `TaskListView` / `TaskDetailView`（概览·发现·执行·覆盖四 Tab） |
| 发现（漏洞 / 复测 / 状态流转） | `FindingsView` + 复测按钮 |
| 资产（资产图 / 计数 / 增删） | `AssetsView` |
| 工具执行记录 | `CommandsView` |
| 流量录制 | `TrafficView` |
| 工作空间（文件读写） | `WorkspaceView` |
| 对话（人在环路） | `ChatListView` / `ChatDetailView` |
| LLM 配置 / 池状态 | `LLMView` |
| Agent 管理 / 工具开关 / MCP | `AgentsView` / `ToolsView` |
| 拦截审批 | `ApprovalsView` |
| 日志 / 系统配置 | `LogsView` / `SettingsView` |
| **cmd 控制台** | `ConsoleView`（本地 cmd + 远端双模式） |

### 新增 1：技能库（319 条，13 大类）

| 分类 | 条数 | 分类 | 条数 |
| --- | --- | --- | --- |
| 信息收集 | 37 | 中间件 | 25 |
| 后渗透 | 32 | 数据库攻击 | 25 |
| Web深入 | 27 | 认证授权 | 26 |
| 域渗透 | 26 | 注入利用 | 26 |
| 云原生 | 24 | 指纹测绘 | 22 |
| 内网横向 | 20 | Linux提权 | 19 |
| 报告复盘 | 10 | | |

每条技能含：名称、分类、阶段（recon/fingerprint/exploit/report）、说明、可直接执行的命令、依赖工具、标签、联动 CVE。

**组合使用（要点）**：在技能库勾选多条 → 右上角「作战编排」→ 自动按 侦察 → 指纹 → 利用 → 复盘 排序，
产出三种形态：编排清单、作战简报（可喂给 LLM Agent）、可执行脚本（粘贴进控制台或 `playbook` 命令）。
新建任务时也能直接套用编排，会写进任务的 objective 一起下发。

### 新增 2：CVE 知识库（201,607 条）

- 覆盖 **2023-01-01 → 2026-11-19**，CVSS ≥ 4.0 全部收录
- 分级：critical 25,544 / high 85,188 / medium 90,875
- 每条含：CVSS 分数与向量、CWE、厂商、影响版本区间、参考链接、FTS5 全文索引
- **四段式指引**（逐条预生成，离线可用）：
  1. **针对什么** — 类型、厂商/产品、影响版本、CVSS 向量、是否有公开 EXP
  2. **怎么使用** — 利用前提（版本落点、可控入口、带外回连等）
  3. **怎么实现** — 可复制的验证载荷（curl / nuclei / sqlmap / searchsploit…）
  4. **真实案例** — ExploitDB 公开利用的作者、发布日期、平台与描述；无 EXP 时给出厂商公告复现路径
- 与技能库双向联动：技能详情里能看到它对应的 CVE；CVE 详情里能看到配套技能

检索体验：FTS5 前缀匹配（`apache tomcat` → 119 条命中），支持等级筛选、厂商筛选、CVSS 下限滑块。

## 控制台说明（重要）

iOS 沙箱不允许 `fork/exec` 任意二进制（`Process` 在 iOS 上不可用），所以控制台是双模式：

- **本地 cmd**：内置 busybox 风格解释器，支持 `ls/cd/cat/head/tail/wc/grep/mkdir/rm/cp/mv`、
  管道 `|`、重定向 `>`，以及原生实现的 `dig`（DNS）、`port`（TCP 探测）、`banner`（服务指纹）、`curl`（HTTP），
  还有 `cve` / `skill` / `playbook` 三个知识库命令。
- **远端**：命令下发到你自建的 ARTEXX 服务，由服务端执行真实的 nmap / sqlmap / hydra 等，输出经会话回传。

要看真实外部工具的输出，用远端模式；设备离线时本地模式仍可做侦察、查库、生成编排。

## 安装

### 方式一：自签（Sideloadly / AltStore / TrollStore）

1. 下载 `dist/ARTEXX-unsigned.ipa`
2. 用 Sideloadly 拖入，填 Apple ID（免费账号 7 天有效，付费开发者 1 年）
3. 设备信任证书后打开

### 方式二：自己编译（Xcode）

```bash
open ios/ARTEXX.xcodeproj
# 选择 Team，改 Bundle Identifier，连真机 Run
```

### 方式三：GitHub Actions 云端编译（免费）

双击 `build-ipa.cmd` 一条龙（生成工程 → 语法自检 → 提交推送 → 等编译 → 下载 ipa 到 `dist/`），
或手动：仓库已配好 `.github/workflows/build-ipa.yml`，push 即构建，产物在 Actions → Artifacts。

需要签名的 ipa 时，配以下 Secrets 后手动触发并勾选 `signing`：
`BUILD_CERT_P12`（p12 的 base64）、`BUILD_CERT_PASSWORD`、`PROVISION_PROFILE`（mobileprovision 的 base64）、
`TEAM_ID`、`BUNDLE_ID`。

## 首次使用

1. 打开 App → 填服务器地址（如 `http://192.168.1.10:8787`）
2. 服务端首次运行会提示「设置管理员密码」，输入后自动登录
3. 已有密码则直接登录，token 存在本地钥匙串外的 UserDefaults，可在「更多 → 系统配置」里改

## 目录结构

```
ios/ARTEXX/
├── Sources/
│   ├── App/         ArtExxApp.swift · RootView.swift（登录 + 6 Tab 主框架）
│   ├── Core/        APIClient · APIs（全量端点封装）· ActivityStream（SSE）· ShellRunner · Theme
│   ├── Data/        CVEDatabase（SQLite+FTS5）· CVEPlaybook · SkillLibrary · Gzip
│   ├── Models/      Models.swift（全部 DTO，容错解码）
│   └── Features/    Dashboard / Task / TaskDetail / Skill / CVE / Console / More
└── Resources/       skills.json · cve.sqlite.gz · exploits.json
```

## 数据流水线（可复现）

```bash
node scripts/harvest-nvd-range.mjs    # 按 100 天窗口拉 NVD 全量（2023-01 ~ 2026-11）
node scripts/harvest-nvd-detail.mjs   # 补参考链接 / 影响版本 / CVSS 向量
node scripts/build-cve-db.mjs         # 建 sqlite + 厂商/CWE 归类
node scripts/merge-detail.mjs         # 合并详情
node scripts/build-guidance.mjs       # 逐条生成四段式指引 + 重打包 gz
python scripts/verify_assets.py       # 资源完整性校验
```

## 启动卡住？看这里

v1.0.1 起启动流程做了三处加固，**不会再卡在「ARTEXX 启动中」**：

| 修复 | 说明 |
| --- | --- |
| CVE 库后台解压 | 78MB gz → 395MB sqlite 改为后台流式解压（内存恒定 <2MB），不再阻塞主线程 |
| 4 秒看门狗 | 无论探测结果如何，最多 4 秒必放行到登录页 |
| 3 秒探活超时 | `waitsForConnectivity=false` + 3s 硬超时，服务器不可达立刻报错而非挂起 |
| 原子解压 | 先解到 `.tmp`，校验能打开且有数据才替换，坏文件不会残留 |
| 启动页可跳过 | 有「直接进入」按钮，随时可进主界面 |

**如果还是停在启动页**，去「更多 → 自检」看三项状态：

1. **内置知识库** — 显示「就绪 / 201607 条」才正常。若「失败」或「未就绪」，点底部「重新解压知识库」。
2. **连通性** — 显示「可达」才正常。不可达时看诊断日志给的排查清单（服务器是否监听 0.0.0.0、防火墙、同网段）。
3. **Token** — 未登录时显示「未设置」，此时点「强制重新登录」。

最常见的真实原因是**服务器地址填成了 `127.0.0.1`**——手机上的 127.0.0.1 是手机自己，要填电脑的局域网 IP（如 `http://192.168.1.10:8787`），且服务端要用 `-addr :8787` 而不是 `127.0.0.1:8787`。

## 已知边界

- 未签名 ipa 首次安装需要自签工具，免费账号 7 天需重签
- 内置知识库让包体到约 84 MB（CVE 库 78.5 MB + 前端 11 MB），首次启动解压约 2~4 秒
- TLS 指纹、JARM 等需要原生套接字的能力走远端模式
- 原版前端的「对话 / LLM 录制 / 通知投递 / 审批历史」这类必须后端 Agent 参与的页面，本机模式下是空列表（不会报错），
  接上真机服务器地址后才会有真实数据
- 内置服务只监听 `127.0.0.1`，局域网里的其他设备连不进来（安全默认；要开放自己改 `EmbeddedServer.start`）
