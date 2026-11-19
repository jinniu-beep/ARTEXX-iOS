# 任务提示词：ARTEXX 前后端整体移植到 iOS（功能/界面/后端与开源一致）

> 把这份文档整段贴给 Claude Code。它自包含，不需要看之前的对话。
> 目标不是"做个像 ARTEXX 的 App"，而是**把 ARTEXX 本身搬到 iPhone 上**。

---

## 0. 铁律（先读这一段，后面所有取舍都按这个判）

1. **界面不许改。** 配色、排版、信息架构、组件、路由、交互流程，与开源项目 `web/out` 保持一致。
   适配 iOS ≠ 重新设计。你只允许改"让它在触摸屏上能用"的适配层，不允许做"移动端改版"。
2. **后端不许改功能。** 253 条 API 路由、请求/响应字段、业务逻辑、Agent 编排、状态机、报告格式，全部保持原样。
3. **不是"兼容层替身"。** 不允许用 Swift 写一堆返回空数据的假接口糊弄页面。要跑**原版 Go 后端的真实代码**。
4. **技能和 CVE 必须内置进 ipa**，离线可查。
5. 只有一处允许、且必须变更：**执行外部命令的那一层**（原因见 §5）。除此之外任何功能缺失都算 bug。

---

## 1. 架构决策（这是本任务的核心，先理解再动手）

原版是 `Go 后端(:8787) + Next.js 前端`。iOS 上的正确做法是：

```
┌─────────────────────────── iPhone App ───────────────────────────┐
│                                                                  │
│  WKWebView  ──http://127.0.0.1:8787──►  Go 后端（原版代码）       │
│  原版前端产物                            编译为 libartex.a        │
│  (web/out, 370 文件)                     c-archive 静态链接       │
│                                                │                 │
│                                                ├─ server/ 253 路由│
│                                                ├─ agent/ 编排引擎 │
│                                                ├─ db/ SQLite      │
│                                                ├─ llmpool/ llmrec/│
│                                                ├─ report/ guard/  │
│                                                └─ exec 层（唯一替换）│
│                                                                  │
│  Swift 壳：启动 Go runtime → 监听 127.0.0.1 → 加载 WebView         │
└──────────────────────────────────────────────────────────────────┘
```

**为什么可行（有先例）**：Go 官方支持 `GOOS=ios GOARCH=arm64 -buildmode=c-archive`，
Tailscale 的 iOS 客户端就是这么做的（完整的 WireGuard + netstack 跑在 Go runtime 上）。
原版 go.mod 里已经有 `modernc.org/sqlite`（纯 Go、无 cgo），说明 SQLite 模式本来就是设计内的。

**所以：不要重写后端。把 Go 代码编译进 App。**

---

## 2. 现状（已完成，别重做）

仓库：`https://github.com/jinniu-beep/ARTEXX-iOS`（本地 `E:\ds\ARTEXX-iOS`）
上游：`https://github.com/imxv/ARTEXX`（本地副本 `E:\ds\_ref\ARTEXX`）

已完成：

| 项 | 状态 |
| --- | --- |
| Xcode 工程 + GitHub Actions 出未签名 ipa | ✅ 84 MB，`dist/ARTEXX-unsigned.ipa` |
| 原版前端整站内置（`ios/ARTEXX/Resources/webui/`，370 文件 / 27 路由） | ✅ 与 `web/out` 逐字节一致 |
| Swift 写的 HTTP 服务（`EmbeddedServer` + `Router` + `StaticFiles`） | ✅ 托管静态文件，但 API 是假的 |
| Swift 版 API 兼容层（`APICompat.swift`，743 行，约 40 条端点） | ⚠️ **本任务要替换掉它** |
| 本地知识库：`skills.json` 319 条、`cve.sqlite.gz` 201,607 条 | ✅ 数据在，但没接进原版后端 |
| SQLite schema 转换（`backend/schema.sqlite.sql`，1294 行） | ✅ 已有，可直接用 |
| Swift 原生页面 + LocalAgent（6 个本地工具） | ✅ 保留，作为降级方案 |

**本次要做的**：把 Swift 假后端换成真 Go 后端。

---

## 3. 阶段 A：Go 后端 iOS 化（最大工作量）

### A1. 编译管线

新增 `ios/build-go.sh`（macOS 上执行）：

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../_ref/ARTEXX"

