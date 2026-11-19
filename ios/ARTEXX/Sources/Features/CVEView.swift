import SwiftUI

/// CVE 知识库 —— 沿用 skills 页的「左树 + 右详情 + 总览」结构
struct CVEView: View {
    @ObservedObject private var db = CVEDatabase.shared
    @State private var query = ""
    @State private var severity = ""
    @State private var vendor = ""
    @State private var minScore: Double = 4.0
    @State private var results: [CVERow] = []
    @State private var selected: CVERow?
    @State private var detailTab = 0
    @State private var mode: Mode = .list
    @State private var searching = false
    @State private var stats = (total: 0, critical: 0, high: 0, medium: 0, vendors: 0)
    @State private var vendors: [(String, Int)] = []

    enum Mode { case list, overview }

    var body: some View {
        VStack(spacing: 0) {
            // ── 顶栏 ──
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("CVE").font(.system(size: 13, weight: .semibold)).foregroundStyle(ArtexTheme.text)
                    Text("CVE 知识库 · \(db.totalRows) 条 · 2023-01 ~ 2026-11")
                        .font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                }
                Spacer()
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
                HStack(spacing: 0) {
                    listPanel
                    Rectangle().fill(ArtexTheme.border).frame(width: 0.5)
                    detailPanel
                }
            }
        }
        .background(ArtexTheme.bg)
        .task {
            stats = db.stats()
            vendors = db.vendors(limit: 60)
            runSearch()
        }
        .onChange(of: db.phase) { _ in
            stats = db.stats()
            vendors = db.vendors(limit: 60)
            runSearch()
        }
    }

    // MARK: - 左列表
    private var listPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                SearchField(placeholder: "CVE / 产品 / 关键词", text: $query)
                    .onSubmit { runSearch() }
                HStack(spacing: 6) {
                    FilterMenu(label: "等级", options: ["全部等级", "critical", "high", "medium"], selection: $severity)
                    FilterMenu(label: "厂商", options: ["全部厂商"] + vendors.prefix(20).map { $0.0 }, selection: $vendor)
                }
                HStack(spacing: 6) {
                    Text("CVSS ≥").font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
                    Slider(value: $minScore, in: 4...10, step: 0.5) { _ in runSearch() }
                        .scaleEffect(0.85)
                    Text(String(Int(minScore))).font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(ArtexTheme.accent).frame(width: 16)
                }
            }
            .padding(8)

            if searching {
                ProgressView().tint(ArtexTheme.accent).padding(.top, 20)
                Spacer()
            } else if results.isEmpty {
                Text(db.phase == .preparing ? "知识库解压中…" : "无匹配结果")
                    .font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                    .padding(.top, 20)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(results) { c in
                            Button { selected = c } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(c.id)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(ArtexTheme.severityColor(c.severity))
                                        Spacer()
                                        Text(String(Int(c.score)))
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(ArtexTheme.severityColor(c.severity))
                                    }
                                    Text(c.title)
                                        .font(.system(size: 9))
                                        .foregroundStyle(selected?.id == c.id ? ArtexTheme.text : ArtexTheme.dim)
                                        .lineLimit(2)
                                }
                                .padding(.horizontal, 7).padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected?.id == c.id ? ArtexTheme.surfaceHi : Color.clear)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 168)
    }

    // MARK: - 右详情（四段式）
    private var detailPanel: some View {
        Group {
            if let c = selected {
                cveDetail(c)
            } else {
                overview
            }
        }
    }

    private func cveDetail(_ c: CVERow) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.id).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ArtexTheme.severityColor(c.severity))
                HStack(spacing: 4) {
                    Pill(text: c.severity.uppercased(), color: ArtexTheme.severityColor(c.severity))
                    Pill(text: "CVSS " + String(Int(c.score)), color: ArtexTheme.severityColor(c.severity))
                    if !c.cwe.isEmpty { Pill(text: c.cwe, color: ArtexTheme.low) }
                    if c.hasExploit { Pill(text: "EXP #" + c.exploitId, color: ArtexTheme.ok) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            ArtexTabs(items: ["针对什么", "怎么使用", "怎么实现", "真实案例"], selection: $detailTab)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if detailTab == 0 {
                        // ① 针对什么
                        detailField("厂商", c.vendor)
                        detailField("CWE", c.cwe.isEmpty ? "-" : c.cwe)
                        detailField("披露日期", c.published)
                        if !c.ranges.isEmpty { detailField("影响版本", c.ranges) }
                        if !c.vector.isEmpty { detailField("CVSS 向量", c.vector) }
                        if let g = db.guidance(c.id) {
                            detailField("漏洞类型", g.type)
                        }
                        if let d = db.detail(c.id)?.desc, !d.isEmpty {
                            detailBlock("描述", d)
                        }
                    } else if detailTab == 1 {
                        // ② 怎么使用
                        if let g = db.guidance(c.id) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(g.prereq.enumerated()), id: \.offset) { i, t in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("\(i + 1).").font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(ArtexTheme.accent)
                                        Text(t).font(.system(size: 11)).foregroundStyle(ArtexTheme.text)
                                    }
                                }
                            }
                        }
                    } else if detailTab == 2 {
                        // ③ 怎么实现
                        if let g = db.guidance(c.id) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(g.payload.enumerated()), id: \.offset) { _, p in
                                    HStack(alignment: .top) {
                                        Text(p).font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(ArtexTheme.accent)
                                        Spacer(minLength: 4)
                                        Button { UIPasteboard.general.string = p } label: {
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
                        }
                    } else {
                        // ④ 真实案例
                        let links = db.references(c.id)
                        VStack(alignment: .leading, spacing: 6) {
                            if c.hasExploit {
                                Text("ExploitDB #\(c.exploitId) 有公开利用")
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(ArtexTheme.ok)
                            } else {
                                Text("暂无公开 EXP，按厂商公告复现").font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                            }
                            ForEach(Array(links.prefix(6).enumerated()), id: \.offset) { _, l in
                                Link(l, destination: URL(string: l) ?? URL(string: "https://nvd.nist.gov")!)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(ArtexTheme.accent)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    // MARK: - 总览
    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CVE 库总览").font(.system(size: 14, weight: .semibold)).foregroundStyle(ArtexTheme.text)
                    Text("选择左侧条目查看四段式攻击指引，或从这里了解整体分布。")
                        .font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    metricCard("\(stats.total)", "CVE 总数", "2023-01 ~ 2026-11", ArtexTheme.accent)
                    metricCard("\(stats.critical)", "严重", "CVSS ≥ 9.0", ArtexTheme.critical)
                    metricCard("\(stats.high)", "高危", "7.0 ~ 8.9", ArtexTheme.high)
                    metricCard("\(stats.vendors)", "厂商", "已归类", ArtexTheme.low)
                }

                // 厂商分布
                VStack(alignment: .leading, spacing: 6) {
                    Text("厂商分布 Top").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                    VStack(spacing: 5) {
                        ForEach(vendors.prefix(8), id: \.0) { v in
                            HStack(spacing: 8) {
                                Text(v.0).font(.system(size: 10)).foregroundStyle(ArtexTheme.text)
                                    .frame(width: 68, alignment: .leading).lineLimit(1)
                                ArtexProgress(value: Double(v.1) / Double(max(1, stats.total)) * 5, tint: ArtexTheme.accent)
                                    .frame(height: 5)
                                Text("\(v.1)").font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(ArtexTheme.dim).frame(width: 42, alignment: .trailing)
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

    private func metricCard(_ value: String, _ label: String, _ hint: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint).monospacedDigit()
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
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ArtexTheme.text)
        }
    }

    private func detailBlock(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(ArtexTheme.dim)
            Text(value).font(.system(size: 10)).foregroundStyle(ArtexTheme.text)
        }
    }

    private func runSearch() {
        searching = true
        let q = query
        let sev = severity == "全部等级" ? "" : severity
        let ven = vendor == "全部厂商" ? "" : vendor
        let ms = minScore
        DispatchQueue.global(qos: .userInitiated).async {
            let rows = CVEDatabase.shared.search(q, severity: sev.isEmpty ? nil : sev,
                                                vendor: ven.isEmpty ? nil : ven,
                                                minScore: ms, limit: 200)
            DispatchQueue.main.async {
                results = rows
                searching = false
            }
        }
    }
}
