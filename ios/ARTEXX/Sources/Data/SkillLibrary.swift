import Foundation

/// 技能库：内置 319 条渗透技能，可组合成任务编排（Playbook）。
final class SkillLibrary: ObservableObject {
    static let shared = SkillLibrary()
    @Published private(set) var all: [Skill] = []
    @Published var selected: Set<String> = []

    private init() { load() }

    private func load() {
        guard let url = Bundle.main.url(forResource: "skills", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Skill].self, from: data) else {
            all = []
            return
        }
        all = list.sorted { $0.cat == $1.cat ? $0.n < $1.n : $0.cat < $1.cat }
    }

    var categories: [(String, Int)] {
        Dictionary(grouping: all, by: { $0.cat })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    func filtered(category: String?, query: String) -> [Skill] {
        var list = all
        if let category, !category.isEmpty { list = list.filter { $0.cat == category } }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.n.lowercased().contains(q) || $0.d.lowercased().contains(q)
                || $0.tags.joined(separator: " ").lowercased().contains(q)
                || $0.tools.joined(separator: " ").lowercased().contains(q)
            }
        }
        return list
    }

    func byID(_ id: String) -> Skill? { all.first { $0.id == id } }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// 把选中的技能按阶段排序，生成可直接交给 Agent / 终端的作战序列
    func buildPlaybook() -> Playbook {
        let picked = all.filter { selected.contains($0.id) }
        let order = ["recon", "fingerprint", "exploit", "report"]
        let steps = picked.sorted {
            let a = order.firstIndex(of: $0.phase) ?? 99
            let b = order.firstIndex(of: $1.phase) ?? 99
            return a == b ? $0.cat < $1.cat : a < b
        }
        return Playbook(skills: steps)
    }
}

struct Playbook {
    var skills: [Skill]

    var title: String {
        if skills.count == 1 { return skills[0].n }
        return skills.prefix(3).map { $0.n }.joined(separator: " + ") + (skills.count > 3 ? " 等 \(skills.count) 项" : "")
    }

    var briefMarkdown: String {
        var s = "# 作战简报\n\n"
        s += "共 \(skills.count) 项技能，按侦察 → 指纹 → 利用 → 复盘排序。\n\n"
        for (i, k) in skills.enumerated() {
            s += "## \(i + 1). \(k.n) · \(k.cat)\n"
            s += "\(k.d)\n\n"
            if !k.cmds.isEmpty {
                s += "```bash\n" + k.cmds.joined(separator: "\n") + "\n```\n\n"
            }
        }
        return s
    }

    var shellScript: String {
        var lines = ["#!/bin/sh", "# ARTEXX playbook: " + skills.map { $0.id }.joined(separator: ",")]
        for k in skills {
            lines.append("# --- \(k.n)")
            lines.append(contentsOf: k.cmds)
        }
        return lines.joined(separator: "\n")
    }

    var cveKeywords: [String] {
        var kw = Set<String>()
        for k in skills {
            for t in k.tools { kw.insert(t) }
            for t in k.tags { kw.insert(t) }
        }
        return Array(kw).sorted()
    }
}
