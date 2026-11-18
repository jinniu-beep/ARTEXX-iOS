
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
let Parser, Swift;
try { Parser = require("tree-sitter"); Swift = require("tree-sitter-swift"); }
catch (e) { console.log("LOAD FAIL", e.message); process.exit(2); }

const parser = new Parser();
parser.setLanguage(Swift);
const root = "E:/ds/ARTEXX-iOS/ios/ARTEXX";
const files = [];
(function walk(d, b) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const rel = b ? b + "/" + e.name : e.name;
    if (e.isDirectory()) walk(path.join(d, e.name), rel);
    else if (e.name.endsWith(".swift")) files.push([root + "/" + rel, rel]);
  }
})(root, "");

let bad = 0;
for (const [full, rel] of files) {
  const src = fs.readFileSync(full, "utf8");
  const tree = parser.parse(src);
  let errs = [];
  (function visit(n) {
    if (n.type === "ERROR" || n.isMissing) {
      errs.push("line " + (n.startPosition.row + 1) + " [" + n.type + "] " + src.slice(n.startIndex, Math.min(n.endIndex, n.startIndex + 60)).replace(/\n/g, " "));
    }
    for (let i = 0; i < n.childCount; i++) visit(n.child(i));
  })(tree.rootNode);
  if (errs.length) { bad++; console.log("\n=== " + rel + " (" + errs.length + ")"); errs.slice(0, 8).forEach((e) => console.log("  " + e)); }
}
console.log("\nfiles:", files.length, "with errors:", bad);
