import SwiftUI

/// 发现页 —— 对齐 function/findings/page.tsx
/// Tabs: 全部发现 / 按任务分组 / 按资产 + 搜索 + 状态/类型/任务筛选 + 导出
struct FindingsView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var localStore = LocalTaskStore.shared

    @State private var tab = 0
    @State private var query = ""
    @State private var statusFilter = "全部状态"
    @State private var sevFilter = "按严重度"
    @State private var remoteFindings: [Finding] = []

    struct Item: Identifiable {
        var id: String
        var title: String
        var severity: String
        var asset: String
        var detail: String
        var cve: String?
        var task: String
        var ts: Date?
        var status: String
    }

    private var items: [Item] {
        var list: [Item] = []
        if store.offlineMode {
            for t in localStore.tasks {
                for f in t.findings {
                    list.append(Item(id: f.id.uuidString, title: f.title, severity: f.severity,
                                     asset: f.asset, detail: f.detail, cve: f.cveId,
                                     task: t.title, ts: f.ts, status: "open"))
                }
            }
        } else {
            list = remoteFindings.map { f in
                Item(id: String(f.id), title: f.displayTitle, severity: f.displaySeverity,
                     asset: f.asset ?? f.url ?? "-", detail: f.summary ?? f.description ?? "",
                     cve: f.cve, task: "#\(f.task_id ?? 0)", ts: f.created_at?.date,
                     status: f.status ?? "open")
            }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.title.lowercased().contains(q) || $0.asset.lowercased().contains(q) || $0.detail.lowercased().contains(q) }
        }
        if sevFilter != "按严重度" && sevFilter != "全部" {
            let target = sevFilter.lowercased()
            list = list.filter { $0.severity.lowercased() == target }
        }
        return list.sorted { ($0.ts ?? .distantPast) > ($1.ts ?? .distantPast) }
    }

    private var sevCounts: (c: Int, h: Int, m: Int, l: Int) {
        var c = 0, h = 0, m = 0, l = 0
        for i in items {
            switch i.severity.lowercased() {
            case "critical": c += 1
            case "high": h += 1
            case "medium": m += 1
            default: l += 1
            }
        }
        return (c, h, m, l)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageTitle("发现", sub: "\(items.count) 条漏洞", action: AnyView(
                ArtexButton(title: "导出", icon: "square.and.arrow.up", style: .outline, compact: true) {
                    exportCSV()
                }
            ))

            ArtexTabs(items: ["全部发现", "按任务分组", "按资产"], selection: $tab)

            VStack(spacing: 8) {
                SearchField(placeholder: "检索漏洞内容", text: $query)
                HStack(spacing: 8) {
                    FilterMenu(label: "状态", options: ["全部状态", "open", "fixed", "ignored"], selection: $statusFilter)
                    FilterMenu(label: "按严重度", options: ["按严重度", "全部", "critical", "high", "medium", "low"], selection: $sevFilter)
                    Spacer()
                }
                // 严重度汇总
                HStack(spacing: 10) {
                    sevChip("严重", sevCounts.c, ArtexTheme.critical)
                    sevChip("高危", sevCounts.h, ArtexTheme.high)
                    sevChip("中危", sevCounts.m, ArtexTheme.medium)
                    sevChip("低危", sevCounts.l, ArtexTheme.low)
                    Spacer()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            if items.isEmpty {
                EmptyHint(text: "暂无发现。运行任务后，Agent 报告的漏洞会出现在这里。")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if tab == 0 {
                            ForEach(items) { i in findingCard(i) }
                        } else if tab == 1 {
                            ForEach(groupedByTask, id: \.0) { group in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(group.0).font(.system(size: 11, weight: .semibold)).foregroundStyle(ArtexTheme.dim)
                                    ForEach(group.1) { i in findingCard(i) }
                                }
                            }
                        } else {
                            ForEach(groupedByAsset, id: \.0) { group in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(group.0).font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.accent)
                                    ForEach(group.1) { i in findingCard(i) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 20)
                }
            }
        }
        .background(ArtexTheme.bg)
        .task { await load() }
    }

    private var groupedByTask: [(String, [Item])] {
        Dictionary(grouping: items, by: { $0.task }).map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }
    private var groupedByAsset: [(String, [Item])] {
        Dictionary(grouping: items, by: { $0.asset }).map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    private func sevChip(_ label: String, _ n: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(label) \(n)").font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
        }
    }

    private func findingCard(_ i: Item) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Pill(text: i.severity.uppercased(), color: ArtexTheme.severityColor(i.severity))
                if let cve = i.cve, !cve.isEmpty { Pill(text: cve, color: ArtexTheme.low) }
                Spacer()
                Text(fmtRel(i.ts)).font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
            }
            Text(i.title).font(.system(size: 12, weight: .medium)).foregroundStyle(ArtexTheme.text).lineLimit(2)
            Text(i.asset).font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.accent).lineLimit(1)
            if !i.detail.isEmpty {
                Text(i.detail).font(.system(size: 10)).foregroundStyle(ArtexTheme.dim).lineLimit(3)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArtexTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radius).stroke(ArtexTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
    }

    private func exportCSV() {
        var csv = "严重度,标题,资产,CVE,任务,详情\n"
        for i in items {
            let d = i.detail.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(i.severity),\(i.title),\(i.asset),\(i.cve ?? ""),\(i.task),\"\(d)\"\n"
        }
        UIPasteboard.general.string = csv
    }

    private func load() async {
        guard !store.offlineMode else { return }
        remoteFindings = (try? await FindingAPI.list()) ?? []
    }
}

