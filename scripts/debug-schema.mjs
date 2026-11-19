
import fs from "node:fs";
import { DatabaseSync } from "node:sqlite";
const sql = fs.readFileSync("E:/ds/ARTEXX-iOS/backend/schema.sqlite.sql", "utf8");
const db = new DatabaseSync(":memory:");

// 逐语句执行，用 sqlite3_complete 语义：按 ; 切但保留触发器块
const stmts = [];
let buf = "";
for (const line of sql.split("\n")) {
  if (line.trim().startsWith("--")) continue;
  buf += line + "\n";
  if (/;\s*$/.test(line.trim())) {
    // 触发器块：BEGIN...END; 需要整块
    if (/CREATE TRIGGER/i.test(buf) && !/END;/i.test(buf)) continue;
    stmts.push(buf.trim());
    buf = "";
  }
}
if (buf.trim()) stmts.push(buf.trim());

let ok = 0, fail = [];
for (const st of stmts) {
  if (!st.replace(/[\s;]/g, "")) continue;
  try { db.exec(st); ok++; }
  catch (e) { fail.push({ st: st.slice(0, 100).replace(/\n/g, " "), err: String(e.message).slice(0, 100) }); }
}
console.log("语句总数:", stmts.length, "成功:", ok, "失败:", fail.length);
fail.slice(0, 15).forEach(f => console.log("✗", f.err, "\n   ", f.st));
const t = db.prepare("SELECT count(*) c FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").get();
console.log("\n实际表数:", t.c);
