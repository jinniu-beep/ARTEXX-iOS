
import fs from "node:fs";
import { DatabaseSync } from "node:sqlite";

const sql = fs.readFileSync("E:/ds/ARTEXX-iOS/backend/schema.sqlite.sql", "utf8");
const db = new DatabaseSync(":memory:");

// Split SQL into statements, handling BEGIN...END trigger blocks
// Only tracks BEGIN/END at the start of a line (SQL keywords, not inside strings/comments)
function splitSQL(text) {
  const stmts = [];
  let buf = "";
  let inBegin = 0;
  
  const lines = text.split("\n");
  for (const line of lines) {
    const trimmed = line.trim();
    
    // Skip pure comment lines for BEGIN/END tracking
    if (trimmed.startsWith("--")) {
      buf += line + "\n";
      continue;
    }
    
    // Check if this line starts a BEGIN block (trigger body)
    if (/^BEGIN\b/i.test(trimmed)) inBegin++;
    // Check if this line ends a BEGIN block
    if (/^END;?\s*$/i.test(trimmed) && inBegin > 0) {
      buf += line + "\n";
      inBegin--;
      if (inBegin === 0 && buf.trim()) {
        stmts.push(buf.trim());
        buf = "";
      }
      continue;
    }
    
    buf += line + "\n";
    
    // Split on lines ending with ; when not in a BEGIN block
    if (inBegin === 0 && trimmed.endsWith(";") && !trimmed.startsWith("--")) {
      if (buf.trim() && buf.trim() !== ";") {
        stmts.push(buf.trim());
        buf = "";
      }
    }
  }
  if (buf.trim()) stmts.push(buf.trim());
  return stmts;
}

const stmts = splitSQL(sql);
console.log("Total statements:", stmts.length);

let ok = 0, failed = 0;
let firstFail = null;
for (let i = 0; i < stmts.length; i++) {
  const st = stmts[i].trim();
  if (!st || st.startsWith("--") || st === ";") continue;
  if (/^--/.test(st.split("\n").filter(l => l.trim())[0] || "")) continue;
  try { db.exec(st); ok++; }
  catch(e) { 
    failed++;
    if (!firstFail) firstFail = { i: i+1, err: e.message.slice(0,100), sql: st.slice(0,120) };
  }
}

const t = db.prepare("SELECT count(*) c FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").get();
const ix = db.prepare("SELECT count(*) c FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'").get();
const tr = db.prepare("SELECT count(*) c FROM sqlite_master WHERE type='trigger'").get();
console.log("Tables:", t.c, "Indexes:", ix.c, "Triggers:", tr.c, "Ok:", ok, "Failed:", failed);
if (firstFail) console.log("First fail #", firstFail.i, "-", firstFail.err, "\n SQL:", firstFail.sql);
