import SwiftUI

/// 视觉：深色终端风，接近 ARTEXX Web 的暗色主题 + 青绿高亮。
enum ArtexTheme {
    static let bg = Color(red: 0.055, green: 0.062, blue: 0.078)      // #0E1014
    static let surface = Color(red: 0.086, green: 0.098, blue: 0.121) // #16191F
    static let surfaceHi = Color(red: 0.118, green: 0.133, blue: 0.161)
    static let border = Color(red: 0.20, green: 0.22, blue: 0.26)
    static let accent = Color(red: 0.30, green: 0.92, blue: 0.75)     // 青绿
    static let critical = Color(red: 0.96, green: 0.30, blue: 0.36)
    static let high = Color(red: 0.98, green: 0.56, blue: 0.24)
    static let medium = Color(red: 0.97, green: 0.83, blue: 0.31)
    static let low = Color(red: 0.44, green: 0.72, blue: 0.98)
    static let ok = Color(red: 0.36, green: 0.85, blue: 0.52)
    static let text = Color(red: 0.90, green: 0.92, blue: 0.95)
    static let dim = Color(red: 0.55, green: 0.60, blue: 0.66)

    static func severityColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "critical", "严重": return critical
        case "high", "高危": return high
        case "medium", "中危": return medium
        case "low", "低危": return low
        default: return dim
        }
    }
}

struct Card<Content: View>: View {
    var title: String? = nil
    var trailing: AnyView? = nil
    let content: () -> Content

    init(title: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || trailing != nil {
                HStack {
                    Text(title ?? "").font(.system(size: 13, weight: .semibold)).foregroundStyle(ArtexTheme.dim)
                    Spacer()
                    if let trailing { trailing }
                }
            }
            content()
        }
        .padding(14)
        .background(ArtexTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ArtexTheme.border, lineWidth: 0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct Pill: View {
    var text: String
    var color: Color = ArtexTheme.accent

    init(text: String, color: Color = ArtexTheme.accent) { self.text = text; self.color = color }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct MetricTile: View {
    var label: String
    var value: String
    var tint: Color = ArtexTheme.accent

    init(label: String, value: String, tint: Color = ArtexTheme.accent) { self.label = label; self.value = value; self.tint = tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ArtexTheme.surfaceHi)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct EmptyHint: View {
    var text: String

    init(text: String) { self.text = text }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 26)).foregroundStyle(ArtexTheme.dim)
            Text(text).font(.system(size: 13)).foregroundStyle(ArtexTheme.dim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}


/// 离线模式下，需要服务端的页面用它提示
struct OfflineNotice: View {
    var what: String
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 34))
                .foregroundStyle(ArtexTheme.medium)
            Text(what + " 需要连接 ARTEXX 服务端")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ArtexTheme.text)
            Text("当前处于离线模式。\n内置技能库、CVE 知识库、cmd 控制台可直接使用。")
                .font(.system(size: 12))
                .foregroundStyle(ArtexTheme.dim)
                .multilineTextAlignment(.center)
            Button("去连接服务器") { store.leaveOffline() }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(ArtexTheme.accent).foregroundStyle(.black)
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .background(ArtexTheme.bg)
    }
}

/// 离线状态条（主界面顶部）
struct OfflineBadge: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        if store.offlineMode {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash").font(.system(size: 9))
                Text("离线模式").font(.system(size: 10, weight: .semibold))
                Spacer()
                Button("连接服务器") { store.leaveOffline() }
                    .font(.system(size: 10))
            }
            .foregroundStyle(ArtexTheme.medium)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(ArtexTheme.medium.opacity(0.12))
        }
    }
}
