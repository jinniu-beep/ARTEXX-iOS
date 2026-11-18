import SwiftUI

/// 启动自检页：把「为什么卡住」变成可见的诊断信息。
struct DiagnosticsView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var cve = CVEDatabase.shared
    @State private var reachable: Bool?
    @State private var probeMs: Int?
    @State private var detail = ""
    @State private var busy = false

    var body: some View {
        List {
            Section("内置知识库") {
                row("状态", phaseText, phaseColor)
                row("CVE 条数", cve.ready ? "\(cve.totalRows)" : "未就绪", cve.ready ? ArtexTheme.ok : ArtexTheme.dim)
                row("技能条数", "\(SkillLibrary.shared.all.count)", ArtexTheme.accent)
                row("解压路径", dbPath, ArtexTheme.dim)
                row("文件大小", fileSize, ArtexTheme.dim)
            }

            Section("服务器") {
                row("地址", store.config.effectiveBase, ArtexTheme.text)
                row("Token", store.config.token.isEmpty ? "未登录" : "已设置（\(store.config.token.count) 字符）",
                    store.config.token.isEmpty ? ArtexTheme.dim : ArtexTheme.ok)
                row("连通性", reachable == nil ? "未检测" : (reachable! ? "可达" : "不可达"),
                    reachable == nil ? ArtexTheme.dim : (reachable! ? ArtexTheme.ok : ArtexTheme.critical))
                if let ms = probeMs { row("耗时", "\(ms) ms", ArtexTheme.dim) }
                Button(busy ? "检测中…" : "重新检测") { Task { await probe() } }
                    .disabled(busy)
            }

            Section("诊断日志") {
                if detail.isEmpty {
                    Text("点上方「重新检测」获取详情").font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                } else {
                    Text(detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.text)
                        .textSelection(.enabled)
                }
            }

            Section {
                Button("重新解压知识库") {
                    try? FileManager.default.removeItem(atPath: dbPath)
                    CVEDatabase.shared.bootstrap()
                }
                .foregroundStyle(ArtexTheme.high)
                Button("强制重新登录") { store.logout() }
                    .foregroundStyle(ArtexTheme.critical)
            } footer: {
                Text("解压失败或数据损坏时，用「重新解压」会删掉本地库并从 App 包内重新展开。")
                    .font(.system(size: 10))
            }
        }
        .scrollContentBackground(.hidden)
        .background(ArtexTheme.bg)
        .navigationTitle("自检")
        .task { await probe() }
    }

    private var phaseText: String {
        switch cve.phase {
        case .idle: return "空闲"
        case .preparing: return "解压中"
        case .ready: return "就绪"
        case .failed(let m): return "失败：" + m
        }
    }

    private var phaseColor: Color {
        switch cve.phase {
        case .ready: return ArtexTheme.ok
        case .failed: return ArtexTheme.critical
        case .preparing: return ArtexTheme.medium
        case .idle: return ArtexTheme.dim
        }
    }

    private var dbPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ARTEXX/cve.sqlite").path
    }

    private var fileSize: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath),
              let n = attrs[.size] as? NSNumber else { return "无文件" }
        return String(format: "%.1f MB", Double(n.intValue) / 1048576)
    }

    private func row(_ k: String, _ v: String, _ c: Color) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 12)).foregroundStyle(ArtexTheme.dim)
            Spacer()
            Text(v).font(.system(size: 11, design: .monospaced)).foregroundStyle(c)
                .multilineTextAlignment(.trailing)
        }
    }

    private func probe() async {
        busy = true
        defer { busy = false }
        let t0 = Date()
        let ok = await APIClient.shared.probe()
        probeMs = Int(Date().timeIntervalSince(t0) * 1000)
        reachable = ok
        if ok {
            do {
                let st = try await AuthAPI.status()
                let initStr = st.initialized == true ? "true" : (st.initialized == false ? "false" : "-")
                let setupStr = st.needSetup == true ? "true" : (st.needSetup == false ? "false" : "-")
                detail = "auth/status → initialized=\(initStr) needSetup=\(setupStr)"
            } catch {
                detail = "probe 通过但 auth/status 失败：\(error.localizedDescription)"
            }
        } else {
            detail = """
            无法连接 \(store.config.effectiveBase)
            排查建议：
              1. 确认手机与服务器在同一网络
              2. 服务器是否监听 0.0.0.0:8787（不是 127.0.0.1）
              3. 服务器防火墙是否放行 8787
              4. 若用 https 自签证书，App 已允许任意加载，但仍需证书链可建立
            """
        }
    }
}
