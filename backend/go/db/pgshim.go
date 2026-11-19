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
	"regexp"
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
	return c.Conn.Prepare(rewriteSQL(query))
}

func (c *shimConn) PrepareContext(ctx context.Context, query string) (driver.Stmt, error) {
	if pc, ok := c.Conn.(driver.ConnPrepareContext); ok {
		return pc.PrepareContext(ctx, rewriteSQL(query))
	}
	return c.Conn.Prepare(rewriteSQL(query))
}

func (c *shimConn) ExecContext(ctx context.Context, query string, args []driver.NamedValue) (driver.Result, error) {
	if ec, ok := c.Conn.(driver.ExecerContext); ok {
		return ec.ExecContext(ctx, rewriteSQL(query), args)
	}
	return nil, driver.ErrSkip // let database/sql fall back to Prepare
}

func (c *shimConn) QueryContext(ctx context.Context, query string, args []driver.NamedValue) (driver.Rows, error) {
	if qc, ok := c.Conn.(driver.QueryerContext); ok {
		return qc.QueryContext(ctx, rewriteSQL(query), args)
	}
	return nil, driver.ErrSkip
}

func (c *shimConn) BeginTx(ctx context.Context, opts driver.TxOptions) (driver.Tx, error) {
	if bt, ok := c.Conn.(driver.ConnBeginTx); ok {
		return bt.BeginTx(ctx, opts)
	}
	return c.Conn.Begin() //nolint:staticcheck
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
)

func rewriteSQL(q string) string {
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
	return q
}