/// 资产页 —— 对齐 function/assets/page.tsx
/// 表头：企业 / 资产数 / 资产范围 / 操作 + 刷新 + 新增企业
struct AssetsView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var localStore = LocalTaskStore.shared
    @State private var query = ""
    @State private var remoteAssets: [Asset] = []

    private var groups: [(name: String, count: Int, values: [String])] {
        var map: [String: Set<String>] = [:]
        if store.offlineMode {
            for t in localStore.tasks {
                for a in t.assets { map[t.title, default: []].insert(a) }
            }
        } else {
            for a in remoteAssets {
                map[a.company ?? "未归类", default: []].insert(a.displayValue)
            }
        }
        var list = map.map { (name: $0.key, count: $0.value.count, values: Array($0.value).sorted()) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.name.lowercased().contains(q) || $0.values.joined(separator: " ").lowercased().contains(q) }
        }
        return list.sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageTitle("资产", sub: "跨任务共享的资产图", action: AnyView(
                ArtexButton(title: "刷新", icon: "arrow.clockwise", style: .outline, compact: true) {
                    Task { await load() }
                }
            ))

            VStack(spacing: 8) {
                SearchField(placeholder: "搜索企业名称或资产范围", text: $query)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            if groups.isEmpty {
                EmptyHint(text: "暂无资产。任务扫到的主机、端口、URL 会汇总到这里。")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(groups, id: \.name) { g in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(g.name).font(.system(size: 12, weight: .medium)).foregroundStyle(ArtexTheme.text)
                                    Spacer()
                                    Pill(text: "\(g.count) 项", color: ArtexTheme.accent)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(g.values.prefix(8), id: \.self) { v in
                                        HStack(spacing: 6) {
                                            Circle().fill(ArtexTheme.assetColor(assetKind(v))).frame(width: 4, height: 4)
                                            Text(v).font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(ArtexTheme.dim).lineLimit(1)
                                            Spacer()
                                        }
                                    }
                                    if g.values.count > 8 {
                                        Text("还有 \(g.values.count - 8) 项…")
                                            .font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
                                    }
                                }
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ArtexTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radius).stroke(ArtexTheme.border, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 20)
                }
            }
        }
        .background(ArtexTheme.bg)
        .task { await load() }
    }

    private func assetKind(_ v: String) -> String {
        if v.contains("://") { return "app" }
        if v.contains(":") { return "service" }
        return "subdomain"
    }

    private func load() async {
        guard !store.offlineMode else { return }
        remoteAssets = (try? await AssetAPI.list()) ?? []
    }
}
