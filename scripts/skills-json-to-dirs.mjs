// skills-json-to-dirs.mjs — expand skills.json (319 entries) into the SKILL.md
// directory layout the Go backend reads (skill.LoadDir): one dir per skill, each
// containing a SKILL.md with YAML frontmatter (name/description) + a body of
// commands / tools / use-cases. Output is bundled and unpacked to
// Application Support/artex/skills on first launch.
//
// usage: node scripts/skills-json-to-dirs.mjs [skills.json] [outDir]
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const src = process.argv[2] || path.join(root, "ios/ARTEXX/Resources/skills.json");
const outDir = process.argv[3] || path.join(root, "ios/ARTEXX/Resources/skills");

const skills = JSON.parse(fs.readFileSync(src, "utf8"));
fs.rmSync(outDir, { recursive: true, force: true });
fs.mkdirSync(outDir, { recursive: true });

function slug(s) {
  return (
    String(s)
      .toLowerCase()
      .replace(/[^a-z0-9._-]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 80) || "skill"
  );
}

const seen = new Set();
let i = 0;
for (const sk of skills) {
  let id = slug(sk.id || sk.n || `skill-${i}`);
  let base = id;
  let k = 1;
  while (seen.has(id)) id = base + "-" + k++;
  seen.add(id);

  const name = sk.n || id;
  const desc = String(sk.d || name).replace(/\r?\n/g, " ").trim();
  const cmds = Array.isArray(sk.cmds) ? sk.cmds : [];
  const tools = Array.isArray(sk.tools) ? sk.tools : [];
  const tags = Array.isArray(sk.tags) ? sk.tags : [];

  const lines = [
    "---",
    `name: ${JSON.stringify(id)}`,
    `description: ${JSON.stringify(desc)}`,
    "---",
    "",
    `# ${name}`,
    "",
  ];
  if (sk.cat || sk.phase) {
    lines.push(`**分类**：${sk.cat || "-"}　·　**阶段**：${sk.phase || "-"}`, "");
  }
  lines.push(desc, "");
  if (tags.length) lines.push(`**适用场景 / 标签**：${tags.join("、")}`, "");
  if (cmds.length) lines.push("## 可执行命令", "", "```bash", ...cmds, "```", "");
  if (tools.length) lines.push("## 依赖工具", "", tools.join("、"), "");

  const dir = path.join(outDir, id);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "SKILL.md"), lines.join("\n") + "\n");
  i++;
}

console.log(`skills: generated ${seen.size} SKILL.md dirs into ${outDir}`);
