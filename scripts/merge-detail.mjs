
import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";

const RAW = "E:/ds/ARTEXX-iOS/resources/cve/raw2";
const OUT = "E:/ds/ARTEXX-iOS/resources/cve/cve.sqlite";
const db = new DatabaseSync(OUT);
db.exec("PRAGMA journal_mode=MEMORY; PRAGMA synchronous=OFF;");

function col(table, name, type) {
  const cols = db.prepare("PRAGMA table_info(" + table + ")").all().map((c) => c.name);
  if (!cols.includes(name)) db.exec("ALTER TABLE " + table + " ADD COLUMN " + name + " " + type);
}
col("cve", "guidance", "TEXT");
col("cve", "vec", "TEXT");
col("cve", "rng", "TEXT");
col("cve", "refjson", "TEXT");

const upd = db.prepare("UPDATE cve SET guidance=?, vec=?, rng=?, refjson=?, desc=? WHERE id=?");
const files = fs.readdirSync(RAW).filter((f) => f.startsWith("d-") && f.endsWith(".json"));
let n = 0, miss = 0;
db.exec("BEGIN");
for (const f of files) {
  const arr = JSON.parse(fs.readFileSync(path.join(RAW, f), "utf8"));
  for (const r of arr) {
    const ranges = (r.r || []).map((x) => {
      if (x.vs || x.ve || x.vse || x.vss) return x.p + " " + (x.vs ? ">=" + x.vs + " " : "") + (x.vss ? ">" + x.vss + " " : "") + (x.ve ? "<" + x.ve + " " : "") + (x.vse ? "<=" + x.vse : "");
      return x.p + (x.v ? " " + x.v : "");
    }).filter(Boolean).slice(0, 3).join(" ; ");
    const res = upd.run(null, r.v || "", ranges, (r.urls || []).join("|"), (r.desc || "").slice(0, 900), r.id);
    if (res.changes === 0) miss++; else n++;
  }
  console.log("merged", f, "n", n, "miss", miss);
}
db.exec("COMMIT");
console.log("updated rows", n, "missing", miss);
db.close();
