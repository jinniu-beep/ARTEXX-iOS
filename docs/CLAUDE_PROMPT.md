# 任务提示词：ARTEXX → iOS 完整移植 + 前端源码 iOS 适配

> 把这份文档整段贴给 Claude Code（或任何具备文件读写 + 终端能力的 agent）。
> 它是自包含的：不需要看之前的对话。

---

## 0. 你的角色与目标

你是一名同时懂 **Next.js / React / Tailwind v4** 和 **Swift / SwiftUI / WebKit** 的工程师。

你要在一个已经跑通的仓库上继续推进，最终交付一个 **未签名 ipa**：iPhone 上打开就是 ARTEXX 的原版界面，界面针对触摸屏做了真正的适配（不是把桌面版缩小），并且离线可用。

本次会话的核心任务是 **阶段 A：把原版前端源码改成 iOS 适配版**。阶段 B/C 是后续增强，先不要动。

---

## 1. 现状：这些已经做完了，不要重做

仓库：`https://github.com/jinniu-beep/ARTEXX-iOS`（本地路径 `E:\ds\ARTEXX-iOS`）
上游原版：`https://github.com/imxv/ARTEXX`（本地参考副本 `E:\ds\_ref\ARTEXX`）

已完成：

1. **Xcode 工程可编译**，GitHub Actions 自动构建未签名 ipa，产物 `dist/ARTEXX-unsigned.ipa`（约 84 MB）。
2. **原版前端整站已内置**：`ios/ARTEXX/Resources/webui/` 是官方 `web/out` 的静态导出产物（370 文件 / 27 条路由），与上游**逐字节一致**。
3. **内置 HTTP 服务**：App 启动时在 `127.0.0.1:8787` 起 `NWListener`，托管 webui 静态文件 + 实现 `/api/*`。
4. **API 兼容层**：`ios/ARTEXX/Sources/Core/APICompat.swift`（743 行），按 `web/src/lib/types.ts` 的形状返回本地数据，约 40 条端点。
5. **本地数据层**：`LocalTaskStore`（任务 JSON 持久化）、`SkillLibrary`（319 条技能）、`CVEDatabase`（201,607 条 CVE，SQLite + FTS5）、`NativeScanner`（BSD socket 实现的 DNS/端口/HTTP/子域枚举）。
6. **本地 Agent**：`LocalAgent.swift`，调 LLM 规划 + 6 个本地工具（`dns_resolve` / `scan_ports` / `http_probe` / `subdomain_enum` / `search_cve` / `search_skills`）。
7. **一键构建脚本** `build-ipa.cmd`：生成工程 → 语法自检 → push → 等 CI → 下载 ipa。

**不要重写上面任何一块。** 你的工作是改前端源码，让它适配 iOS，然后重新导出替换。

---

## 2. 关键路径地图

```
E:\ds\ARTEXX-iOS\
├── build-ipa.cmd                     一键构建
├── ios\
│   ├── ARTEXX.xcodeproj              由脚本生成，勿手改
│   └── ARTEXX\
│       ├── Sources\
│       │   ├── App\                  ArtExxApp / RootView / AppShell
│       │   ├── Core\                 APICompat / Router / EmbeddedServer / StaticFiles / WebUIView
│       │   ├── Data\                 CVEDatabase / SkillLibrary / LocalTaskStore / Gzip
│       │   ├── Models\               Models.swift
│       │   └── Features\             原生 SwiftUI 页面
│       └── Resources\
│           ├── webui\                ← 原版前端产物（你要替换的就是这个目录）
│           ├── cve.sqlite.gz         78.5 MB
│           ├── skills.json           319 条
│           └── exploits.json         25,095 条 CVE→EXP 映射
└── scripts\
    ├── gen-xcodeproj.mjs             扫描 Sources 重新生成 pbxproj
    └── syntaxcheck.mjs               Swift 括号/结构自检

E:\ds\_ref\ARTEXX\web\               ← 前端源码在这里（Next.js 15 App Router）
├── src\app\                         27 条路由
├── src\components\ui\               shadcn/ui（60 个组件）
├── src\hooks\use-mobile.ts          已有 768px 断点 hook
├── src\lib\api.ts                   所有接口调用（1316 行）
├── src\lib\types.ts                 所有 DTO 定义（1612 行）
├── src\app\globals.css              Tailwind v4 入口
└── next.config.mjs                  output:"export" + trailingSlash:true
```

