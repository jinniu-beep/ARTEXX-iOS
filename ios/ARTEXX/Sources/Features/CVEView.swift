import SwiftUI

struct CVEView: View {
    @State private var query = ""
    @State private var severity = ""
    @State private var vendor = ""
    @State private var results: [CVERow] = []
    @State private var searching = false
    @State private var detail: CVERow?
    @State private var stats = (total: 0, critical: 0, high: 0, medium: 0, vendors: 0)
    @State private var vendors: [(String, Int)] = []
    @State private var minScore: Double = 4.0
    @State private var didInit = false

    private let severities = ["", "critical", "high", "medium"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                HStack(spacing: 8) {
                    Text("CVSS ≥ " + String(Int(minScore)))
                        .font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                    Slider(value: $minScore, in: 4...10, step: 0.5) { _ in runSearch() }
                }
                .padding(.horizontal, 14).padding(.bottom, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(severities, id: \.self) { s in
                            Button { severity = s; runSearch() } label: {
                                Pill(text: s.isEmpty ? "全部等级" : s.uppercased(),
                                     color: severity == s ? ArtexTheme.accent : ArtexTheme.dim)
                            }
                        }
                        Menu {
                            Button("全部厂商") { vendor = ""; runSearch() }
                            ForEach(vendors.prefix(40), id: \.0) { v in
                                Button("\(v.0) (\(v.1))") { vendor = v.0; runSearch() }
                            }
                        } label: {
                            Pill(text: vendor.isEmpty ? "全部厂商" : vendor, color: vendor.isEmpty ? ArtexTheme.dim : ArtexTheme.low)
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                }

                if searching {
                    ProgressView().tint(ArtexTheme.accent).padding(.top, 40)
                    Spacer()
                } else if results.isEmpty {
                    EmptyHint(text: didInit ? "没有匹配的 CVE，换个关键词试试" : "加载中…")
                    Spacer()
                } else {
                    List {
                        ForEach(results) { c in
                            Button { detail = c } label: { row(c) }
                                .listRowBackground(ArtexTheme.surface)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(ArtexTheme.bg)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "CVE 编号 / 产品 / 关键词")
            .onSubmit(of: .search) { runSearch() }
            .onChange(of: query) { _ in runSearch() }
            .navigationTitle("CVE 知识库")
            .sheet(item: $detail) { c in CVEDetailView(row: c) }
            .task {
                stats = CVEDatabase.shared.stats()
                vendors = CVEDatabase.shared.vendors(limit: 80)
                runSearch()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            miniStat("总条目", "\(stats.total)", ArtexTheme.accent)
            miniStat("严重", "\(stats.critical)", ArtexTheme.critical)
            miniStat("高危", "\(stats.high)", ArtexTheme.high)
            miniStat("命中", "\(results.count)", ArtexTheme.low)
        }
        .padding(.horizontal, 14).padding(.top, 6)
    }

    private func miniStat(_ l: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(l).font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
            Text(v).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(c)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ c: CVERow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Pill(text: c.id, color: ArtexTheme.severityColor(c.severity))
                Pill(text: String(Int(c.score)) + "." + String(Int((c.score * 10).rounded()) % 10), color: ArtexTheme.severityColor(c.severity))
                if !c.cwe.isEmpty { Pill(text: c.cwe, color: ArtexTheme.dim) }
                Spacer()
                Text(c.published).font(.system(size: 9, design: .monospaced)).foregroundStyle(ArtexTheme.dim)
            }
            Text(c.title).font(.system(size: 12)).foregroundStyle(ArtexTheme.text).lineLimit(2)
        }
        .padding(.vertical, 3)
    }

    private func runSearch() {
        searching = true
        let q = query, sev = severity, ven = vendor
        DispatchQueue.global(qos: .userInitiated).async {
            let rows = CVEDatabase.shared.search(q, severity: sev.isEmpty ? nil : sev,
                                                vendor: ven.isEmpty ? nil : ven,
                                                minScore: minScore, limit: 200)
            DispatchQueue.main.async {
                results = rows
                searching = false
                didInit = true
            }
        }
    }
}

struct CVEDetailView: View {
    let row: CVERow
    @Environment(\.dismiss) var dismiss
    @State private var body_: (desc: String, refs: Int)?
    @State private var relatedSkills: [Skill] = []
    @State private var guide = CVEPlaybook.empty

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Pill(text: row.id, color: ArtexTheme.severityColor(row.severity))
                        Pill(text: row.severity.uppercased(), color: ArtexTheme.severityColor(row.severity))
                        Pill(text: "CVSS " + String(Int(row.score)) + "." + String(Int((row.score * 10).rounded()) % 10), color: ArtexTheme.severityColor(row.severity))
                        if !row.cwe.isEmpty { Pill(text: row.cwe, color: ArtexTheme.low) }
                    }

                    Text(row.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(ArtexTheme.text)

                    if let d = body_?.desc, !d.isEmpty {
                        Card(title: "漏洞描述") {
                            Text(d).font(.system(size: 12)).foregroundStyle(ArtexTheme.dim)
                        }
                    }

                    Card(title: "① 针对什么") {
                        VStack(alignment: .leading, spacing: 6) {
                            kv("厂商/产品", row.vendor)
                            kv("CWE", row.cwe.isEmpty ? "-" : row.cwe)
                            kv("披露日期", row.published)
                            kv("影响面", guide.target)
                        }
                    }

                    Card(title: "② 怎么使用（利用前提）") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(guide.prereqs, id: \.self) { t in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•").foregroundStyle(ArtexTheme.accent)
                                    Text(t).font(.system(size: 12)).foregroundStyle(ArtexTheme.text)
                                }
                            }
                        }
                    }

                    Card(title: "③ 怎么实现（验证载荷）") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(guide.payloads, id: \.self) { p in
                                HStack(alignment: .top) {
                                    Text(p).font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.accent)
                                    Spacer(minLength: 6)
                                    Button { UIPasteboard.general.string = p } label: {
                                        Image(systemName: "doc.on.doc").font(.system(size: 11))
                                    }
                                }
                                Divider().background(ArtexTheme.border)
                            }
                        }
                    }

                    Card(title: "④ 真实案例") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(guide.caseStudy).font(.system(size: 12)).foregroundStyle(ArtexTheme.text)
                            if !guide.references.isEmpty {
                                ForEach(guide.references, id: \.self) { r in
                                    Link(r, destination: URL(string: r) ?? URL(string: "https://nvd.nist.gov")!)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(ArtexTheme.low)
                                }
                            }
                        }
                    }

                    if !relatedSkills.isEmpty {
                        Card(title: "配套技能") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(relatedSkills) { s in
                                    HStack {
                                        Text(s.n).font(.system(size: 12)).foregroundStyle(ArtexTheme.text)
                                        Spacer()
                                        Pill(text: s.cat, color: ArtexTheme.low)
                                    }
                                }
                            }
                        }
                    }
                }.padding(16)
            }
            .background(ArtexTheme.bg)
            .navigationTitle(row.id)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .task {
                body_ = CVEDatabase.shared.detail(row.id)
                relatedSkills = row.skills.compactMap { SkillLibrary.shared.byID($0) }
                guide = CVEPlaybook.build(row: row, desc: body_?.desc ?? row.title)
            }
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 11)).foregroundStyle(ArtexTheme.dim).frame(width: 78, alignment: .leading)
            Text(v.isEmpty ? "-" : v).font(.system(size: 12, design: .monospaced)).foregroundStyle(ArtexTheme.text)
        }
    }
}