export CGO_ENABLED=1
export GOOS=ios
export GOARCH=arm64
export GOFLAGS="-tags=ios"
export CGO_CFLAGS="-arch arm64 -miphoneos-version-min=15.0 -isysroot $(xcrun --sdk iphoneos --show-sdk-path)"
export CGO_LDFLAGS="-arch arm64 -miphoneos-version-min=15.0 -isysroot $(xcrun --sdk iphoneos --show-sdk-path)"

go build -buildmode=c-archive -trimpath -ldflags="-s -w" \
  -o ../ios/ARTEXX/Go/libartex.a \
  ./cmd/artex-ios
```

新增入口 `cmd/artex-ios/main.go`（**不调用 `os.Exit`，不自己监听信号**）：

```go
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"unsafe"

	"github.com/Autumn-27/artex/server"
)

var cancel context.CancelFunc

//export ArtexStart
func ArtexStart(port C.int, dataDir *C.char) C.int {
	dir := C.GoString(dataDir)
	ctx, c := context.WithCancel(context.Background())
	cancel = c
	if err := server.RunEmbedded(ctx, int(port), dir); err != nil {
		return -1
	}
	return 0
}

//export ArtexStop
func ArtexStop() { if cancel != nil { cancel() } }

func main() {}
```

要求：
- `server.RunEmbedded` 是新加的薄封装：复用 `server.go` 里已有的 mux 构建逻辑，把监听地址固定成 `127.0.0.1:port`，**不要复制粘贴一份路由注册**。
- 产物 `libartex.a` + `libartex.h` 一起进 Xcode 工程，Swift 通过 bridging header 调 `ArtexStart`。
- `scripts/gen-xcodeproj.mjs` 要加：链接 `libartex.a`、`-lresolv`、`-framework Foundation`、`-framework Security`。

### A2. 依赖分级（决定哪些包能编进去）

先跑一遍 `go build -tags ios ./...` 看哪些包炸，然后按下表处理：

| 依赖 | 处理 | 说明 |
| --- | --- | --- |
| `modernc.org/sqlite` | ✅ 直接用 | 纯 Go，无 cgo，iOS 完美 |
| `jackc/pgx/v5` | 🔧 编译期排除 | iOS 上没有 Postgres；用 build tag 隔离，运行时只走 SQLite 分支 |
| `lqqyt2423/go-mitmproxy` | ⚠️ 保留但降级 | 能编译；iOS 不允许 App 改系统代理，只能监听 App 内流量。UI 上标「仅 App 内」 |
| `creack/pty` | ❌ 排除 | 交互式 shell，iOS 无 PTY |
| `os/exec`（`selfupdate/bootstrap.go:184`、`server/customtool.go:398`） | ❌ 排除 | 自更新在 iOS 无意义；自定义脚本工具（python 解释器）标记为 unsupported |
| `projectdiscovery/dnsx`、`miekg/dns` | ✅ 直接用 | 纯 Go DNS，能跑 |
| `golang.org/x/crypto`、`x/net` | ✅ 直接用 | |

**做法**：在需要排除的文件顶部加 `//go:build !ios`，并为 iOS 提供同名空实现（`*_ios.go`），保证 `go vet ./...` 在 iOS tag 下也能过。

### A3. 数据层：Postgres → SQLite

原版用 pgx 连 Postgres，iOS 上必须走 SQLite。

1. 用已有的 `backend/schema.sqlite.sql`（1294 行，已做 pg→sqlite 语法转换）初始化数据库。
2. 在 `db/` 里加一个 driver 抽象：`OpenDB(dataDir string)` 在 iOS tag 下返回 SQLite 连接，其他平台保持 pgx。
3. **SQL 方言差异要逐个改**，不要指望自动转换：
   - `$1` 占位符 → `?`（或用 `sqlx.Rebind`）
   - `now()` → `datetime('now')`
   - `ILIKE` → `LIKE`（SQLite 默认不区分大小写，需确认 `PRAGMA case_sensitive_like=OFF`）
   - `ON CONFLICT ... DO UPDATE` 语法一致，可用
   - `jsonb` → `TEXT` + `json_extract()`
   - `RETURNING` SQLite 3.35+ 支持，可用
   - 数组类型 → JSON 文本
   - `interval '5 minutes'` → `datetime('now','-5 minutes')`
4. 全量搜索 `db/` 下所有 `.go` 里的原生 SQL，列出差异清单后再改，不要边改边猜。
5. 数据目录：`FileManager.default.urls(for: .applicationSupportDirectory)`，通过 `ArtexStart` 的 `dataDir` 传进去。

### A4. 执行层（唯一允许变更的功能点）

