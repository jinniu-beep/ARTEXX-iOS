import SwiftUI

/// 作战编排 —— 把勾选的技能按阶段排序，产出清单/简报/脚本三种形态
struct PlaybookView: View {
    @Environment(\.dismiss) var dismiss
    @State private var mode = 0
    private var playbook: Playbook { SkillLibrary.shared.buildPlaybook() }

    var body: some View {
        VStack(spacing: 0) {
            ArtexTabs(items: ["编排", "简报", "命令"], selection: $mode)

            ScrollView {
                Group {
                    switch mode {
                    case 0:
                        VStack(alignment: .leading, spacing: 0) {
                            if playbook.skills.isEmpty {
                                EmptyHint(text: "还没有选择技能\n到「技能库」勾选后回来")
                            }
                            ForEach(Array(playbook.skills.enumerated()), id: \.element.id) { i, s in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(String(format: "%02d", i + 1))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(ArtexTheme.dim)
                                        .frame(width: 18, alignment: .leading)
                                    Text(s.phase.prefix(3).uppercased())
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(ArtexTheme.accent)
                                        .frame(width: 26, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.n).font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(ArtexTheme.text)
                                        if let c = s.cmds.first {
                                            Text(c).font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(ArtexTheme.dim).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                Rectangle().fill(ArtexTheme.border).frame(height: 0.5)
                            }
                        }
                    case 1:
                        Text(playbook.briefMarkdown)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ArtexTheme.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    default:
                        Text(playbook.shellScript)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(ArtexTheme.accent)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("\(playbook.skills.count) 项").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                Spacer()
                ArtexButton(title: "复制", icon: "doc.on.doc", compact: true) {
                    UIPasteboard.general.string = mode == 2 ? playbook.shellScript : playbook.briefMarkdown
                }
            }
            .padding(10)
            .overlay(Rectangle().frame(height: 0.5).foregroundStyle(ArtexTheme.border), alignment: .top)
        }
        .background(ArtexTheme.bg)
        .navigationTitle("作战编排")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("关闭") { dismiss() }.font(.system(size: 12))
            }
        }
    }
}

/// 技能详情（独立页，从技能库点进时用）
struct SkillDetailView: View {
    let skill: Skill
    @Environment(\.dismiss) var dismiss
    @State private var relatedCVE: [CVERow] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 5) {
                    Pill(text: skill.cat, color: ArtexTheme.low)
                    Pill(text: skill.phase, color: ArtexTheme.dim)
                }
                Text(skill.d).font(.system(size: 12)).foregroundStyle(ArtexTheme.text)

                Card(title: "命令") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(skill.cmds, id: \.self) { c in
                            HStack(alignment: .top) {
                                Text(c).font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(ArtexTheme.accent)
                                Spacer(minLength: 4)
                                Button { UIPasteboard.general.string = c } label: {
                                    Image(systemName: "doc.on.doc").font(.system(size: 9))
                                        .foregroundStyle(ArtexTheme.dim)
                                }
                            }
                        }
                    }
                }

                if !relatedCVE.isEmpty {
                    Card(title: "关联 CVE \(relatedCVE.count)") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(relatedCVE.prefix(10)) { c in
                                HStack(spacing: 5) {
                                    Pill(text: c.id, color: ArtexTheme.severityColor(c.severity))
                                    Text(c.title).font(.system(size: 9))
                                        .foregroundStyle(ArtexTheme.dim).lineLimit(1)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                ArtexButton(title: SkillLibrary.shared.selected.contains(skill.id) ? "从编排中移出" : "加入编排") {
                    SkillLibrary.shared.toggle(skill.id)
                    dismiss()
                }
            }.padding(16)
        }
        .background(ArtexTheme.bg)
        .navigationTitle(skill.n)
        .navigationBarTitleDisplayMode(.inline)
        .task { relatedCVE = CVEDatabase.shared.bySkill(skill.id, limit: 20) }
    }
}