**技术栈**：Next.js 15 App Router、React 19、Tailwind CSS **v4**（`@import "tailwindcss"`，无 tailwind.config.js）、shadcn/ui、Radix/base-ui、recharts、@antv/g6、@xyflow/react、@tanstack/react-table。

---

## 3. 硬约束（违反就白干）

| 约束 | 原因 |
| --- | --- |
| **不能改 `web/out/`**，只能改 `web/src/` 再重新 build | out 是构建产物 |
| **不能改 `src/lib/api.ts` 的请求路径和字段名** | 后端契约固定，改了 APICompat 全崩 |
| **不能用动态路由 `[id]`** | 静态导出不支持，原版已统一用 `?id=` query |
| **不能用 `100vh` / `h-screen`** | iOS 地址栏收缩会切内容，必须用 `dvh` |
| **不能只靠 `hover:` 传达信息** | 触摸设备 hover 会「粘住」，必须同时给 active/focus 态 |
| **输入框 `font-size` 不能小于 16px** | 小于 16px iOS 会自动放大页面 |
| **不要引入新 npm 依赖**（除非确实无法实现，且需说明理由） | 包体已经 84 MB |
| **不要改 iOS 侧的 Swift 代码**（除非阶段 A 完成后发现接口对不上） | 已经在 CI 上编译通过 |
| **桌面端不能退化** | 断点用 `md:` / `lg:`，桌面保持现状 |

---

## 4. 阶段 A：前端源码 iOS 适配（本次核心）

### A0. 总原则

**移动优先，但不破坏桌面。** 断点沿用现有的 `768px`（`useIsMobile`）。
所有适配用 Tailwind 响应式前缀（`max-md:` / `md:`）或 `useIsMobile()` 实现，不要写死只给手机用的分支。

判断标准只有一条：**在 iPhone 13 mini（375×812）上单手能不能顺畅用完整个流程**——打开 → 看任务 → 进详情 → 看发现 → 查技能/CVE → 改设置。

---

### A1. 视口与安全区（先做，影响全部页面）

改 `src/app/layout.tsx`：

1. 导出 Next 的 `viewport`：

```ts
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  viewportFit: "cover",
  themeColor: "#0a0a0a",
};
```

`viewportFit: "cover"` 是刘海屏全屏的前提，缺了 `env(safe-area-inset-*)` 全是 0。

2. 在 `globals.css` 里加安全区变量和工具类：

```css
:root {
  --safe-top: env(safe-area-inset-top, 0px);
  --safe-bottom: env(safe-area-inset-bottom, 0px);
  --safe-left: env(safe-area-inset-left, 0px);
  --safe-right: env(safe-area-inset-right, 0px);
  --app-height: 100dvh;
}

@utility pt-safe { padding-top: var(--safe-top); }
@utility pb-safe { padding-bottom: var(--safe-bottom); }
@utility px-safe { padding-left: var(--safe-left); padding-right: var(--safe-right); }
@utility h-app { height: var(--app-height); }
```

3. 全局禁掉 iOS 的橡皮筋和长按选择：

```css
html, body {
  overscroll-behavior: none;
  -webkit-tap-highlight-color: transparent;
}
body { min-height: 100dvh; }
/* 文本可选，但按钮/导航不可选 */
button, a, [role="button"] { -webkit-user-select: none; user-select: none; }
/* 输入框防缩放 */
input, textarea, select { font-size: max(16px, 1em); }
```

