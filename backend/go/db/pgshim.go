package db

// On iOS the shared db/ SQL is Postgres dialect. This driver shim wraps modernc's
// "sqlite" driver and rewrites the handful of PG tokens that are invalid in
// SQLite but appear broadly: `expr::type` casts and a few PG column types in DDL
// (BIGSERIAL/TIMESTAMPTZ/…). Doing it at the driver layer fixes every query at
// once instead of editing ~160 sites. It is SQLite-only — the Postgres build
// never opens this driver — so these rewrites cannot affect Postgres behavior.
//
// It deliberately does NOT touch jsonb operators (`?`, `#>`), arrays (`= ANY`,
// `unnest`, `array_agg`) or `DISTINCT ON`; those few remaining sites are handled
// per-query where a route actually needs them.

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"encoding/json"
	"reflect"
	"regexp"
	"strings"
	"time"
)

func init() {
	sql.Register("sqlite-pgshim", pgShimDriver{base: moderncBaseDriver()})
}

// moderncBaseDriver returns the registered modernc "sqlite" driver by opening a
// throwaway handle (modernc's init has already registered it by the time this
// package's init runs, since we import it).
func moderncBaseDriver() driver.Driver {
	d, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		panic("sqlite-pgshim: cannot reach base sqlite driver: " + err.Error())
	}
	drv := d.Driver()
	_ = d.Close()
	return drv
}

type pgShimDriver struct{ base driver.Driver }

func (d pgShimDriver) Open(name string) (driver.Conn, error) {
	c, err := d.base.Open(name)
	if err != nil {
		return nil, err
	}
	return &shimConn{Conn: c}, nil
}

// shimConn forwards to the modernc connection, rewriting the SQL text on every
// path database/sql may take (direct exec/query for multi-statement + speed, and
// the prepared-statement fallback).
type shimConn struct{ driver.Conn }

func (c *shimConn) Prepare(query string) (driver.Stmt, error) {
	st, err := c.Conn.Prepare(rewriteSQL(query))
	if err != nil {
		return nil, err
	}
	return &shimStmt{Stmt: st}, nil
}

func (c *shimConn) PrepareContext(ctx context.Context, query string) (driver.Stmt, error) {
	if pc, ok := c.Conn.(driver.ConnPrepareContext); ok {
		st, err := pc.PrepareContext(ctx, rewriteSQL(query))
		if err != nil {
			return nil, err
		}
		return &shimStmt{Stmt: st}, nil
	}
	st, err := c.Conn.Prepare(rewriteSQL(query))
	if err != nil {
		return nil, err
	}
	return &shimStmt{Stmt: st}, nil
}

func (c *shimConn) ExecContext(ctx context.Context, query string, args []driver.NamedValue) (driver.Result, error) {
	if ec, ok := c.Conn.(driver.ExecerContext); ok {
		return ec.ExecContext(ctx, rewriteSQL(query), args)
	}
	return nil, driver.ErrSkip // let database/sql fall back to Prepare
}

func (c *shimConn) QueryContext(ctx context.Context, query string, args []driver.NamedValue) (driver.Rows, error) {
	if qc, ok := c.Conn.(driver.QueryerContext); ok {
		rows, err := qc.QueryContext(ctx, rewriteSQL(query), args)
		if err != nil {
			return nil, err
		}
		return wrapRows(rows), nil
	}
	return nil, driver.ErrSkip
}

func (c *shimConn) BeginTx(ctx context.Context, opts driver.TxOptions) (driver.Tx, error) {
	if bt, ok := c.Conn.(driver.ConnBeginTx); ok {
		return bt.BeginTx(ctx, opts)
	}
	return c.Conn.Begin() //nolint:staticcheck
}

