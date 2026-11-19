import SwiftUI

/// 技能选择器（新建任务时套用编排）
struct SkillPickerView: View {
    @Binding var picked: [Skill]
    @State private var query = ""
    @State private var category: String?
    @Environment(\.dismiss) var dismiss
    private let lib = SkillLibrary.shared

    private var list: [Skill] { lib.filtered(category: category, query: query) }

    var body: some View {
        VStack(spacing: 0) {
            // 分类筛选
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button { category = nil } label: {
                        Pill(text: "全部 \(lib.all.count)", color: category == nil ? ArtexTheme.accent : ArtexTheme.dim)
                    }
                    ForEach(lib.categories, id: \.0) { c in
                        Button { category = c.0 } label: {
                            Pill(text: "\(c.0) \(c.1)", color: category == c.0 ? ArtexTheme.accent : ArtexTheme.dim)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }

            SearchField(placeholder: "搜技能 / 工具 / 标签", text: $query)
                .padding(.horizontal, 16).padding(.bottom, 8)

            if list.isEmpty {
                EmptyHint(text: "无匹配技能")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(list) { s in
                            Button {
                                if let i = picked.firstIndex(where: { $0.id == s.id }) {
                                    picked.remove(at: i)
                                } else {
                                    picked.append(s)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: picked.contains(where: { $0.id == s.id })
                                          ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 13))
                                        .foregroundStyle(picked.contains(where: { $0.id == s.id })
                                                         ? ArtexTheme.accent : ArtexTheme.dim)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.n).font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(ArtexTheme.text)
                                        Text(s.d).font(.system(size: 10))
                                            .foregroundStyle(ArtexTheme.dim).lineLimit(2)
                                        HStack(spacing: 4) {
                                            Pill(text: s.cat, color: ArtexTheme.low)
                                            Pill(text: s.phase, color: ArtexTheme.dim)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                            }
                            Rectangle().fill(ArtexTheme.border).frame(height: 0.5)
                        }
                    }
                }
            }

            // 底部确认
            HStack {
                Text("已选 \(picked.count) 项").font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                Spacer()
                ArtexButton(title: "完成", compact: true) { dismiss() }
            }
            .padding(12)
            .background(ArtexTheme.surface)
            .overlay(Rectangle().frame(height: 0.5).foregroundStyle(ArtexTheme.border), alignment: .top)
        }
        .background(ArtexTheme.bg)
        .navigationTitle("选技能")
        .navigationBarTitleDisplayMode(.inline)
    }
}