4. 替换所有 `100vh` / `h-screen` / `min-h-screen`（共 8 处，用 `grep -rn "100vh\|h-screen" src` 找）→ `100dvh` / `h-app`。

---

### A2. 侧边栏

现状：`src/components/ui/sidebar.tsx` 已经内置移动端 `<Sheet>` 分支（`isMobile` 为真时走抽屉），`app-sidebar.tsx` 也已有触发按钮。**不用重写，只调整细节**：

1. 抽屉宽度：`w-[272px]` 这类写死宽度在 375px 屏上占比过大 → 改成 `w-[min(82vw,300px)]`。
2. 抽屉内容顶部要留安全区：`<SheetContent>` 内层加 `pt-safe pb-safe`。
3. 抽屉里的分组标题字号 `text-[10px]` 偏小 → 移动端 `text-[11px]`。
4. 每个导航项的高度确保 ≥ 44px（`h-11`），现在 `py-2` 约 36px。
5. 移动端默认**收起**，桌面默认展开——检查 `defaultOpen` 逻辑是否用 cookie 记忆，移动端不要继承桌面的展开状态。

---

### A3. 表格 → 移动端卡片化（工作量最大，15 个文件）

涉及：`function/tasks`、`function/findings`、`function/assets`、`function/commands`、`function/traffic`、`function/llm-records`、`system/agents`、`system/tools`、`system/mcp`、`system/logs`、`system/notify` 等。

**方案（二选一，按页面性质定）：**

- **数据型列表**（tasks / findings / assets / commands / traffic / llm-records）→ 移动端渲染**卡片列表**，桌面仍是 `<Table>`。抽一个通用组件：

```tsx
// src/components/mobile-card-list.tsx
export function MobileCardList<T>({
  items, renderCard, emptyText = "暂无数据",
}: { items: T[]; renderCard: (item: T) => React.ReactNode; emptyText?: string }) {
  if (!items.length) return <EmptyHint text={emptyText} />;
  return (
    <div className="flex flex-col gap-2 p-3 md:hidden">
      {items.map(renderCard)}
    </div>
  );
}
```

页面结构改成：

```tsx
<Table className="hidden md:table">…</Table>
<MobileCardList items={rows} renderCard={(r) => <TaskCard key={r.id} row={r} />} />
```

- **配置型表格**（system/tools、system/mcp、settings 类）→ 保留表格，但外层套 `overflow-x-auto` + `min-w-[640px]`，允许横向滚动，不强行卡片化。

卡片统一规范：`rounded-xl border p-3`，主标题 `text-[15px] font-medium`，元信息 `text-[12px] text-muted-foreground`，右侧放状态徽章；整张卡可点（`onClick` 或外层 `<Link>`），点击区 ≥ 44px。

**分页**：移动端把 `Pagination` 简化为「上一页 / 第 n/m 页 / 下一页」，不要渲染 10 个页码按钮。

---

### A4. 触摸目标与间距

全局扫一遍 `components/ui/button.tsx` 的 size 定义：

- `size="sm"` 默认 `h-8`（32px）→ 移动端 `max-md:h-10`（40px）
- `size="icon"` 默认 `size-9`（36px）→ 移动端 `max-md:size-11`（44px）
- 表格行内的操作按钮组，移动端改成卡片底部一行，`gap-2`，每个 ≥ 40px

不要用 `scale` 放大，直接改尺寸。

---

### A5. 去掉 hover-only 的交互

`grep -rn "hover:" src/app src/components | wc -l` 会看到大量 hover。

规则：
1. hover 只做**装饰**（变色、加边框），不允许 hover 才显示关键操作（如行内「删除」按钮只在 hover 出现）——这类必须改成常驻或收进 `DropdownMenu`。
2. 所有 `group-hover:` 出现的操作按钮，移动端改为 `max-md:opacity-100`。
3. `Tooltip` 在触摸设备无效 → 关键说明文字直接内联，或改用 `Popover`（点击触发）。