原版 Agent 靠 `Bash` 工具跑 `nmap` / `sqlmap` / `curl` / `hydra`。**iOS 沙箱物理上禁止 fork/exec 任意二进制**，这是系统限制，无法绕过。

保功能的做法是**替换执行后端，不替换工具接口**：

```go
// exec/runner.go（新文件）
type Runner interface {
    Run(ctx context.Context, cmd string, timeout time.Duration) (stdout, stderr string, code int, err error)
}
```

三个实现，按能力自动选择：

| 实现 | 场景 | 覆盖的命令 |
| --- | --- | --- |
| `LocalRunner` | 离线、无电脑 | Go 原生实现：`dig`/`nslookup`（miekg/dns）、端口扫描（`net.DialTimeout` 并发）、HTTP 请求（`net/http`，支持自定义 header/代理）、子域枚举（字典 + DNS）、TLS 证书读取、目录爆破（并发 HTTP） |
| `RemoteRunner` | 已配置电脑上的 ARTEXX | 把命令 POST 到远端 `/api/exec`（需在远端加一个端点），拿回 stdout/stderr |
| `MockRunner` | 演示 | 返回 `command not supported on iOS`，并在 UI 上明确提示 |

关键要求：
- **Agent 的 prompt、工具名、参数 schema 全部不变**，只换底层执行。
- `LocalRunner` 要覆盖原版 prompt 里最常用的命令族，至少：`nmap -p/-sT`、`curl`、`dig`、`whois`（可降级）、`openssl s_client`、`sqlmap`（降级为自研注入探测）、`gobuster/ffuf`（降级为内置字典爆破）、`hydra`（降级为并发登录尝试）。
- 每个降级实现都要在返回文本里写清"这是 iOS 内置实现，不是原生工具"，避免 Agent 误判证据。
- 无法实现的（需要内核/raw socket 的 SYN 扫描、ARP、抓包）→ 返回明确错误 + 建议「接远端服务器」。

### A5. 入口与生命周期

1. `AppDelegate` / `ArtExxApp.init()` 里调 `ArtexStart(8787, dataDir)`，失败则降级到 Swift 版 `EmbeddedServer`（保留作为兜底）。
2. App 进后台时**不要**停 Go runtime（iOS 会挂起进程，回来时 socket 还在）。
3. 内存警告时不要杀 Go runtime，只清 WebView 缓存。

### A6. 文件系统

iOS 沙箱路径规则：

| 用途 | 路径 |
| --- | --- |
| 数据库 / 配置 | `Library/Application Support/artex/` |
| 工作空间（workspace 页面） | `Documents/workspace/`（`UIFileSharingEnabled` 已开，用户能在「文件」App 里看到） |
| 技能目录 | `Application Support/artex/skills/`（首次启动从 bundle 解压） |
| 临时文件 | `NSTemporaryDirectory()` |

所有 `os.Getwd()` / 相对路径的地方都要改，`grep -rn "os.Getwd\|\./" --include=*.go server/ db/ agent/` 逐个核对。

---

## 4. 阶段 B：前端 iOS 适配（**不许改界面**）

### B0. 与"移动端改版"的界线

| 允许 | 禁止 |
| --- | --- |
| 加 `viewport` / 安全区 / `dvh` | 把表格改成卡片列表 |
| 按钮触摸区从 32px 提到 40px | 改配色、改字体、改间距体系 |
| 表格外层加横向滚动 + 首列 sticky | 隐藏桌面端有的字段 |
| 给 hover-only 的操作补 active 态 | 重排信息层级 |
| 弹窗在窄屏改底部抽屉 | 换组件库 |
| 输入框 font-size ≥ 16px | 删功能、改路由 |

**判断标准**：在 1280px 宽的桌面浏览器里打开改造后的 `out`，与改造前的截图**像素级对比不应有可见差异**（除了按钮高度）。

### B1. 必做项

