
import fs from "node:fs";
import { DatabaseSync } from "node:sqlite";

const sql = fs.readFileSync("E:/ds/ARTEXX-iOS/backend/schema.sqlite.sql", "utf8");
const db = new DatabaseSync(":memory:");

let ok = 0, fail = [];
// 按分号切分执行（注意触发器块 BEGIN...END; 需要整体）
const stmts = sql.split(/;\s*\n/).map(s => s.trim()).filter(s => s && !s.startsWith("--"));

// 更稳妥：整体执行（SQLite 支持多语句）
try {
  db.exec(sql);
  ok = 1;
} catch (e) {
  // 逐条定位失败语句
  for (const st of stmts) {
    if (!st || st.startsWith("--")) continue;
    try { db.exec(st + ";"); ok++; }
    catch (err) { fail.push({ st: st.slice(0, 90), err: String(err.message).slice(0, 120) }); }
  }
}

console.log("整体执行:", ok === 1 ? "成功 ✓" : "失败，已逐条重试");
if (fail.length) {
  console.log("失败语句数:", fail.length);
  fail.slice(0, 12).forEach(f => console.log("  ✗", f.err, "|", f.st));
}

// 统计实际建出的对象
try {
  const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").all();
  const idx = db.prepare("SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'").all();
  const trg = db.prepare("SELECT name FROM sqlite_master WHERE type='trigger'").all();
  console.log("\n=== 实际建出 ===");
  console.log("表:", tables.length);
  console.log("索引:", idx.length);
  console.log("触发器:", trg.length);
  console.log("\n前 10 张表:", tables.slice(0, 10).map(t => t.name).join(", "));
} catch (e) {
  console.log("统计失败:", e.message);
}
