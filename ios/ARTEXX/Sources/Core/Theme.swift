import SwiftUI

/// 视觉规范：严格对齐 ARTEXX Web 端（shadcn/ui 深色主题）
/// 对应 globals.css 中 .dark 的 oklch 变量
enum ArtexTheme {
    // ── 基础色板（oklch → sRGB 已换算）──────────────────────────────
    /// --background: oklch(0.145 0 0)
    static let bg = Color(hex: 0x0A0A0A)
    /// --foreground: oklch(0.985 0 0)
    static let text = Color(hex: 0xFAFAFA)
    /// --card: oklch(0.205 0 0)
    static let surface = Color(hex: 0x171717)
    /// --card-foreground / --primary: oklch(0.985 0 0)
    static let surfaceText = Color(hex: 0xFAFAFA)
    /// --popover: oklch(0.205 0 0)
    static let popover = Color(hex: 0x171717)
    /// --secondary / --muted / --accent: oklch(0.269 0 0)
    static let surfaceHi = Color(hex: 0x262626)
    /// --muted-foreground: oklch(0.708 0 0)
    static let dim = Color(hex: 0xA3A3A3)
    /// --border: oklch(1 0 0 / 10%)
    static let border = Color.white.opacity(0.10)
    /// --input: oklch(1 0 0 / 15%)
    static let input = Color.white.opacity(0.15)
    /// --ring: oklch(0.556 0 0)
    static let ring = Color(hex: 0x737373)
    /// --sidebar: oklch(0.205 0 0)
    static let sidebar = Color(hex: 0x171717)
    /// --sidebar-accent: oklch(0.269 0 0)
    static let sidebarAccent = Color(hex: 0x262626)

    // ── 语义色（dashboard 实际用的 Tailwind 色）──────────────────────
    /// text-blue-400 —— 探索/运行中
    static let accent = Color(hex: 0x60A5FA)
    /// text-rose-500 —— 严重
    static let critical = Color(hex: 0xF43F5E)
    /// text-red-400 —— 高危
    static let high = Color(hex: 0xF87171)
    /// text-amber-400 —— 中危
    static let medium = Color(hex: 0xFBBF24)
    /// text-slate-400 —— 低危
    static let low = Color(hex: 0x94A3B8)
    /// text-emerald-400 / emerald-500 —— 完成/成功
    static let ok = Color(hex: 0x34D399)
    /// text-violet-500 —— 子域名等
    static let violet = Color(hex: 0x8B5CF6)
    /// text-cyan-500 —— 服务
    static let cyan = Color(hex: 0x06B6D4)
    /// text-orange-400 —— 应用
    static let orange = Color(hex: 0xFB923C)
    /// text-indigo-400 —— IP
    static let indigo = Color(hex: 0x818CF8)

    // ── 圆角（--radius: 0.625rem = 10pt）────────────────────────────
    static let radius: CGFloat = 10
    static let radiusSm: CGFloat = 6
    static let radiusLg: CGFloat = 14

    /// 严重度颜色，对齐 findingsBySev 用色
    static func severityColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "critical", "严重": return critical
        case "high", "高危": return high
        case "medium", "中危": return medium
        case "low", "低危": return low
        default: return dim
        }
    }

    /// 资产类型颜色（对应用 ASSET_COLORS）
    static func assetColor(_ kind: String) -> Color {
        switch kind {
        case "root_domain": return Color(hex: 0x3B82F6)   // bg-blue-500
        case "ip": return indigo
        case "subdomain": return violet
        case "app": return orange
        case "service": return cyan
        case "endpoint": return Color(hex: 0x10B981)      // bg-emerald-500
        default: return dim
        }
    }

    /// HTTP 状态码着色（对应 statusColor）
    static func statusColor(_ code: Int) -> Color {
        if code < 300 { return Color(hex: 0x10B981) }
        if code < 400 { return accent }
        if code < 500 { return medium }
        return high
    }
}

extension Color {
    /// 0xRRGGBB → Color
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

// ── 组件：严格对齐 shadcn Card ──────────────────────────────────────

/// 对应 <Card>：bg-card rounded-lg border shadow-sm
struct Card<Content: View>: View {
    var title: String?
    var trailing: AnyView?
    var padded: Bool
    let content: () -> Content

