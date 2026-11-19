
import fs from "node:fs";
import { DatabaseSync } from "node:sqlite";

const sql = fs.readFileSync("E:/ds/ARTEXX-iOS/backend/schema.sqlite.sql", "utf8");
const lines = sql.split("\n");

// Find the actual syntax error (not just incomplete input)
let prev = "";
for (let i = 0; i < lines.length; i++) {
  const test = prev + lines[i] + "\n";
  const db = new DatabaseSync(":memory:");
  try { 
    db.exec(test); 
    prev = test; 
  } catch(e) { 
    if (e.message.includes("incomplete")) {
      // Statement not complete yet, that's OK - continue accumulating
      prev = test;
      continue;
    }
    console.log("REAL SYNTAX ERROR at line", i+1);
    console.log("Error:", e.message.slice(0, 120));
    console.log("Context (lines", Math.max(0, i-4), "to", i+1, "):");
    for (let j = Math.max(0, i-4); j <= Math.min(i+2, lines.length-1); j++) {
      console.log("  " + (j+1) + ": " + lines[j]);
    }
    break;
  }
}