// CheckNamedValue converts argument types that Postgres accepts but modernc
// rejects into their SQLite form: Go slices/maps/structs (bound to PG arrays like
// bigint[]/text[]/jsonb[]) become JSON text, and []byte (json.RawMessage) becomes
// a string so JSON columns land as TEXT (json_each/json_extract need text, not a
// BLOB). Scalars are left to the default converter.
func (c *shimConn) CheckNamedValue(nv *driver.NamedValue) error {
	switch v := nv.Value.(type) {
	case []byte:
		nv.Value = string(v)
		return nil
	case nil, bool, int64, float64, string, time.Time:
		return driver.ErrSkip
	default:
		switch reflect.ValueOf(v).Kind() {
		case reflect.Slice, reflect.Array, reflect.Map, reflect.Struct:
			if b, err := json.Marshal(v); err == nil {
				nv.Value = string(b)
				return nil
			}
		}
		return driver.ErrSkip
	}
}

var (
	// `expr::type` and `expr::type[]` → drop the cast (SQLite is dynamically typed;
	// on SQLite the operand already has the right affinity).
	reCast = regexp.MustCompile(`::[a-zA-Z_]+(?:\[\])?`)
	// PG column types used in runtime DDL (CREATE TABLE in Go). Uppercase-only so
	// lowercase column names like `timestamp` are never touched.
	rePGTypes = regexp.MustCompile(`\b(?:BIGSERIAL|SERIAL|TIMESTAMPTZ|TIMESTAMP|BIGINT|BOOLEAN|BYTEA)\b`)
	// `FOR UPDATE [OF ident] [SKIP LOCKED|NOWAIT]` → nothing. SQLite is a single
	// writer, so row locks are implicit; the clause is pure PG and invalid in SQLite.
	reForUpdate = regexp.MustCompile(`(?i)\s+FOR\s+UPDATE(?:\s+OF\s+[a-zA-Z_][a-zA-Z0-9_]*)?(?:\s+(?:SKIP\s+LOCKED|NOWAIT))?`)
	// SQLite forbids custom functions in a DEFAULT clause, so `DEFAULT now()` in
	// runtime DDL becomes the built-in CURRENT_TIMESTAMP (same text form).
	reDefaultNow = regexp.MustCompile(`(?i)DEFAULT\s+now\(\)`)
	// `STRING_AGG(DISTINCT col, 'sep')` → `GROUP_CONCAT(DISTINCT col)` (SQLite's
	// DISTINCT group_concat can't take a separator; the shared sites use ',').
	reStrAggDistinct = regexp.MustCompile(`(?i)STRING_AGG\(\s*DISTINCT\s+([A-Za-z_][A-Za-z0-9_.]*)\s*,\s*'[^']*'\s*\)`)
	// Non-distinct `STRING_AGG(expr, sep)` → `GROUP_CONCAT(expr, sep)` (same shape).
	reStrAgg = regexp.MustCompile(`(?i)\bSTRING_AGG\(`)
	// The recurring asset-merge idiom `(SELECT ARRAY(SELECT DISTINCT unnest(A || B)))`
	// → a JSON set-union over the two arrays (columns are JSON text on SQLite).
	reArrayMerge = regexp.MustCompile(`(?i)\(\s*SELECT\s+ARRAY\(\s*SELECT\s+DISTINCT\s+unnest\(\s*([\w.]+)\s*\|\|\s*([\w.]+)\s*\)\s*\)\s*\)`)
	// The `DISTINCT ON (...) elem FROM unnest(A || B) AS elem [ORDER BY ...]` merges
	// (open_ports, auth) → the same JSON set-union. Pragmatic: open_ports is then
	// deduped by whole entry, not by port-preferring-service (a re-scanned port with
	// new banner data can appear twice instead of merging).
	reDistinctOnMerge = regexp.MustCompile(`(?is)\(\s*SELECT\s+ARRAY\(\s*SELECT\s+DISTINCT\s+ON\s+\(.*?\)\s+elem\s+FROM\s+unnest\(\s*([\w.]+)\s*\|\|\s*([\w.]+)\s*\)\s+AS\s+elem.*?\)\s*\)`)
	// Postgres inet containment `net >>= addr` (SQLite tokenizes >>= as >> then =)
	// → the registered inet_contains(net, addr) scalar. Runs after :: casts are
	// stripped, so `$1::inet` is already `$1`.
	reInetContains = regexp.MustCompile(`([\w.]+)\s*>>=\s*(try_inet\([^)]*\)|\$\d+|[\w.]+)`)
	// `X.extra || EXCLUDED.extra` (jsonb object merge in the asset upserts) →
	// json_patch (SQLite `||` is string concat, which would corrupt the JSON).
	reExtraMerge = regexp.MustCompile(`([\w.]+\.extra)\s*\|\|\s*(EXCLUDED\.extra)`)

	// `$n::double precision` — reCast only handles single-word types, so strip this
	// two-word PG type before reCast runs.
	reDoublePrec = regexp.MustCompile(`::double precision`)
	// PG case-insensitive LIKE → SQLite LIKE (already case-insensitive for ASCII).
	reILIKE = regexp.MustCompile(`\bILIKE\b`)
	// GREATEST/LEAST(a,b,…) → SQLite's scalar max/min.
	reGreatest = regexp.MustCompile(`\bGREATEST\b`)
	reLeast    = regexp.MustCompile(`\bLEAST\b`)
	// `X AT TIME ZONE 'UTC'` → X (SQLite TEXT timestamps are already UTC).
	reAtTimeZone = regexp.MustCompile(`\s+AT TIME ZONE\s+'[^']*'`)
	// `EXTRACT(EPOCH FROM ` → `pg_epoch(` (registered); the original ')' closes it.
	reExtractEpoch = regexp.MustCompile(`(?i)EXTRACT\s*\(\s*EPOCH\s+FROM\s+`)
	// `now() ± make_interval(secs => $n)` → datetime('now', '±n seconds').
	reMakeIntervalPlus  = regexp.MustCompile(`(?i)now\(\)\s*\+\s*make_interval\(\s*secs\s*=>\s*(\$\d+)\s*\)`)
	reMakeIntervalMinus = regexp.MustCompile(`(?i)now\(\)\s*-\s*make_interval\(\s*secs\s*=>\s*(\$\d+)\s*\)`)
	// `NOW() - ($n * INTERVAL '1 day')` → datetime('now', '-n days').
	reIntervalDays = regexp.MustCompile(`(?i)now\(\)\s*-\s*\(\s*(\$\d+)\s*\*\s*INTERVAL\s+'1 day'\s*\)`)
)