---

### A6. 弹窗 / 抽屉 / 下拉

1. `Dialog`：移动端改用 `Drawer`（底部弹出）或给 Dialog 加 `max-md:inset-x-0 max-md:bottom-0 max-md:top-auto max-md:rounded-t-2xl max-md:max-h-[85dvh]`，内容区 `overflow-y-auto`。
2. 表单类弹窗（新建任务、新建技能）必须能被键盘顶起：容器用 `max-h-[85dvh]` + `overflow-y-auto`，不要用固定高度。
3. `DropdownMenu` / `Select` 在窄屏会溢出屏幕 → 确认使用 Radix 的 collision padding（默认有），必要时加 `sideOffset={8}`。
4. 所有 fixed 定位的浮层，底部要留 `pb-[var(--safe-bottom)]`。

---

### A7. 图表与图谱页面

`dashboard` 用 recharts，`function/findings` 有图谱，`function/tasks/detail` 有覆盖图。

1. recharts：`<ResponsiveContainer>` 在移动端高度改 `h-[180px]`（桌面 `h-[280px]`），X 轴 tick 数量减半，`interval="preserveStartEnd"`。
2. @antv/g6 / @xyflow/react 图谱：移动端**默认收起**，给一个「展开图谱」按钮，展开后全屏 + 双指缩放（`zoomOnPinch`），并提供「适应屏幕」按钮。不要一进页面就渲染大图，iPhone 上会卡。
3. 所有 canvas/svg 容器加 `touch-action: pan-y` 以外的手势交给库处理，避免和页面滚动打架。

---

### A8. 文件上传 / 下载

`function/workspace`、`system/skills`（上传 zip）、导出报告都用 `fetch` + `Blob`。

iOS Safari/WKWebView 的行为差异：
1. `<a download>` **不生效**（不会存到「文件」App）。改用 `navigator.share()` 或把内容写进剪贴板，或提示「长按复制」。
2. 上传用 `<input type="file">` 可以，但 WKWebView 需要宿主实现 `UIDelegate`。**iOS 侧已经在 `WebUIView` 里设置了 `uiDelegate`**，你只需确保前端 input 有 `accept` 属性。
3. `URL.createObjectURL` + `revokeObjectURL` 要成对，iOS 上泄漏更明显。

如果某个功能（如 workspace 下载）在 iOS 上确实无法实现，**保留 UI 但点击时弹 toast 说明「iOS 上请用原生界面导出」**，不要留一个点了没反应的按钮。

---

### A9. 键盘与输入

1. 所有输入框 `font-size ≥ 16px`（A1 已全局处理，但 `text-sm`(14px) 的输入框会被覆盖，检查是否有 `!important` 冲突）。
2. 搜索框在移动端不要自动聚焦（会立刻弹键盘挡住半屏）：`autoFocus` 只保留在桌面分支。
3. 多行输入用 `textarea` + `rows` 而非 `contentEditable`。
4. 表单提交按钮固定在键盘上方会被遮挡 → 用 `sticky bottom-0` + `pb-safe`。

---

### A10. 滚动与长列表

1. 长列表（任务、发现、日志）加 `overscroll-contain`，避免滚动穿透到 body。
2. 列表页保留 `sticky top-0` 的筛选栏，但移动端要 `pt-safe`（否则被刘海挡住）。
3. 不要用 `position: fixed` 做页脚（iOS 键盘弹出会错位），用 `sticky`。

---

### A11. 构建与替换流程（每改完一个模块就跑一遍）

