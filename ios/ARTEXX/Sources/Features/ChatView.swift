import SwiftUI

/// 对话页 —— 对齐 chat/page.tsx（人在环路）
struct ChatListView: View {
    @EnvironmentObject var store: AppStore
    @State private var convs: [ConversationItem] = []
    @State private var showNew = false

    var body: some View {
        VStack(spacing: 0) {
            PageTitle("对话", sub: "人在环路 · 与 Agent 直接交流", action: AnyView(
                ArtexButton(title: "新会话", icon: "plus", compact: true) { Task { await createConv() } }
            ))

            if store.offlineMode {
                ScrollView {
                    VStack(spacing: 12) {
                        Card(title: "本地对话") {
                            Text("离线模式下可直接与模型对话，或到「任务」页让 Agent 执行。")
                                .font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                        }
                        NavigationLink { LocalChatView() } label: {
                            HStack {
                                Image(systemName: "message").font(.system(size: 13)).foregroundStyle(ArtexTheme.accent)
                                Text("开始本地对话").font(.system(size: 12)).foregroundStyle(ArtexTheme.text)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                            }
                            .padding(12).background(ArtexTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radius).stroke(ArtexTheme.border, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
                        }
                    }.padding(16)
                }
            } else if convs.isEmpty {
                EmptyHint(text: "暂无会话")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(convs) { c in
                            NavigationLink { ChatDetailView(conv: c) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.title ?? "会话 #\(c.id)")
                                            .font(.system(size: 12)).foregroundStyle(ArtexTheme.text)
                                        Text(fmtRel(c.updated_at?.date))
                                            .font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 11)
                            }
                            Rectangle().fill(ArtexTheme.border).frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .background(ArtexTheme.bg)
        .task {
            guard !store.offlineMode else { return }
            convs = (try? await ChatAPI.conversations()) ?? []
        }
    }

    private func createConv() async {
        _ = try? await ChatAPI.create("新会话")
        convs = (try? await ChatAPI.conversations()) ?? []
    }
}

/// 本地对话：直接调 LLM，不依赖服务端
struct LocalChatView: View {
    @State private var msgs: [(role: String, text: String)] = []
    @State private var input = ""
    @State private var busy = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if msgs.isEmpty {
                            EmptyHint(text: LLMClient.shared.config.ready
                                      ? "输入问题开始对话"
                                      : "先去「模型」页配置 API Key")
                        }
                        ForEach(Array(msgs.enumerated()), id: \.offset) { _, m in
                            HStack {
                                if m.role == "user" { Spacer() }
                                Text(m.text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(m.role == "user" ? ArtexTheme.bg : ArtexTheme.text)
                                    .padding(10)
                                    .background(m.role == "user" ? ArtexTheme.text : ArtexTheme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
                                if m.role != "user" { Spacer() }
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(16)
                }
                .onChange(of: msgs.count) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            HStack(spacing: 8) {
                TextField("输入消息…", text: $input)
                    .font(.system(size: 12))
                    .focused($focused)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(ArtexTheme.bg)
                    .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm).stroke(ArtexTheme.input, lineWidth: 0.8))
                    .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
                Button {
                    send()
                } label: {
                    if busy { ProgressView().tint(ArtexTheme.accent).scaleEffect(0.7) }
                    else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)).foregroundStyle(ArtexTheme.accent) }
                }
                .disabled(busy || input.isEmpty)
            }
            .padding(10)
            .background(ArtexTheme.surface)
            .overlay(Rectangle().frame(height: 0.5).foregroundStyle(ArtexTheme.border), alignment: .top)
        }
        .background(ArtexTheme.bg)
        .navigationTitle("本地对话")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send() {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        input = ""
        msgs.append(("user", t))
        busy = true
        Task {
            do {
                let reply = try await LLMClient.shared.complete(
                    messages: msgs.map { LLMMessage(role: $0.role, content: $0.text) }, tools: [])
                msgs.append(("assistant", reply.content.isEmpty ? "(空回复)" : reply.content))
            } catch {
                msgs.append(("assistant", "错误：" + error.localizedDescription))
            }
            busy = false
        }
    }
}

/// 远端会话详情
struct ChatDetailView: View {
    let conv: ConversationItem
    @State private var msgs: [ChatMessage] = []
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(msgs) { m in
                        HStack {
                            if m.role == "user" { Spacer() }
                            Text(m.content)
                                .font(.system(size: 12))
                                .foregroundStyle(m.role == "user" ? ArtexTheme.bg : ArtexTheme.text)
                                .padding(10)
                                .background(m.role == "user" ? ArtexTheme.text : ArtexTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
                            if m.role != "user" { Spacer() }
                        }
                    }
                }.padding(16)
            }
            HStack(spacing: 8) {
                TextField("发消息", text: $input)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(ArtexTheme.bg)
                    .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm).stroke(ArtexTheme.input, lineWidth: 0.8))
                    .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
                Button("发送") {
                    let t = input; input = ""
                    Task {
                        try? await ChatAPI.send(conv.id, text: t)
                        msgs = (try? await ChatAPI.messages(conv.id)) ?? []
                    }
                }.font(.system(size: 12))
            }.padding(10)
        }
        .background(ArtexTheme.bg)
        .navigationTitle(conv.title ?? "会话")
        .navigationBarTitleDisplayMode(.inline)
        .task { msgs = (try? await ChatAPI.messages(conv.id)) ?? [] }
    }
}
