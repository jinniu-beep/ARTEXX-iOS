
// convert-schema.mjs — PostgreSQL schema → SQLite schema
import fs from "node:fs";

const src = fs.readFileSync("E:/ds/_ref/ARTEXX/db/schema.sql", "utf8");
let out = [];
let stats = { tables: 0, indexes: 0, triggers: 0, functionsSkipped: 0, uniques: 0 };

// 1) 去掉 plpgsql 函数定义（SQLite 不支持）
// 先删整个 $ ... $ 函数体
let s = src.replace(/CREATE OR REPLACE FUNCTION[\s\S]*?\$\$[\s\S]*?\$\$\s*LANGUAGE plpgsql[^;]*;/gi, () => {
  stats.functionsSkipped++;
  return "-- [converted] plpgsql function removed (logic moved to app layer)";
});
// 兜底：任何残留的 FUNCTION 行
s = s.replace(/CREATE OR REPLACE FUNCTION[^\n]*\n/g, () => {
  stats.functionsSkipped++;
  return "-- [converted] function removed\n";
});

// 2) 逐行处理
const lines = s.split("\n");
let inTable = false;
let tableBuf = [];

for (let raw of lines) {
  let line = raw;

  // 注释保留
  if (/^\s*--/.test(line)) { out.push(line); continue; }
  if (!line.trim()) { out.push(line); continue; }

  // CREATE TABLE
  if (/CREATE TABLE IF NOT EXISTS/i.test(line)) {
    inTable = true;
    tableBuf = [];
    stats.tables++;
    line = line.replace(/CREATE TABLE IF NOT EXISTS/i, "CREATE TABLE IF NOT EXISTS");
    tableBuf.push(line);
    continue;
  }

  if (inTable) {
    // 类型映射
    line = line
      .replace(/\bBIGSERIAL\s+PRIMARY KEY\b/gi, "INTEGER PRIMARY KEY AUTOINCREMENT")
      .replace(/\bSERIAL\s+PRIMARY KEY\b/gi, "INTEGER PRIMARY KEY AUTOINCREMENT")
      .replace(/\bBIGSERIAL\b/gi, "INTEGER")
      .replace(/\bSERIAL\b/gi, "INTEGER")
      .replace(/\bTIMESTAMPTZ\b/gi, "TEXT")
      .replace(/\bTIMESTAMP\b/gi, "TEXT")
      .replace(/\bJSONB\[\]/gi, "TEXT")
      .replace(/\bJSONB\b/gi, "TEXT")
      .replace(/\bJSON\[\]/gi, "TEXT")
      .replace(/\bJSON\b/gi, "TEXT")
      .replace(/\bTEXT\[\]/gi, "TEXT")
      .replace(/\bINTEGER\[\]/gi, "TEXT")
      .replace(/\bBIGINT\[\]/gi, "TEXT")
      .replace(/\bCIDR\b/gi, "TEXT")
      .replace(/\bINET\b/gi, "TEXT")
      .replace(/\bnow\(\)/gi, "(datetime('now'))")
      .replace(/DEFAULT\s+'\{\}'/gi, "DEFAULT '[]'")
      .replace(/DEFAULT\s+''\{\}'/gi, "DEFAULT '[]'");

    tableBuf.push(line);
    if (/^\s*\);/.test(line)) {
      inTable = false;
      out.push(...tableBuf);
    }
    continue;
  }

  // 索引
  if (/CREATE (UNIQUE )?INDEX/i.test(line)) {
    stats.indexes++;
    if (/USING\s+(GIN|GIST|BRIN)/i.test(line)) {
      out.push("-- [converted] " + line.trim() + "  (GIN/GIST index dropped; full-text handled by app)");
      continue;
    }
    // SQLite 支持部分索引
    line = line.replace(/\bTIMESTAMPTZ\b/gi, "TEXT");
    out.push(line);
    continue;
  }

  // 触发器 → SQLite 形式
  if (/CREATE TRIGGER/i.test(line)) {
    stats.triggers++;
    const m = line.match(/CREATE TRIGGER\s+(\w+)\s+BEFORE UPDATE ON\s+(\w+)/i);
    if (m) {
      out.push("CREATE TRIGGER IF NOT EXISTS " + m[1] + " AFTER UPDATE ON " + m[2]);
      out.push("FOR EACH ROW WHEN NEW.updated_at = OLD.updated_at");
      out.push("BEGIN");
      out.push("  UPDATE " + m[2] + " SET updated_at = datetime('now') WHERE rowid = NEW.rowid;");
      out.push("END;");
      continue;
    }
    continue;
  }
  // 跳过触发器的续行
  if (/FOR EACH ROW EXECUTE FUNCTION/i.test(line)) { continue; }
  if (/DROP TRIGGER/i.test(line)) { continue; }

  // DROP FUNCTION
  if (/DROP FUNCTION/i.test(line)) { continue; }

  // PG 幂等迁移语句：SQLite 不支持 ADD COLUMN IF NOT EXISTS / ALTER COLUMN SET DEFAULT / DROP CONSTRAINT
  // 全新 SQLite 库已由 CREATE TABLE 建成最终形态，这些升级语句一律跳过
  if (/ALTER TABLE/i.test(line) && /(ADD COLUMN IF NOT EXISTS|ALTER COLUMN|DROP CONSTRAINT|ADD CONSTRAINT)/i.test(line)) {
    out.push("-- [skipped] PG migration: " + line.trim().slice(0, 100));
    continue;
  }
  out.push(line);
}

