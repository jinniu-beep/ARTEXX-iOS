
import fs from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { buildGuidance } from "./guidance.mjs";

const OUT = "E:/ds/ARTEXX-iOS/resources/cve/cve.sqlite";
const db = new DatabaseSync(OUT);
db.exec("PRAGMA journal_mode=MEMORY; PRAGMA synchronous=OFF;");

const cols = db.prepare("PRAGMA table_info(cve)").all().map((c) => c.name);
if (!cols.includes("has_exp")) db.exec("ALTER TABLE cve ADD COLUMN has_exp INTEGER DEFAULT 0");
if (!cols.includes("exp_id")) db.exec("ALTER TABLE cve ADD COLUMN exp_id TEXT");
console.log("columns ready");

const expByCve = JSON.parse(fs.readFileSync("E:/ds/ARTEXX-iOS/resources/cve/raw2/exploitdb-by-cve.json", "utf8"));
const rows = db.prepare("SELECT rowid,id,desc,cwe FROM cve").all();
console.log("rows:", rows.length);

const upd = db.prepare("UPDATE cve SET guidance=?, has_exp=?, exp_id=? WHERE rowid=?");
db.exec("BEGIN");
let n = 0, withExp = 0;
for (const r of rows) {
  const g = buildGuidance({ desc: r.desc || "", cwe: r.cwe || "", title: "" });
  const e = expByCve[r.id];
  const has = e && e.length ? 1 : 0;
  if (has) withExp++;
  upd.run(JSON.stringify(g), has, has ? String(e[0].id) : null, r.rowid);
  n++;
  if (n % 50000 === 0) console.log("guided", n);
}
db.exec("COMMIT");
console.log("guidance done:", n, "with exploit:", withExp);
db.exec("CREATE INDEX IF NOT EXISTS idx_exp ON cve(has_exp);");
db.exec("ANALYZE");
db.close();

import zlib from "node:zlib";
const raw = fs.readFileSync(OUT);
const gz = zlib.gzipSync(raw, { level: 9 });
fs.writeFileSync("E:/ds/ARTEXX-iOS/ios/ARTEXX/Resources/cve.sqlite.gz", gz);
fs.writeFileSync(OUT + ".gz", gz);
console.log("sqlite MB", (raw.length / 1048576).toFixed(1), "gz MB", (gz.length / 1048576).toFixed(1));