1. `src/app/layout.tsx` 导出 `viewport`：`viewportFit:"cover"`、`userScalable:false`、`themeColor`。
2. `globals.css` 加安全区变量与 `pt-safe/pb-safe/h-app` 工具类；`html,body{overscroll-behavior:none}`。
3. 全站 `100vh` / `h-screen` / `min-h-screen`（8 处）→ `100dvh` / `h-app`。
4. 输入框 `font-size ≥ 16px`（防 iOS 自动缩放）。
5. `components/ui/button.tsx`：`sm` 从 `h-8`→`max-md:h-10`，`icon` 从 `size-9`→`max-md:size-11`。
6. 15 个用 `<Table>` 的页面：外层 `<div className="overflow-x-auto -mx-3 px-3">`，`<Table className="min-w-[720px]">`；首列 `sticky left-0 bg-background z-10`。
7. `group-hover:` 出现的操作按钮：加 `max-md:opacity-100`。
8. `Dialog` 在 `max-md` 下贴底：`max-md:inset-x-0 max-md:bottom-0 max-md:top-auto max-md:rounded-t-2xl max-md:max-h-[85dvh]`。
9. 图表：`ResponsiveContainer` 高度 `max-md:h-[180px]`；图谱（g6/xyflow）移动端给「展开全屏」按钮，默认不渲染。
10. `autoFocus` 只在 `!isMobile` 时生效。

### B2. 构建与替换

```bash
cd E:\ds\_ref\ARTEXX\web
npx tsc --noEmit
# Windows PowerShell:
$env:NEXT_EXPORT="1"; npx next build
# bash / macOS:
NEXT_EXPORT=1 npx next build

rm -rf E:/ds/ARTEXX-iOS/ios/ARTEXX/Resources/webui
cp -r out E:/ds/ARTEXX-iOS/ios/ARTEXX/Resources/webui
```

⚠️ `NEXT_EXPORT` 不设会走 dev 分支（带 rewrites），产物不是纯静态。

---

## 5. 阶段 C：技能与 CVE 内置

### C1. 技能（319 条）

原版读的是 `skills/<name>/SKILL.md` 目录结构（agentskills.io 规范），不是 JSON。

要做的事：
1. 写脚本 `scripts/skills-json-to-dirs.mjs`：把现有 `skills.json`（319 条）转成 319 个目录，每个含 `SKILL.md`（frontmatter: `name` / `description` / `license` / `compatibility` / `mcps` + 正文放命令清单、适用场景、注意事项）。
2. 把生成结果放进 `ios/ARTEXX/Resources/skills/`，作为 **folder reference** 打进 bundle。
3. 首次启动时从 bundle 复制到 `Application Support/artex/skills/`（Go 侧要能写，不能直接读 bundle）。
4. Go 侧把 skills 根目录指向该路径，验证 `/api/skills` 返回 319 条。

**要求**：`SKILL.md` 的正文质量要够——原版 Agent 是把这个文件当提示词读的。每条至少包含：什么时候用、前置条件、可直接执行的命令、判读要点。

### C2. CVE（201,607 条）

原版**没有 CVE 知识库**（`grep -i cve` 只在 prompt 里出现"不要拿 CVE 匹配当证据"）。所以这是**纯增量**，必须保证不碰原有行为。

1. 数据：现有 `ios/ARTEXX/Resources/cve.sqlite.gz`（78.5 MB → 解压 395 MB，FTS5 索引齐全）。
2. 首次启动解压到 `Application Support/artex/cve.sqlite`（后台线程，内存恒定 < 2 MB）。
3. 新增 Go 包 `cve/`：
   - `Search(q string, severity string, vendor string, minScore float64, limit, offset int) ([]CVEEntry, int, error)`
   - `Get(id string) (*CVEEntry, error)`
   - `BySkill(skillID string, limit int) ([]CVEEntry, error)`
4. 新增路由（**只增不改**，放在 `server/cve_api.go`）：
   - `GET /api/cve/search?q=&severity=&vendor=&min_score=&limit=&offset=`
   - `GET /api/cve/{id}`
   - `GET /api/cve/stats`
5. 前端新增一个页面 `src/app/(main)/function/cve/page.tsx` + 侧边栏加一项：
   - 搜索框（FTS5 前缀匹配）、严重度筛选、厂商筛选、CVSS 滑块
   - 列表 + 详情（四段式：针对什么 / 怎么使用 / 怎么实现 / 真实案例）
   - **风格必须与其他页面完全一致**（复用现有 Card/Table/Badge/Tabs，不要引入新样式）
6. 这一条会多出一个页面（27 → 28 条路由）。这是用户明确要求的增量，不算"改界面"；但**原有 27 个页面一个像素都不许动**。

---

## 6. 构建流水线

`.github/workflows/build-ipa.yml` 要改：

1. `runs-on: macos-14`（需要 Xcode + Go）。
2. 加 `actions/setup-go@v5`，`go-version: '1.26.x'`。
3. 构建顺序：
   ```
   1) go build（iOS 交叉编译）→ libartex.a
   2) npm ci && NEXT_EXPORT=1 next build → out
   3) 拷贝 webui / skills / cve.sqlite.gz
   4) node scripts/gen-xcodeproj.mjs
   5) xcodebuild archive（CODE_SIGNING_ALLOWED=NO）
   6) 打包 Payload → ipa
   ```