    init(title: String? = nil, trailing: AnyView? = nil, padded: Bool = true,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.padded = padded
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || trailing != nil {
                HStack(spacing: 6) {
                    if let title {
                        // text-xs font-semibold
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ArtexTheme.surfaceText)
                    }
                    Spacer(minLength: 0)
                    if let trailing { trailing }
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padded ? 16 : 0)
        .background(ArtexTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: ArtexTheme.radius)
                .stroke(ArtexTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
    }
}

/// 对应 <Badge>：rounded-md border px-2 py-0.5 text-[10px]
struct Pill: View {
    var text: String
    var color: Color

    init(text: String, color: Color = ArtexTheme.dim) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .overlay(
                RoundedRectangle(cornerRadius: ArtexTheme.radiusSm)
                    .stroke(color.opacity(0.35), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
    }
}

/// 统计卡：对齐 dashboard Row1 的 Card（gap-1，标题 text-[10px]，数值 text-2xl）
struct StatCard: View {
    var icon: String
    var label: String
    var value: String
    var suffix: String?
    var tint: Color
    var footer: AnyView?

    init(icon: String, label: String, value: String, suffix: String? = nil,
         tint: Color = ArtexTheme.text, footer: AnyView? = nil) {
        self.icon = icon
        self.label = label
        self.value = value
        self.suffix = suffix
        self.tint = tint
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 10))
            }
            .foregroundStyle(ArtexTheme.dim)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ArtexTheme.surfaceText)
                    .monospacedDigit()
                if let suffix {
                    Text(suffix).font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                }
            }

            if let footer {
                footer.padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(ArtexTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: ArtexTheme.radius)
                .stroke(ArtexTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
    }
}

/// 区块标题：对齐 SectionTitle（icon size-3.5 + text-xs font-semibold + 右侧 sub）
struct SectionHeader: View {
    var icon: String
    var title: String
    var sub: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(ArtexTheme.surfaceText)
            Spacer()
            if let sub {
                Text(sub).font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
            }
        }
    }
}

/// 页面大标题：h1 text-lg font-semibold + p text-xs muted
struct PageHeader: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ArtexTheme.text)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(ArtexTheme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 实时闪烁点（对应 LiveDot：size-1.5 animate-pulse rounded-full bg-blue-400）
struct LiveDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(ArtexTheme.accent)
            .frame(width: 5, height: 5)
            .opacity(on ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(), value: on)
            .onAppear { on = true }
    }
}

/// 空状态
struct EmptyHint: View {
    var text: String
    init(text: String) { self.text = text }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 22))
                .foregroundStyle(ArtexTheme.dim.opacity(0.6))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(ArtexTheme.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

/// 进度条：对应 shadcn <Progress>
struct ArtexProgress: View {
    var value: Double
    var tint: Color = ArtexTheme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(ArtexTheme.surfaceHi)
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}

/// 离线提示
struct OfflineNotice: View {
    var what: String
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 30))
                .foregroundStyle(ArtexTheme.medium)
            Text(what + " 需要连接 ARTEXX 服务端")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ArtexTheme.text)
            Text("当前处于离线模式。\n内置技能库、CVE 知识库、cmd 控制台可直接使用。")
                .font(.system(size: 11))
                .foregroundStyle(ArtexTheme.dim)
                .multilineTextAlignment(.center)
            Button("去连接服务器") { store.leaveOffline() }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(ArtexTheme.text).foregroundStyle(ArtexTheme.bg)
                .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .background(ArtexTheme.bg)
    }
}

/// 离线状态条
struct OfflineBadge: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        if store.offlineMode {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash").font(.system(size: 9))
                Text("离线模式").font(.system(size: 10, weight: .medium))
                Spacer()
                Button("连接服务器") { store.leaveOffline() }
                    .font(.system(size: 10))
            }
            .foregroundStyle(ArtexTheme.medium)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(ArtexTheme.medium.opacity(0.12))
            .overlay(Rectangle().frame(height: 0.5).foregroundStyle(ArtexTheme.border), alignment: .bottom)
        }
    }
}


/// 兼容别名：旧代码用 MetricTile，映射到 StatCard 风格
struct MetricTile: View {
    var label: String
    var value: String
    var tint: Color = ArtexTheme.text

    init(label: String, value: String, tint: Color = ArtexTheme.text) {
        self.label = label; self.value = value; self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(ArtexTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radius).stroke(ArtexTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
    }
}
