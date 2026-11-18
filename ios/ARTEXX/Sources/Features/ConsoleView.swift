import SwiftUI

/// cmd 控制台：与桌面端一致的命令行体验（本地 /bin/sh + 远端 gateway 双模式）
struct ConsoleView: View {
    @StateObject private var shell = ShellRunner.shared
    @StateObject private var remote = RemoteConsole()
    @State private var input = ""
    @State private var mode = 0                       // 0 = 本地 cmd，1 = 远端服务
    @State private var showSkills = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Picker("", selection: $mode) {
                        Text("本地 cmd").tag(0)
                        Text("远端").tag(1)
                    }.pickerStyle(.segmented).frame(width: 190)

                    Spacer()

                    if mode == 1 {
                        Circle().fill(remote.connected ? ArtexTheme.ok : ArtexTheme.dim)
                            .frame(width: 7, height: 7)
                        Text(remote.connected ? "SSE 已连接" : "未连接")
                            .font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                    } else {
                        Text(shell.running ? "运行中" : "就绪")
                            .font(.system(size: 10)).foregroundStyle(shell.running ? ArtexTheme.ok : ArtexTheme.dim)
                    }

                    Button { showSkills = true } label: { Image(systemName: "square.stack.3d.up") }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if mode == 0 {
                                ForEach(shell.lines) { l in line(l.text, l.kind) }
                            } else {
                                ForEach(Array(remote.lines.enumerated()), id: \.offset) { _, l in line(l, .output) }
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(ArtexTheme.bg)
                    .onChange(of: mode == 0 ? shell.lines.count : remote.lines.count) { _ in
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }

                HStack(spacing: 8) {
                    Text(mode == 0 ? "$" : ">")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(ArtexTheme.accent)
                    TextField(mode == 0 ? "输入命令，如 nmap -sV 10.0.0.1" : "输入远端 shell 命令", text: $input)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(ArtexTheme.text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onSubmit { submit() }
                    Button { submit() } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 22))
                            .foregroundStyle(ArtexTheme.accent)
                    }
                }
                .padding(10)
                .background(ArtexTheme.surface)
                .overlay(Rectangle().frame(height: 0.5).foregroundStyle(ArtexTheme.border), alignment: .top)
            }
            .background(ArtexTheme.bg)
            .navigationTitle("控制台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        shell.clear(); remote.clear()
                    } label: { Image(systemName: "trash") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { focused = true } label: { Image(systemName: "keyboard") }
                }
            }
            .sheet(isPresented: $showSkills) {
                ConsoleSkillPicker { cmd in input = cmd }
            }
            .onAppear { if shell.lines.isEmpty { shell.append("ARTEXX iOS 控制台 · 输入 help 查看内置命令", kind: .system) } }
        }
    }

    private func line(_ text: String, _ kind: ConsoleKind) -> some View {
        Text(text)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(color(kind))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(_ k: ConsoleKind) -> Color {
        switch k {
        case .input: return ArtexTheme.accent
        case .error: return ArtexTheme.critical
        case .system: return ArtexTheme.medium
        default: return ArtexTheme.text
        }
    }

    private func submit() {
        let cmd = input.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        input = ""
        if mode == 0 { shell.run(cmd) } else { remote.run(cmd) }
    }
}

/// 远端控制台：把命令经后端 chat / 任务通道下发，并把 SSE 活动流转成终端输出。
final class RemoteConsole: ObservableObject {
    @Published var lines: [String] = []
    @Published var connected = false

    func clear() { lines.removeAll() }

    func run(_ command: String) {
        lines.append("> " + command)
        Task {
            do {
                let convs = try await ChatAPI.conversations()
                let conv = convs.first
                if let conv {
                    try await ChatAPI.send(conv.id, text: command)
                    lines.append("[已下发到会话 #\(conv.id)]")
                } else {
                    let created = try await ChatAPI.create("控制台")
                    if let id = created["id"]?.intValue {
                        try await ChatAPI.send(Int64(id), text: command)
                        lines.append("[已创建会话 #\(id) 并下发]")
                    }
                }
            } catch {
                lines.append("错误: \(error.localizedDescription)")
            }
        }
    }
}

struct ConsoleSkillPicker: View {
    @Environment(\.dismiss) var dismiss
    var onPick: (String) -> Void
    @State private var q = ""
    private let lib = SkillLibrary.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(lib.filtered(category: nil, query: q).prefix(120)) { s in
                    Button {
                        onPick(s.cmds.first ?? "")
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.n).font(.system(size: 13, weight: .medium)).foregroundStyle(ArtexTheme.text)
                            Text(s.cmds.first ?? "").font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.accent).lineLimit(1)
                        }
                    }
                    .listRowBackground(ArtexTheme.surface)
                }
            }
            .searchable(text: $q, prompt: "搜技能")
            .scrollContentBackground(.hidden)
            .background(ArtexTheme.bg)
            .navigationTitle("插入技能命令")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