4. 产物名 `ARTEXX-ipa`，路径 `dist/ARTEXX-unsigned.ipa`。

本地 `build-ipa.cmd` 不用改（它只是 push + 等 CI + 下载）。

---

## 7. 验收（逐条打勾）

**后端真实性**
- [ ] `curl http://127.0.0.1:8787/api/health` 返回的是 Go 版 `{"ok":true,"service":"artex",...}`，不是 Swift 版
- [ ] `/api/tasks` 返回结构与上游 `server/dto.go` 一致（字段名、嵌套、时间格式）
- [ ] 建一个任务 → 数据库里真有记录（`sqlite3` 能查到）
- [ ] 配好 LLM Key 后，Agent 真的跑起来：plan → tool → result 有 SSE 事件
- [ ] 253 条路由里，随机抽 20 条，`curl` 都不 404、不 500
- [ ] 删除 `APICompat.swift` 后 App 仍能正常工作（证明真后端接管）

**前端一致性**
- [ ] 1280px 桌面截图与改造前 diff 无可视差异（除按钮高度）
- [ ] iPhone 13 mini 上 27 个页面逐个打开，无横向溢出、无内容被裁
- [ ] 表格能横向滚动，首列不跟着滚
- [ ] 输入框聚焦不放大页面
- [ ] 弹窗不被键盘遮挡

**知识库**
- [ ] `/api/skills` 返回 319 条
- [ ] 技能详情能打开，内容非空
- [ ] `/api/cve/search?q=apache tomcat` 有命中
- [ ] CVE 详情四段式内容完整
- [ ] 飞行模式下这两个库仍可用

**执行层**
- [ ] 离线时 Agent 能完成一次真实扫描（DNS + 端口 + HTTP 指纹）
- [ ] 执行 `nmap` 这类无法实现的命令时，返回明确的"iOS 不支持，请接远端"而不是静默失败

---

## 8. 禁止事项

- 不要用 Swift 重写后端业务逻辑（除了执行层）
- 不要保留 `APICompat.swift` 作为"双后端"（要删掉，只留 Go）
- 不要改 `web/src/lib/api.ts` 的路径与字段
- 不要改 `web/src/lib/types.ts` 的字段名
- 不要手改 `web/out/`
- 不要手改 `project.pbxproj`（用脚本生成）
- 不要把表格卡片化、不要重排信息架构
- 不要引入新的 UI 框架或新 npm 依赖
- 不要在 iOS 上假装支持 raw socket / 抓包

---

## 9. 已知不可行（写清楚，别硬做）

| 能力 | 为什么不行 | 替代 |
| --- | --- | --- |
| 跑 `nmap -sS`（SYN 半开扫描） | 需要 raw socket / root | `-sT` 全连接扫描（Go net.Dial 并发） |
| 跑任意二进制（sqlmap/hydra/gobuster） | iOS 禁止 fork/exec | 内置 Go 等价实现，或接远端 |
| 抓系统级流量（MITM 全机） | iOS 不允许 App 改系统代理 | App 内代理 + 用户手动设 Wi-Fi 代理 |
| 交互式 PTY shell | 无 PTY 设备 | 单命令执行（每次 fork 一个新 ctx） |
| 自更新（替换自身二进制） | 沙箱 + 签名 | 走 App Store / 重签 |
| 后台常驻运行 | iOS 后台挂起 | 前台运行；长任务用 BGTask 续命 |

这些不是"偷懒"，是系统限制。要在 App 的「关于」页里如实列出。

---

## 10. 工作节奏

1. **先勘察**：跑 `go build -tags ios ./...`，把编译失败清单、SQL 方言差异清单、exec 依赖点清单列出来给我确认。
2. **先通一条线**：`ArtexStart` → `/api/health` 通 → `/api/tasks` 通 → 前端能列出任务。这条线不通，别的都别做。
3. **小步提交**：一个阶段一个 commit。
4. **每步验证**：Go 侧 `go vet ./...` + `go build -tags ios`；前端 `tsc --noEmit` + `next build`。
5. **诚实报告**：你跑不了 iOS 模拟器就直说，只报构建结果和 curl 结果，不要编"已验证"。

---

现在开始：先给我**勘察报告**——iOS tag 下的编译失败清单、SQL 方言差异、exec 依赖点，以及阶段 A 的分步计划。等我确认后再动代码。
