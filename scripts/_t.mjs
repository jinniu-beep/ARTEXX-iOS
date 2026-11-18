
import { DatabaseSync } from "node:sqlite";
const d = new DatabaseSync(":memory:");
try {
  d.exec("CREATE VIRTUAL TABLE t USING fts5(a)");
  d.exec("INSERT INTO t VALUES('apache tomcat rce')");
  console.log(JSON.stringify(d.prepare("SELECT * FROM t WHERE t MATCH 'tomcat'").all()));
} catch (e) { console.log("FTS5 FAIL", e.message); }