func rewriteSQL(q string) string {
	q = reDoublePrec.ReplaceAllString(q, "")
	q = reCast.ReplaceAllString(q, "")
	q = rePGTypes.ReplaceAllStringFunc(q, func(m string) string {
		switch m {
		case "BIGSERIAL", "SERIAL", "BIGINT":
			return "INTEGER"
		case "TIMESTAMPTZ", "TIMESTAMP":
			return "TEXT"
		case "BOOLEAN":
			return "INTEGER"
		case "BYTEA":
			return "BLOB"
		}
		return m
	})
	q = reDefaultNow.ReplaceAllString(q, "DEFAULT CURRENT_TIMESTAMP")
	q = reForUpdate.ReplaceAllString(q, "")
	q = reStrAggDistinct.ReplaceAllString(q, "GROUP_CONCAT(DISTINCT $1)")
	q = reStrAgg.ReplaceAllString(q, "GROUP_CONCAT(")
	q = reArrayMerge.ReplaceAllString(q,
		`(SELECT json_group_array(value) FROM (SELECT value FROM json_each(COALESCE(${1},'[]')) UNION SELECT value FROM json_each(COALESCE(${2},'[]'))))`)
	// json(value): these are arrays of OBJECTS (auth/params), so re-embed each
	// element as JSON — a bare value would be stored double-encoded as a string.
	q = reDistinctOnMerge.ReplaceAllString(q,
		`(SELECT json_group_array(json(value)) FROM (SELECT value FROM json_each(COALESCE(${1},'[]')) UNION SELECT value FROM json_each(COALESCE(${2},'[]'))))`)
	q = reInetContains.ReplaceAllString(q, `inet_contains(${1}, ${2})`)
	q = reExtraMerge.ReplaceAllString(q, `json_patch(${1}, ${2})`)
	// PG date/interval/text ops → SQLite equivalents (helpers registered in sqlite.go).
	q = reAtTimeZone.ReplaceAllString(q, "")
	q = reExtractEpoch.ReplaceAllString(q, "pg_epoch(")
	q = reMakeIntervalPlus.ReplaceAllString(q, `datetime('now', '+'||(${1})||' seconds')`)
	q = reMakeIntervalMinus.ReplaceAllString(q, `datetime('now', '-'||(${1})||' seconds')`)
	q = reIntervalDays.ReplaceAllString(q, `datetime('now', '-'||(${1})||' days')`)
	q = reILIKE.ReplaceAllString(q, "LIKE")
	q = reGreatest.ReplaceAllString(q, "max")
	q = reLeast.ReplaceAllString(q, "min")
	return q
}

