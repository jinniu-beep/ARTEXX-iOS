import SwiftUI

// MARK: - 页头（h1 text-lg + p text-xs）
struct PageTitle: View {
    var title: String
    var sub: String?
    var action: AnyView?

    init(_ title: String, sub: String? = nil, action: AnyView? = nil) {
        self.title = title; self.sub = sub; self.action = action
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(ArtexTheme.text)
                if let sub { Text(sub).font(.system(size: 11)).foregroundStyle(ArtexTheme.dim) }
            }
            Spacer()
            if let action { action }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }
}

// MARK: - Tabs（对齐 shadcn Tabs：底部分隔线 + 选中下划线）
struct ArtexTabs: View {
    var items: [String]
    @Binding var selection: Int

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { selection = i }
                        } label: {
                            VStack(spacing: 6) {
                                Text(t)
                                    .font(.system(size: 12, weight: selection == i ? .semibold : .regular))
                                    .foregroundStyle(selection == i ? ArtexTheme.text : ArtexTheme.dim)
                                    .padding(.horizontal, 10)
                                Rectangle()
                                    .fill(selection == i ? ArtexTheme.text : Color.clear)
                                    .frame(height: 1.5)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            Rectangle().fill(ArtexTheme.border).frame(height: 0.5)
        }
    }
}

// MARK: - 搜索框（对齐 shadcn Input + 放大镜）
struct SearchField: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
            TextField(placeholder, text: $text)
                .font(.system(size: 12))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(ArtexTheme.bg)
        .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm).stroke(ArtexTheme.input, lineWidth: 0.8))
        .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
    }
}

// MARK: - 下拉筛选（对齐 shadcn Select）
struct FilterMenu: View {
    var label: String
    var options: [String]
    @Binding var selection: String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { o in
                Button {
                    selection = o
                } label: {
                    if selection == o { Label(o, systemImage: "checkmark") } else { Text(o) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selection == options.first ? label : selection)
                    .font(.system(size: 11))
                    .foregroundStyle(selection == options.first ? ArtexTheme.dim : ArtexTheme.text)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(ArtexTheme.dim)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(ArtexTheme.bg)
            .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm).stroke(ArtexTheme.input, lineWidth: 0.8))
            .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
        }
    }
}

// MARK: - 按钮（对齐 shadcn Button 变体）
struct ArtexButton: View {
    enum Style { case primary, outline, ghost, destructive }
    var title: String
    var icon: String?
    var style: Style = .primary
    var compact: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10)) }
                Text(title).font(.system(size: compact ? 11 : 12, weight: .medium))
            }
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .background(bg)
            .foregroundStyle(fg)
            .overlay(
                RoundedRectangle(cornerRadius: ArtexTheme.radiusSm)
                    .stroke(style == .outline ? ArtexTheme.input : Color.clear, lineWidth: 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
        }
    }

    private var bg: Color {
        switch style {
        case .primary: return ArtexTheme.text
        case .outline, .ghost: return Color.clear
        case .destructive: return ArtexTheme.critical.opacity(0.15)
        }
    }
    private var fg: Color {
        switch style {
        case .primary: return ArtexTheme.bg
        case .outline, .ghost: return ArtexTheme.text
        case .destructive: return ArtexTheme.critical
        }
    }
}

// MARK: - 表格（对齐 shadcn Table：表头灰底细线，行分隔）
struct ArtexTable<Row: Identifiable, Cell: View>: View {
    var columns: [String]
    var rows: [Row]
    var rowHeight: CGFloat = 44
    @ViewBuilder var cell: (Row) -> Cell

    var body: some View {
        VStack(spacing: 0) {
            // 表头
            HStack(spacing: 0) {
                ForEach(columns, id: \.self) { c in
                    Text(c)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ArtexTheme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                }
            }
            .background(ArtexTheme.surfaceHi.opacity(0.4))

            Rectangle().fill(ArtexTheme.border).frame(height: 0.5)

            ForEach(rows) { r in
                cell(r)
                    .frame(minHeight: rowHeight)
                Rectangle().fill(ArtexTheme.border).frame(height: 0.5)
            }
        }
    }
}

// MARK: - 属性行（Label + 值，对齐 Field）
struct FieldRow: View {
    var label: String
    var value: String
    var tint: Color = ArtexTheme.text

    var body: some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                .frame(width: 92, alignment: .leading)
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(tint)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 输入框（对齐 shadcn Input）
struct ArtexField: View {
    var label: String?
    var placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var multiline: Bool = false
    var desc: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let label {
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(ArtexTheme.text)
            }
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else if multiline {
                    TextField(placeholder, text: $text, axis: .vertical).lineLimit(3...6)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(size: 12))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 9).padding(.vertical, 8)
            .background(ArtexTheme.bg)
            .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm).stroke(ArtexTheme.input, lineWidth: 0.8))
            .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))

            if let desc {
                Text(desc).font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
            }
        }
    }
}

// MARK: - 开关（对齐 shadcn Switch）
struct ArtexToggle: View {
    var label: String
    @Binding var on: Bool

    var body: some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(ArtexTheme.text)
            Spacer()
            Toggle("", isOn: $on)
                .labelsHidden()
                .tint(ArtexTheme.text)
                .scaleEffect(0.8)
        }
    }
}

// MARK: - 相对时间（对齐 fmtRel）
func fmtRel(_ date: Date?) -> String {
    guard let date else { return "—" }
    let s = Int(Date().timeIntervalSince(date))
    if s < 60 { return "\(max(0, s))s 前" }
    let m = s / 60
    if m < 60 { return "\(m)m 前" }
    let h = m / 60
    if h < 24 { return "\(h)h 前" }
    return "\(h / 24)d 前"
}

// MARK: - Token 格式化（对齐 fmtTokens）
func fmtTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
    return String(n)
}