```bash
cd E:\ds\_ref\ARTEXX\web

# 1. 类型检查 + 构建（必须先过 tsc）
npx tsc --noEmit
NEXT_EXPORT=1 npx next build

# 2. 产物在 web/out，替换进 ipa 资源
rm -rf E:/ds/ARTEXX-iOS/ios/ARTEXX/Resources/webui
cp -r out E:/ds/ARTEXX-iOS/ios/ARTEXX/Resources/webui

# 3. 核对文件数（改造后可能略有增减，量级应仍在 370 左右）
find E:/ds/ARTEXX-iOS/ios/ARTEXX/Resources/webui -type f | wc -l

# 4. 重新生成工程 + 自检
cd E:\ds\ARTEXX-iOS
node scripts/gen-xcodeproj.mjs
node scripts/syntaxcheck.mjs

# 5. 提交推送，等 CI 出包
git add -A && git commit -m "feat(web): iOS adaptation" && git push
gh run watch --exit-status
gh run download $(gh run list --limit 1 --json databaseId --jq ".[0].databaseId") -n ARTEXX-ipa -D dist
```

**注意**：`next build` 时如果 `NEXT_EXPORT` 没设，会走 dev 分支（有 rewrites），产物不是纯静态。必须带这个环境变量。

Windows 下用 PowerShell 时 `NEXT_EXPORT=1 npx ...` 不生效，改成：

```powershell
$env:NEXT_EXPORT="1"; npx next build
```

---

### A12. 验收清单（逐条打勾，缺一条不算完成）

在 iPhone 真机（或 Xcode 模拟器 iPhone 13 mini）上：

- [ ] 打开 App 直接进任务页，**没有**停在登录页、没有白屏
- [ ] 顶部内容不被刘海/状态栏遮挡，底部按钮不被 Home 指示条遮挡
- [ ] 侧边栏从左侧滑出，宽度不超屏，能点关闭，能切页面
- [ ] 27 个页面逐个打开，**没有横向滚动条**、没有内容溢出到屏幕外
- [ ] 任务列表在 375px 宽下是卡片，不是被压扁的表格
- [ ] 点「新建任务」→ 弹窗不被键盘遮住 → 能提交 → 列表出现新任务
- [ ] 发现页筛选栏 sticky 且不被刘海遮挡
- [ ] 技能库搜索、CVE 库搜索能输入、能出结果、列表可滚动
- [ ] 任意输入框聚焦时，页面**不会**被放大
- [ ] 页面滚动到底后不会带动 body 弹跳
- [ ] 切到后台再回来，页面状态还在（WKWebView 不会重载）
- [ ] 横屏（旋转）布局不塌
- [ ] 桌面浏览器打开 `web/out`（用 `npx serve out`）**布局与改造前一致**

---

## 5. 阶段 B：把 API 兼容层补到 253 条（A 完成后再做）

上游 Go 后端 `server/` 有 253 条路由（`grep -c "mux.HandleFunc" server.go` = 243，全目录 253）。当前 `APICompat.swift` 只覆盖约 40 条。

补的顺序按页面依赖走，不要按字母序：

1. `tasks/{id}` 下的子资源：`goals` / `constraints` / `scope` / `intercept-rules` / `asset-refs` / `coverage-graph` / `llm/resolution`
2. `exploration/*`：`nodes` / `graph` / `activity` / `frontier` / `intents`
3. `findings/*`：`retests` / `groups` / `asset-tree` / `deepen` / `lineage` / `traffic`
4. `assets` 的 DSL 查询（`?dsl=`，语法见 `server/assets.go`）
5. `llm/*`：`profiles` CRUD / `pool` / `retry-policy` / `records`
6. `notify/*`、`intercept/*`、`workspace/*` 的写操作

每补一条，对照 `web/src/lib/types.ts` 的 interface 逐字段核对，**宁少字段不要错字段**——前端对 `undefined` 的容忍度比类型错误高。

---

## 6. 阶段 C：原生侧（可选）

原生 SwiftUI 侧已有 27 个页面。如果要继续：