// --- result-side rewrites: time columns ---------------------------------
//
// SQLite stores timestamps as TEXT, so modernc returns a string for created_at /
// updated_at / *_at columns. The shared Go code was written for pgx, which hands
// back time.Time for timestamptz columns and scans those into *time.Time /
// sql.NullTime; database/sql cannot assign a string to *time.Time ("unsupported
// Scan ... storing driver.Value type string into type *time.Time"). So on the
// read path we convert the text of *_at columns back into time.Time — matching
// pgx — which every existing scan target already accepts. Wraps both the direct
// QueryContext path and the prepared-statement path.

type shimStmt struct{ driver.Stmt }

func (s *shimStmt) ExecContext(ctx context.Context, args []driver.NamedValue) (driver.Result, error) {
	if e, ok := s.Stmt.(driver.StmtExecContext); ok {
		return e.ExecContext(ctx, args)
	}
	return s.Stmt.Exec(namedToValues(args)) //nolint:staticcheck
}

func (s *shimStmt) QueryContext(ctx context.Context, args []driver.NamedValue) (driver.Rows, error) {
	if q, ok := s.Stmt.(driver.StmtQueryContext); ok {
		rows, err := q.QueryContext(ctx, args)
		if err != nil {
			return nil, err
		}
		return wrapRows(rows), nil
	}
	rows, err := s.Stmt.Query(namedToValues(args)) //nolint:staticcheck
	if err != nil {
		return nil, err
	}
	return wrapRows(rows), nil
}

func (s *shimStmt) Query(args []driver.Value) (driver.Rows, error) { //nolint:staticcheck
	rows, err := s.Stmt.Query(args) //nolint:staticcheck
	if err != nil {
		return nil, err
	}
	return wrapRows(rows), nil
}

func namedToValues(named []driver.NamedValue) []driver.Value {
	vals := make([]driver.Value, len(named))
	for i, nv := range named {
		vals[i] = nv.Value
	}
	return vals
}

// Per-column coercion kind, computed once from the column names.
const (
	colPlain uint8 = iota
	colTime        // *_at / open_until / … → time.Time
	colJSON        // jsonb → []byte (so *json.RawMessage targets scan)
)

type shimRows struct {
	driver.Rows
	kind []uint8
}

