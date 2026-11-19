
import fs from "node:fs";
import { DatabaseSync } from "node:sqlite";

const sql = fs.readFileSync("E:/ds/ARTEXX-iOS/backend/schema.sqlite.sql", "utf8");

// Find where exec fails by incrementally adding content
const lines = sql.split("\n");
let lo = 0, hi = lines.length;

// First try full
const db0 = new DatabaseSync(":memory:");
try { db0.exec(sql); console.log("Full exec OK!"); process.exit(0); } catch(e) { console.log("Full fails:", e.message.slice(0,80)); }

// Binary search for failure point
let failLine = hi;
for (let attempt = 0; attempt < 15; attempt++) {
  const mid = Math.floor((lo + hi) / 2);
  const partial = lines.slice(0, mid).join("\n");
  const db = new DatabaseSync(":memory:");
  let failed = false;
  try { db.exec(partial); } catch(e) { failed = true; }
  if (failed) { hi = mid; failLine = mid; }
  else lo = mid;
}

console.log("Failure around line:", failLine);
console.log("Lines before:", lines.slice(Math.max(0, failLine-5), failLine+3).join("\n"));
