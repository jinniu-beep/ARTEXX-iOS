import SwiftUI

/// 技能库 —— 严格对齐 system/skills/page.tsx
/// 结构：顶部标题 + 左树右详情 + 总览指标卡 + 调用排行 / 最近调用 / 未使用
struct SkillLibraryView: View {
    @ObservedObject private var lib = SkillLibrary.shared
    @State private var selected: Skill?
    @State private var detailTab = 0
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var showPlaybook = false
    @State private var mode: Mode = .list

    enum Mode { case list, overview }

    private var filtered: [Skill] { lib.filtered(category: nil, query: query) }
    private var grouped: [(String, [Skill])] {
        Dictionary(grouping: filtered, by: { $0.cat })
            .map { ($0.key, $0.value.sorted { $0.n < $1.n }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── 顶栏（对齐 border-b px-4 py-2.5）──
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Skill").font(.system(size: 13, weight: .semibold)).foregroundStyle(ArtexTheme.text)
                    Text("技能库 · \(lib.all.count) 条 · 按 Agent 授权可见")
                        .font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                }
                Spacer()
                if !lib.selected.isEmpty {
                    Button { showPlaybook = true } label: {
                        Pill(text: "编排 \(lib.selected.count)", color: ArtexTheme.accent)
                    }
                }
                Button {
                    mode = mode == .list ? .overview : .list
                } label: {
                    Image(systemName: mode == .list ? "chart.bar" : "list.bullet")
                        .font(.system(size: 13)).foregroundStyle(ArtexTheme.dim)
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .overlay(Rectangle().frame(height: 0.5).foregroundStyle(ArtexTheme.border), alignment: .bottom)

            if mode == .overview {
                overview
            } else {
                // ── 左树 + 右详情 ──
                HStack(spacing: 0) {
                    treePanel
                    Rectangle().fill(ArtexTheme.border).frame(width: 0.5)
                    detailPanel
                }
            }
        }
        .background(ArtexTheme.bg)
        .sheet(isPresented: $showPlaybook) { NavigationStack { PlaybookView() } }
    }

    // MARK: - 左树
    private var treePanel: some View {
        VStack(spacing: 0) {
            SearchField(placeholder: "搜索技能", text: $query)
                .padding(8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(grouped, id: \.0) { group in
                        let isOpen = expanded.contains(group.0)
                        // 分类节点
                        Button {
                            if isOpen { expanded.remove(group.0) } else { expanded.insert(group.0) }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(ArtexTheme.dim)
                                    .frame(width: 10)
                                Image(systemName: isOpen ? "folder.fill" : "folder")
                                    .font(.system(size: 11))
                                    .foregroundStyle(ArtexTheme.accent)
                                Text(group.0)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ArtexTheme.text)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(group.1.count)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(ArtexTheme.dim)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(isOpen ? ArtexTheme.surfaceHi.opacity(0.4) : Color.clear)
                        }

                        if isOpen {
                            ForEach(group.1) { s in
                                Button { selected = s } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 9))
                                            .foregroundStyle(ArtexTheme.dim)
                                            .padding(.leading, 14)
                                        Text(s.n)
                                            .font(.system(size: 11))
                                            .foregroundStyle(selected?.id == s.id ? ArtexTheme.text : ArtexTheme.dim)
                                            .lineLimit(1)
                                        Spacer()
                                        if lib.selected.contains(s.id) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(ArtexTheme.ok)
                                        }
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(selected?.id == s.id ? ArtexTheme.surfaceHi : Color.clear)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 4).padding(.bottom, 16)
            }
        }
        .frame(width: 168)
    }

    // MARK: - 右详情
    private var detailPanel: some View {
        Group {
            if let s = selected {
                skillDetail(s)
            } else {
                overview
            }
        }
    }

    private func skillDetail(_ s: Skill) -> some View {
        VStack(spacing: 0) {
            // 标题
            VStack(alignment: .leading, spacing: 3) {
                Text(s.n).font(.system(size: 15, weight: .semibold)).foregroundStyle(ArtexTheme.text)
                HStack(spacing: 4) {
                    Pill(text: s.cat, color: ArtexTheme.low)
                    Pill(text: s.phase, color: ArtexTheme.dim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            ArtexTabs(items: ["基本信息", "关联 CVE", "可见性"], selection: $detailTab)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if detailTab == 0 {
                        // 基本信息：名称/描述/命令/工具/标签
                        VStack(alignment: .leading, spacing: 10) {
                            detailField("名称", s.id)
                            detailBlock("描述", s.d)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("命令").font(.system(size: 10, weight: .medium)).foregroundStyle(ArtexTheme.dim)
                                ForEach(s.cmds, id: \.self) { c in
                                    HStack(alignment: .top) {
                                        Text(c)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(ArtexTheme.accent)
                                        Spacer(minLength: 4)
                                        Button { UIPasteboard.general.string = c } label: {
                                            Image(systemName: "doc.on.doc").font(.system(size: 9))
                                                .foregroundStyle(ArtexTheme.dim)
                                        }
                                    }
                                    .padding(7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(ArtexTheme.bg)
                                    .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
                                }
                            }
                            detailField("工具", s.tools.joined(separator: " · "))
                            detailField("标签", s.tags.joined(separator: " · "))
                        }
                    } else if detailTab == 1 {
                        // 关联 CVE
                        let related = CVEDatabase.shared.bySkill(s.id, limit: 20)
                        if related.isEmpty {
                            Text("该技能暂无关联 CVE").font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(related) { c in
                                    HStack(spacing: 6) {
                                        Pill(text: c.id, color: ArtexTheme.severityColor(c.severity))
                                        Text(c.title).font(.system(size: 10))
                                            .foregroundStyle(ArtexTheme.dim).lineLimit(1)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    } else {
                        // 可见性
                        VStack(alignment: .leading, spacing: 8) {
                            Text("按 Agent 授权可见").font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                            ForEach(["planner", "worker", "mainagent", "goals", "retester"], id: \.self) { a in
                                HStack {
                                    Text(a).font(.system(size: 11, design: .monospaced)).foregroundStyle(ArtexTheme.text)
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12)).foregroundStyle(ArtexTheme.ok)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
                .padding(12)
            }

            // 底部：加入编排
            HStack {
                Button {
                    lib.toggle(s.id)
                } label: {
                    Text(lib.selected.contains(s.id) ? "从编排中移出" : "加入编排")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(lib.selected.contains(s.id) ? ArtexTheme.surfaceHi : ArtexTheme.text)
                        .foregroundStyle(lib.selected.contains(s.id) ? ArtexTheme.text : ArtexTheme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
                }
            }
            .padding(10)
            .overlay(Rectangle().frame(height: 0.5).foregroundStyle(ArtexTheme.border), alignment: .top)
        }
    }

    // MARK: - 总览（对齐技能库总览）
    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("技能库总览").font(.system(size: 14, weight: .semibold)).foregroundStyle(ArtexTheme.text)
                    Text("选择左侧的 Skill 查看详情与调用记录，或从这里快速了解整体使用情况。")
                        .font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                }

                // 指标卡（grid-cols-2 sm:grid-cols-4）
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    metricCard("\(lib.all.count)", "Skill 总数", "13 大类覆盖")
                    metricCard("\(lib.categories.count)", "分类", "信息收集 → 后复盘")
                    metricCard("\(lib.selected.count)", "已选编排", lib.selected.isEmpty ? "未选择" : "待生成作战序列")
                    metricCard("\(lib.all.filter { !$0.cmds.isEmpty }.count)", "带命令", "可直接执行")
                }

                // 调用排行（本地无调用记录，用技能条数代替展示）
                VStack(alignment: .leading, spacing: 6) {
                    Text("分类分布").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                    VStack(spacing: 5) {
                        ForEach(lib.categories.prefix(8), id: \.0) { c in
                            HStack(spacing: 8) {
                                Text(c.0).font(.system(size: 10)).foregroundStyle(ArtexTheme.text)
                                    .frame(width: 72, alignment: .leading)
                                ArtexProgress(value: Double(c.1) / Double(max(1, lib.all.count)) * 4, tint: ArtexTheme.accent)
                                    .frame(height: 5)
                                Text("\(c.1)").font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(ArtexTheme.dim).frame(width: 24, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(12)
                .background(ArtexTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radius).stroke(ArtexTheme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
            }
            .padding(16)
        }
    }

    private func metricCard(_ value: String, _ label: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .semibold)).foregroundStyle(ArtexTheme.text).monospacedDigit()
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(ArtexTheme.text)
            Text(hint).font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(ArtexTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radius).stroke(ArtexTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
    }

    private func detailField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(ArtexTheme.dim)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ArtexTheme.text)
        }
    }

    private func detailBlock(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(ArtexTheme.dim)
            Text(value).font(.system(size: 11)).foregroundStyle(ArtexTheme.text)
        }
    }
}