// wrapRows marks time/json columns; a result set with none keeps the base Rows
// untouched (no per-row cost, and its optional column-type interfaces survive).
func wrapRows(r driver.Rows) driver.Rows {
	cols := r.Columns()
	kind := make([]uint8, len(cols))
	anySpecial := false
	for i, c := range cols {
		switch {
		case isTimeColName(c):
			kind[i] = colTime
			anySpecial = true
		case isJSONColName(c):
			kind[i] = colJSON
			anySpecial = true
		}
	}
	if !anySpecial {
		return r
	}
	return &shimRows{Rows: r, kind: kind}
}

func (r *shimRows) Next(dest []driver.Value) error {
	if err := r.Rows.Next(dest); err != nil {
		return err
	}
	for i := range dest {
		if i >= len(r.kind) {
			continue
		}
		switch r.kind[i] {
		case colTime:
			switch v := dest[i].(type) {
			case string:
				if t, ok := parseSQLiteTime(v); ok {
					dest[i] = t
				}
			case []byte:
				if t, ok := parseSQLiteTime(string(v)); ok {
					dest[i] = t
				}
			}
		case colJSON:
			// modernc returns TEXT as a Go string; database/sql cannot assign a
			// string to *json.RawMessage (a named []byte), but CAN assign []byte.
			// Harmless for *string / *[]byte / []byte-intermediate targets.
			if s, ok := dest[i].(string); ok {
				dest[i] = []byte(s)
			}
		}
	}
	return nil
}

// isTimeColName decides which result columns to coerce back to time.Time. The
// `_at` suffix catches created_at/updated_at/started_at/sent_at/… across every
// table. A few timestamptz columns don't end in `_at` and ARE scanned into
// time.Time, so they're listed explicitly.
//
// Deliberately NOT listed: last_seen — assets always select it as `last_seen::text`
// into a Go `string` field, so leaving it a string keeps its exact value. Columns
// like companies.created_at (also `::text` into a string field) still match `_at`
// and become time.Time, which database/sql assigns to the *string target as an
// RFC3339 string — a harmless format change, never a scan error.
var extraTimeCols = map[string]bool{
	"open_until": true, // llm_profile_health.OpenUntil *time.Time
	"ts":         true, // llm_usage / command-run timestamp
	"last_fire":  true, // scheduled-trigger last fire
}

func isTimeColName(name string) bool {
	n := strings.ToLower(name)
	return strings.HasSuffix(n, "_at") || extraTimeCols[n]
}

// isJSONColName lists the jsonb columns scanned into *json.RawMessage (a named
// []byte). tools.schema/exec are scanned directly and fail as strings; payload /
// metadata are json.RawMessage fields too (mostly read via a []byte intermediate,
// which []byte also satisfies, so coercing them is safe and future-proofs any
// direct scan). Columns read into a plain Go string (extra/config/filter/params…)
// are deliberately left out — they already work and need no change.
var jsonCols = map[string]bool{
	"schema":   true, // tools.schema
	"exec":     true, // tools.exec
	"payload":  true, // exploration_nodes.payload
	"metadata": true, // exploration_nodes / activity metadata
}

func isJSONColName(name string) bool {
	return jsonCols[strings.ToLower(name)]
}

// Layouts cover datetime('now') ("2006-01-02 15:04:05", UTC, no zone) and the
// forms modernc emits when a time.Time is bound to a TEXT column (with zone, with
// fractional seconds, or ISO "T"). First match wins; a non-time *_at value that
// parses as none is left as-is.
var sqliteTimeLayouts = []string{
	"2006-01-02 15:04:05.999999999-07:00",
	"2006-01-02 15:04:05-07:00",
	"2006-01-02T15:04:05.999999999Z07:00",
	"2006-01-02T15:04:05Z07:00",
	"2006-01-02 15:04:05.999999999",
	"2006-01-02 15:04:05",
	"2006-01-02",
}

func parseSQLiteTime(s string) (time.Time, bool) {
	if s == "" {
		return time.Time{}, false
	}
	for _, layout := range sqliteTimeLayouts {
		if t, err := time.Parse(layout, s); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}