1. `AppShell` 的 `useWebUI` 开关默认值改成 `false`，让用户可选原生或 Web。
2. 原生侧的 CVE 库（201,607 条）与技能库（319 条）比 Web 侧完整，考虑在 Web UI 里加一个「打开原生 CVE 库」的桥接入口。

---

## 7. 已经踩过的坑（改代码时别踩回去）

| 坑 | 现象 | 正确做法 |
| --- | --- | --- |
| **API 前缀判断** | `Router.swift` 曾先丢掉 `api` 段再比较，导致所有 `/api/*` 返回 404，整页空白 | 必须先判 `path.hasPrefix("/api/")` 再分流 |
| **ATS** | `http://127.0.0.1` 被 ATS 拦 | `Info.plist` 已设 `NSAllowsArbitraryLoads` + `NSAllowsLocalNetworking`，别删 |
| **前端登录守卫** | 前端读 `localStorage.artex_token`，没有就跳 `/login` | iOS 侧已在 `documentStart` 注入 token，别在前端加额外的登录校验 |
| **SSE** | EventSource 连不上会每 3 秒重连 | 服务端对 `/stream` 返回 **204**，EventSource 按规范停止重连 |
| **静态路由** | Next 静态导出 `trailingSlash:true`，RSC 预取请求 `<route>/index.txt` | `StaticFiles.swift` 已支持「目录 → index.html」和 `.txt`，改前端不要关掉 trailingSlash |
| **100vh** | iOS 地址栏收缩切掉内容 | 一律 `dvh` |
| **CVE 页不存在** | 原版前端 27 条路由里**没有 CVE 页**，CVE 库是原生侧新增的 tab | 不要试图在 Web UI 里找 CVE 页面，也不要新建一条路由（静态导出会多出文件，但 API 层没有对应端点） |

---

## 8. 禁止事项

- 不要重写 `src/lib/api.ts` 的接口签名
- 不要改 `src/lib/types.ts` 的字段名
- 不要手改 `web/out/`
- 不要手改 `ios/ARTEXX.xcodeproj/project.pbxproj`（用 `scripts/gen-xcodeproj.mjs` 生成）
- 不要为了「适配」而删掉桌面端功能（用响应式分支，不是删代码）
- 不要引入 UI 框架（MUI/Ant/Chakra）替换 shadcn
- 不要用 `!important` 覆盖 Tailwind（除了 A1 里明确列出的全局规则）
- 不要在移动端用 `position: fixed` 做输入区

---

## 9. 交付物

1. 改造后的 `web/src/**` 源码（可 diff 的完整改动）
2. 重新导出的 `ios/ARTEXX/Resources/webui/`（370 文件左右）
3. 一份 `web/IOS_ADAPTATION.md`：列出改了哪些文件、每个文件改了什么、为什么
4. 通过 CI 的 `dist/ARTEXX-unsigned.ipa`
5. A12 验收清单的逐条结果（哪条过、哪条没过、为什么）

---

## 10. 工作节奏要求

1. **先读再改**：动手前先 `grep` 清楚现状（哪些组件已有移动端分支、哪些页面用表格），把清单列出来给我确认。
2. **小步提交**：一个模块（如「表格卡片化」）一个 commit，不要一次改 40 个文件。
3. **每步验证**：每完成一个模块就跑 `npx tsc --noEmit` + `NEXT_EXPORT=1 npx next build`，构建失败立刻修，不要攒到最后。
4. **不确定就问**：遇到原版逻辑看不懂的地方（比如图谱数据流），先说明你的理解和两种可能做法，再动手。
5. **不要假装验证**：你无法运行 iOS 模拟器就明说「未在真机验证」，只报告构建和类型检查的真实结果。

---

现在开始：先输出你对 `web/src` 的**现状勘察报告**（27 条路由、15 个用表格的文件、8 处 100vh、已有的移动端分支），以及阶段 A 的**分模块改造计划**，等我确认后再动第一行代码。
