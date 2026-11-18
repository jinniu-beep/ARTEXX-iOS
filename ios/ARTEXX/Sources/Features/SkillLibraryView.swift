import SwiftUI

struct SkillLibraryView: View {
    @StateObject private var lib = SkillLibrary.shared
    @State private var query = ""
    @State private var category: String?
    @State private var showPlaybook = false
    @State private var detailSkill: Skill?

    private var list: [Skill] { lib.filtered(category: category, query: query) }

    var body: some View {
        Group {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button { category = nil } label: {
                            Pill(text: "全部 \(lib.all.count)", color: category == nil ? ArtexTheme.accent : ArtexTheme.dim)
                        }
                        ForEach(lib.categories, id: \.0) { c in
                            Button { category = c.0 } label: {
                                Pill(text: "\(c.0) \(c.1)", color: category == c.0 ? ArtexTheme.accent : ArtexTheme.dim)
                            }
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                }

                List {
                    ForEach(list) { s in
                        Button { detailSkill = s } label: { row(s) }
                            .listRowBackground(ArtexTheme.surface)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    lib.toggle(s.id)
                                } label: {
                                    Label(lib.selected.contains(s.id) ? "移出编排" : "加入编排",
                                          systemImage: lib.selected.contains(s.id) ? "minus.circle" : "plus.circle")
                                }.tint(ArtexTheme.accent)
                            }
                    }
                }
                .scrollContentBackground(.hidden)
                .searchable(text: $query, prompt: "搜技能 / 工具 / 标签")
            }
            .background(ArtexTheme.bg)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showPlaybook = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.horizontal.circle")
                            Text("\(lib.selected.count)")
                        }
                    }
                    .disabled(lib.selected.isEmpty)
                }
            }
            .sheet(item: $detailSkill) { s in
                SkillDetailView(skill: s)
            }
            .sheet(isPresented: $showPlaybook) {
                PlaybookView()
            }
        }
    }

    private func row(_ s: Skill) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: lib.selected.contains(s.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(lib.selected.contains(s.id) ? ArtexTheme.accent : ArtexTheme.dim)
            VStack(alignment: .leading, spacing: 4) {
                Text(s.n).font(.system(size: 14, weight: .medium)).foregroundStyle(ArtexTheme.text)
                Text(s.d).font(.system(size: 11)).foregroundStyle(ArtexTheme.dim).lineLimit(2)
                HStack(spacing: 5) {
                    Pill(text: s.cat, color: ArtexTheme.low)
                    Pill(text: s.phase, color: ArtexTheme.dim)
                    if !s.tools.isEmpty { Pill(text: s.tools.prefix(2).joined(separator: ","), color: ArtexTheme.medium) }
                }
            }
        }
        .padding(.vertical, 3)
    }
}


struct SkillDetailView: View {
    let skill: Skill
    @Environment(\.dismiss) var dismiss
    @State private var relatedCVE: [CVERow] = []

    var body: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Pill(text: skill.cat, color: ArtexTheme.low)
                        Pill(text: skill.phase, color: ArtexTheme.dim)
                    }
                    Text(skill.d).font(.system(size: 14)).foregroundStyle(ArtexTheme.text)

                    Card(title: "命令") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(skill.cmds, id: \.self) { c in
                                HStack(alignment: .top) {
                                    Text(c).font(.system(size: 11, design: .monospaced)).foregroundStyle(ArtexTheme.accent)
                                    Spacer(minLength: 6)
                                    Button {
                                        UIPasteboard.general.string = c
                                    } label: { Image(systemName: "doc.on.doc").font(.system(size: 11)) }
                                }
                            }
                        }
                    }

                    Card(title: "工具") {
                        Text(skill.tools.joined(separator: " · ")).font(.system(size: 12, design: .monospaced)).foregroundStyle(ArtexTheme.text)
                    }

                    if !relatedCVE.isEmpty {
                        Card(title: "联动 CVE（\(relatedCVE.count)）") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(relatedCVE.prefix(12)) { c in
                                    HStack {
                                        Pill(text: c.id, color: ArtexTheme.severityColor(c.severity))
                                        Text(c.title).font(.system(size: 11)).foregroundStyle(ArtexTheme.dim).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        SkillLibrary.shared.toggle(skill.id)
                        dismiss()
                    } label: {
                        Text(SkillLibrary.shared.selected.contains(skill.id) ? "从编排中移出" : "加入编排")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(ArtexTheme.accent).foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(16)
            }
            .background(ArtexTheme.bg)
            .task { relatedCVE = CVEDatabase.shared.bySkill(skill.id, limit: 20) }
        }
    }
}

struct PlaybookView: View {
    @Environment(\.dismiss) var dismiss
    @State private var mode = 0
    private var playbook: Playbook { SkillLibrary.shared.buildPlaybook() }

    var body: some View {
        Group {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    Text("编排").tag(0)
                    Text("简报").tag(1)
                    Text("命令").tag(2)
                }.pickerStyle(.segmented).padding(12)

                ScrollView {
                    Group {
                        switch mode {
                        case 0:
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(playbook.skills) { s in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(s.phase.prefix(3).uppercased())
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(ArtexTheme.accent)
                                            .frame(width: 34, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(s.n).font(.system(size: 13, weight: .medium)).foregroundStyle(ArtexTheme.text)
                                            Text(s.cmds.first ?? "").font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.dim).lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    Divider().background(ArtexTheme.border)
                                }
                            }.padding(14)
                        case 1:
                            Text(playbook.briefMarkdown)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(ArtexTheme.text)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        default:
                            Text(playbook.shellScript)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(ArtexTheme.accent)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .background(ArtexTheme.bg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("复制") {
                        UIPasteboard.general.string = mode == 2 ? playbook.shellScript : playbook.briefMarkdown
                    }
                }
            }
        }
    }
}
