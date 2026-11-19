package db

// SQLite data source for iOS (and host tests). Builds on all platforms so the
// open path is exercisable off-device; the iOS wiring that routes NewManager
// here lives in open_ios.go. OpenSQLite deliberately mirrors the Postgres Open:
// apply the schema (idempotent), then seed the built-in agents.

import (
	"context"
	"database/sql"
	"database/sql/driver"
	_ "embed"
	"fmt"
	"time"

	sqlitelib "modernc.org/sqlite" // database/sql driver "sqlite" (pure Go, no cgo)
)

//go:embed schema_sqlite.sql
var sqliteSchema string

// SQLite has no now(); the shared db/ SQL calls now() in ~58 places (and the
// converted schema uses datetime('now') for defaults). Registering now() as a
// scalar function that returns SQLite's text-timestamp form lets all that
// Postgres-style SQL run unchanged instead of rewriting every call site. The
// registration is global to the modernc "sqlite" driver and harmless on
// platforms that never open a SQLite connection.
func init() {
	sqlitelib.MustRegisterScalarFunction("now", 0, func(_ *sqlitelib.FunctionContext, _ []driver.Value) (driver.Value, error) {
		return time.Now().UTC().Format("2006-01-02 15:04:05"), nil
	})
}

// Mode routing: on iOS, RunEmbedded calls SetSQLiteMode before opening stores so
// the shared Open/DSN/coordinateWithSchemaMigration (defined in the Postgres-
// oriented db.go) delegate here instead of touching Postgres.
var (
	sqliteMode     bool
	sqliteFilePath string
)

// SetSQLiteMode routes Open/DSN to SQLite at dbPath. Call once before NewManager.
func SetSQLiteMode(dbPath string) {
	sqliteMode = true
	sqliteFilePath = dbPath
}

// sqliteDSN builds a modernc DSN. "" / ":memory:" → a shared in-memory database
// (used by the probe/tests); any other value is treated as a file path.
func sqliteDSN(dbPath string) string {
	if dbPath == "" || dbPath == ":memory:" {
		return "file::memory:?cache=shared"
	}
	return "file:" + dbPath + "?cache=shared"
}

// OpenSQLite opens (or creates) the SQLite database, applies the converted
// schema, and seeds the built-in agents — the iOS equivalent of Open(dsn).
func OpenSQLite(dbPath string) (*DB, error) {
	sqlDB, err := sql.Open("sqlite", sqliteDSN(dbPath))
	if err != nil {
		return nil, err
	}
	// SQLite is a single writer; one connection serializes writes and keeps a
	// ":memory:" database alive for the process's lifetime.
	sqlDB.SetMaxOpenConns(1)
	sqlDB.SetConnMaxLifetime(0)

	for _, pragma := range []string{
		"PRAGMA journal_mode=WAL",
		"PRAGMA foreign_keys=ON",
		"PRAGMA busy_timeout=5000",
	} {
		if _, err := sqlDB.Exec(pragma); err != nil {
			sqlDB.Close()
			return nil, fmt.Errorf("pragma %q: %w", pragma, err)
		}
	}
	if err := sqlDB.Ping(); err != nil {
		sqlDB.Close()
		return nil, fmt.Errorf("ping sqlite (%s): %w", dbPath, err)
	}

	d := &DB{sqlDB}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	// modernc runs the whole multi-statement script, honoring BEGIN/COMMIT.
	if _, err := sqlDB.ExecContext(ctx, sqliteSchema); err != nil {
		sqlDB.Close()
		return nil, fmt.Errorf("apply sqlite schema: %w", err)
	}
	if err := d.seedBuiltins(); err != nil {
		sqlDB.Close()
		return nil, fmt.Errorf("seed builtins: %w", err)
	}
	return d, nil
}
