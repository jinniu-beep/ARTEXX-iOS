import SwiftUI

// MARK: - 工具执行（对齐 function/commands/page.tsx）
// 表头：时间 / 任务 / Worker / 工具 / 输入 / 状态
struct CommandsView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var localStore = LocalTaskStore.shared
    @State private var query = ""
    @State private var remote: [CommandRecord] = []

    struct Item: Identifiable {
        var id: String
        var ts: Date?
        var task: String
        var worker: String
        var tool: String
        var input: String
        var status: String
    }

    private var items: [Item] {
        var list: [Item] = []
        if store.offlineMode {
            for t in localStore.tasks {
                for s in t.steps where s.role == "tool" {
                    list.append(Item(id: s.id.uuidString, ts: s.ts, task: t.title,
                                     worker: "worker", tool: s.title,
                                     input: s.detail, status: "done"))
                }
            }
        } else {
            list = remote.map {
                Item(id: String($0.id), ts: $0.created_at?.date, task: "#\($0.task_id ?? 0)",
                     worker: "worker", tool: $0.tool ?? "-",
                     input: $0.command ?? "", status: $0.status ?? "-")
            }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.tool.lowercased().contains(q) || $0.input.lowercased().contains(q) }
        }
        return list.sorted { ($0.ts ?? .distantPast) > ($1.ts ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageTitle("工具执行", sub: "\(items.count) 次调用")
            VStack(spacing: 8) {
                SearchField(placeholder: "搜索工具 / 参数...", text: $query)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            if items.isEmpty {
                EmptyHint(text: "暂无工具执行记录")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { i in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Pill(text: i.tool, color: ArtexTheme.accent)
                                    Pill(text: i.status, color: ArtexTheme.ok)
                                    Spacer()
                                    Text(fmtRel(i.ts)).font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
                                }
                                Text(i.input)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(ArtexTheme.dim)
                                    .lineLimit(3)
                                Text(i.task).font(.system(size: 9)).foregroundStyle(ArtexTheme.dim.opacity(0.7))
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Rectangle().fill(ArtexTheme.border).frame(height: 0.5)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .background(ArtexTheme.bg)
        .task { await load() }
    }

    private func load() async {
        guard !store.offlineMode else { return }
        remote = (try? await OpsAPI.commands()) ?? []
    }
}

// MARK: - 流量（对齐 function/traffic/page.tsx）
// Tabs: 请求/响应 + 方法/状态码筛选 + host/URL 搜索
struct TrafficView: View {
    @EnvironmentObject var store: AppStore
    @State private var tab = 0
    @State private var methodFilter = "全部方法"
    @State private var query = ""
    @State private var hosts: [String: AnyJSON] = [:]

    var body: some View {
        VStack(spacing: 0) {
            PageTitle("流量", sub: "MITM 录制 · \(hostCount) 个 host")
            ArtexTabs(items: ["请求 Request", "响应 Response"], selection: $tab)

            VStack(spacing: 8) {
                SearchField(placeholder: "搜索全部（URL / 方法 / 类型 / 状态码…）", text: $query)
                HStack(spacing: 8) {
                    FilterMenu(label: "全部方法", options: ["全部方法", "GET", "POST", "PUT", "DELETE"], selection: $methodFilter)
                    FilterMenu(label: "全部状态码", options: ["全部状态码", "2xx", "3xx", "4xx", "5xx"], selection: $methodFilter)
                    Spacer()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            if store.offlineMode || hosts.isEmpty {
                EmptyHint(text: "暂无流量记录\n流量录制需要连接 ARTEXX 服务端的 MITM 代理")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(hosts.keys.sorted(), id: \.self) { h in
                            HStack {
                                Text(h).font(.system(size: 11, design: .monospaced)).foregroundStyle(ArtexTheme.text)
                                Spacer()
                                Text(hosts[h]?.display ?? "").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            Rectangle().fill(ArtexTheme.border).frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .background(ArtexTheme.bg)
        .task {
            guard !store.offlineMode else { return }
            hosts = (try? await OpsAPI.trafficHosts()) ?? [:]
        }
    }

    private var hostCount: Int { hosts.count }
}

// MARK: - 工作空间（对齐 function/workspace/page.tsx）
struct WorkspaceView: View {
    @EnvironmentObject var store: AppStore
    @State private var path = ""
    @State private var content = ""
    @State private var files: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            PageTitle("工作空间", sub: "Agent 共享的文件目录")
            VStack(spacing: 8) {
                SearchField(placeholder: "路径，留空为根目录", text: $path)
                HStack(spacing: 8) {
                    ArtexButton(title: "打开", icon: "folder", style: .outline, compact: true) {
                        Task { await open() }
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            if store.offlineMode {
                let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("workspace")
                let items = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
                if items.isEmpty {
                    EmptyHint(text: "本地工作空间为空\n\(dir.path)")
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(items, id: \.self) { f in
                                HStack(spacing: 8) {
                                    Image(systemName: "doc").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                                    Text(f).font(.system(size: 11, design: .monospaced)).foregroundStyle(ArtexTheme.text)
                                    Spacer()
                                }
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                Rectangle().fill(ArtexTheme.border).frame(height: 0.5)
                            }
                        }
                    }
                }
            } else {
                ScrollView {
                    Text(content.isEmpty ? "（空）" : content)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ArtexTheme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
        }
        .background(ArtexTheme.bg)
    }

    private func open() async {
        guard !store.offlineMode else { return }
        content = (try? await WorkspaceAPI.read(path)) ?? ""
    }
}

// MARK: - LLM 录制（对齐 function/llm-records/page.tsx）
struct LLMRecordsView: View {
    @EnvironmentObject var store: AppStore
    @State private var records: [String: AnyJSON] = [:]

    var body: some View {
        VStack(spacing: 0) {
            PageTitle("LLM 录制", sub: "逐次调用记录")
            if store.offlineMode || records.isEmpty {
                EmptyHint(text: "暂无录制记录\nLLM 录制需要连接 ARTEXX 服务端")
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(records.keys.sorted(), id: \.self) { k in
                            FieldRow(label: k, value: records[k]?.display ?? "-")
                        }
                    }.padding(16)
                }
            }
        }
        .background(ArtexTheme.bg)
    }
}
