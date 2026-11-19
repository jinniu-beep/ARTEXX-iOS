// Command sqliteprobe is an A3 diagnostic (host-run, NOT part of libartex.a): it
// loads the converted SQLite schema into modernc.org/sqlite and checks the two
// things that decide the A3 data-layer approach — whether the whole schema loads
// in one Exec, and whether $N placeholders bind the way pgx/Postgres binds them
// (so the existing 751 $N query sites can stay as-is instead of being rewritten).
package main

import (
	"database/sql"
	"fmt"
	"os"

	artexdb "github.com/Autumn-27/artex/db"
	_ "modernc.org/sqlite"
)

var fails int

func check(label string, err error) bool {
	if err != nil {
		fmt.Printf("  [FAIL] %-46s %v\n", label, err)
		fails++
		return false
	}
	fmt.Printf("  [ ok ] %s\n", label)
	return true
}

func assert(label string, cond bool, detail string) {
	if !cond {
		fmt.Printf("  [FAIL] %-46s %s\n", label, detail)
		fails++
		return
	}
	fmt.Printf("  [ ok ] %-46s %s\n", label, detail)
}

func exec(db *sql.DB, q string, args ...any) error {
	_, err := db.Exec(q, args...)
	return err
}

func main() {
	schemaPath := "../../backend/schema.sqlite.sql"
	if len(os.Args) > 1 {
		schemaPath = os.Args[1]
	}

	db, err := sql.Open("sqlite", "file:probe?mode=memory&cache=shared")
	if err != nil {
		fmt.Println("open:", err)
		os.Exit(2)
	}
	defer db.Close()
	db.SetMaxOpenConns(1) // SQLite is a single writer

	fmt.Println("## 0. pragmas")
	for _, p := range []string{"PRAGMA journal_mode=WAL", "PRAGMA foreign_keys=ON", "PRAGMA busy_timeout=5000"} {
		var out string
		_ = db.QueryRow(p).Scan(&out)
		fmt.Printf("  %-32s -> %q\n", p, out)
	}

	fmt.Println("## 1. load converted schema (single multi-statement Exec — the real path)")
	schema, err := os.ReadFile(schemaPath)
	if !check(fmt.Sprintf("read %s (%d bytes)", schemaPath, len(schema)), err) {
		os.Exit(2)
	}
	// This is exactly what the iOS open layer will do. modernc runs the whole
	// script, honoring BEGIN/COMMIT; it halts at the first error and names it.
	check("schema loads in ONE Exec", exec(db, string(schema)))
	var ntab int
	_ = db.QueryRow(`SELECT count(*) FROM sqlite_master WHERE type='table'`).Scan(&ntab)
	assert("all tables created", ntab >= 49, fmt.Sprintf("%d tables", ntab))

	fmt.Println("## 2. $N placeholder semantics (must match pgx)")
	check("create ptest", exec(db, `CREATE TABLE ptest(a TEXT, b TEXT, c TEXT)`))

	// Reused $1: pgx sends 2 args for distinct placeholders $1,$2.
	if check(`INSERT ($1,$1,$2) with 2 args`, exec(db, `INSERT INTO ptest(a,b,c) VALUES ($1,$1,$2)`, "X", "Y")) {
		var a, b, c string
		_ = db.QueryRow(`SELECT a,b,c FROM ptest`).Scan(&a, &b, &c)
		assert("reused $1 binds same value", a == "X" && b == "X" && c == "Y", fmt.Sprintf("a=%q b=%q c=%q (want X,X,Y)", a, b, c))
	}
	_, _ = db.Exec(`DELETE FROM ptest`)

	// Out-of-order: pgx binds by NUMBER, so arg0->$1, arg1->$2 regardless of order.
	if check(`INSERT ($2,$1,$1) with 2 args`, exec(db, `INSERT INTO ptest(a,b,c) VALUES ($2,$1,$1)`, "P", "Q")) {
		var a, b, c string
		_ = db.QueryRow(`SELECT a,b,c FROM ptest`).Scan(&a, &b, &c)
		assert("out-of-order $N maps by number (pgx-compatible)", a == "Q" && b == "P" && c == "P", fmt.Sprintf("a=%q b=%q c=%q (want Q,P,P)", a, b, c))
	}

	fmt.Println("## 3. dialect features used across db/")
	check("ON CONFLICT DO NOTHING", exec(db, `INSERT INTO ptest(a,b,c) VALUES ('t','t','t') ON CONFLICT DO NOTHING`))
	var rid int64
	check("RETURNING", db.QueryRow(`INSERT INTO ptest(a,b,c) VALUES ('r','r','r') RETURNING rowid`).Scan(&rid))
	var s string
	check("datetime('now')", db.QueryRow(`SELECT datetime('now')`).Scan(&s))
	check("json_extract", db.QueryRow(`SELECT json_extract('{"port":80}','$.port')`).Scan(&s))
	var n int
	check("json_each (= ANY(array) substitute)", db.QueryRow(`SELECT count(*) FROM json_each('[1,2,3]')`).Scan(&n))
	assert("json_each counts elements", n == 3, fmt.Sprintf("n=%d", n))

	fmt.Println("## 4. real open path: db.OpenSQLite (embedded schema + seedBuiltins)")
	ad, err := artexdb.OpenSQLite(":memory:")
	if check(`db.OpenSQLite(":memory:")`, err) {
		defer ad.Close()
		var nt int
		_ = ad.QueryRow(`SELECT count(*) FROM sqlite_master WHERE type='table'`).Scan(&nt)
		assert("OpenSQLite created all tables", nt >= 49, fmt.Sprintf("%d tables", nt))
		var na int
		_ = ad.QueryRow(`SELECT count(*) FROM agents WHERE builtin=1`).Scan(&na)
		assert("seedBuiltins seeded agents", na >= 5, fmt.Sprintf("%d builtin agents", na))
		var k string
		if e := ad.QueryRow(`SELECT key FROM agents WHERE key=$1`, "planner").Scan(&k); e != nil {
			check("select planner via $1", e)
		} else {
			assert("planner agent seeded", k == "planner", "key="+k)
		}
	}

	fmt.Printf("\n=== probe done: %d failure(s) ===\n", fails)
	if fails > 0 {
		os.Exit(1)
	}
}