// ── 语句级后处理：只保留 CREATE TABLE / CREATE INDEX / CREATE TRIGGER ──
let joined = out.join("\n");

// 移出 $ ... $ 块（DO / plpgsql 匿名块）
joined = joined.replace(/DO \$\$[\s\S]*?\$\$\s*;/g, "-- [skipped] plpgsql DO block");
joined = joined.replace(/\$\$[\s\S]*?\$\$/g, "");

// 用状态机切成语句（尊重括号深度与引号）
function splitStatements(text) {
  const res = [];
  let buf = "", depth = 0, inS = null;
  for (let i = 0; i < text.length; i++) {
    const c = text[i], n = text[i + 1];
    if (inS) {
      buf += c;
      if (c === inS) inS = null;
      continue;
    }
    if (c === "'" || c === '"') { inS = c; buf += c; continue; }
    if (c === "-" && n === "-") { // 行注释
      const nl = text.indexOf("\n", i);
      buf += text.slice(i, nl < 0 ? text.length : nl + 1);
      i = (nl < 0 ? text.length : nl);
      continue;
    }
    if (c === "(") depth++;
    if (c === ")") depth--;
    if (c === ";" && depth <= 0) { res.push(buf + ";"); buf = ""; continue; }
    buf += c;
  }
  if (buf.trim()) res.push(buf);
  return res;
}

const stmts = splitStatements(joined);
const kept = [];
let dropped = 0;
for (const st of stmts) {
  const t = st.trim();
  if (!t || /^--/.test(t) && t.split("\n").every(l => /^\s*--/.test(l) || !l.trim())) continue;
  const head = t.replace(/^(--[^\n]*\n\s*)+/, "").trim();
  if (/^CREATE TABLE/i.test(head) || /^CREATE (UNIQUE )?INDEX/i.test(head) || /^CREATE TRIGGER/i.test(head)) {
    kept.push(t);
  } else if (/^ALTER TABLE/i.test(head) && /ADD COLUMN (?!IF NOT EXISTS)/i.test(head)) {
    kept.push(t); // 普通 ADD COLUMN 保留
  } else {
    dropped++;
  }
}
console.log("语句级过滤：保留", kept.length, "丢弃", dropped);
const result = kept.join("\n\n")
  .replace(/\bBIGSERIAL\b/gi, "INTEGER")
  .replace(/\bTIMESTAMPTZ\b/gi, "TEXT")
  .replace(/\bJSONB\b/gi, "TEXT")
  .replace(/\bCIDR\b/gi, "TEXT")
  .replace(/\bnow\(\)/gi, "(datetime('now'))")
  .replace(/\bJSONB\b/gi, "TEXT")
  .replace(/\$\$ LANGUAGE plpgsql[^;]*;/gi, ";")
  .replace(/\bLANGUAGE plpgsql\b/gi, "");

fs.mkdirSync("E:/ds/ARTEXX-iOS/backend", { recursive: true });
fs.writeFileSync("E:/ds/ARTEXX-iOS/backend/schema.sqlite.sql", result);

console.log("转换统计：", JSON.stringify(stats));
console.log("输出行数：", result.split("\n").length);
console.log("输出大小：", Math.round(result.length / 1024) + " KB");
console.log("残留 PG 类型检查：");
for (const bad of ["BIGSERIAL", "TIMESTAMPTZ", "JSONB", "CIDR", "plpgsql", "EXECUTE FUNCTION"]) {
  const n = (result.match(new RegExp(bad, "gi")) || []).length;
  console.log("  " + bad + ": " + n + (n === 0 ? " ✓" : " ✗"));
}
console.log("\nCREATE TABLE 数：", (result.match(/CREATE TABLE/gi) || []).length);
console.log("CREATE INDEX 数：", (result.match(/CREATE INDEX/gi) || []).length);
