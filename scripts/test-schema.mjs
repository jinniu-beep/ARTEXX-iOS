
import fs from "node:fs";
import { DatabaseSync } from "node:sqlite";

const sql = fs.readFileSync("E:/ds/ARTEXX-iOS/backend/schema.sqlite.sql", "utf8");
const db = new DatabaseSync(":memory:");

try {
  db.exec(sql);
  const t = db.prepare("SELECT count(*) c FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").get();
  const tr = db.prepare("SELECT count(*) c FROM sqlite_master WHERE type='trigger'").get();
  const ix = db.prepare("SELECT count(*) c FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'").get();
  console.log("SUCCESS Tables:", t.c, "Indexes:", ix.c, "Triggers:", tr.c);
  const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all();
  console.log("Tables:", tables.map(x => x.name).join(", "));
} catch(e) {
  console.log("FAIL:", e.message.slice(0, 200));
}
