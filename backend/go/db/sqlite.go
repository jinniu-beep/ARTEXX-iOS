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
	"net"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	sqlitelib "modernc.org/sqlite" // database/sql driver "sqlite" (pure Go, no cgo)
)

func boolToInt(b bool) int64 {
	if b {
		return 1
	}
	return 0
}

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
	// Postgres advisory locks are meaningless on SQLite (single writer). Register
	// them as no-ops so shared code that calls them resolves instead of erroring.
	noopLock := func(_ *sqlitelib.FunctionContext, _ []driver.Value) (driver.Value, error) {
		return int64(1), nil
	}
	sqlitelib.MustRegisterScalarFunction("pg_advisory_xact_lock", 1, noopLock)
	sqlitelib.MustRegisterScalarFunction("pg_advisory_lock", 1, noopLock)
	sqlitelib.MustRegisterScalarFunction("pg_advisory_unlock", 1, noopLock)

	// On SQLite the array columns already hold JSON text, so the list query's
	// array_to_json(col) is the identity (returns the stored JSON string).
	sqlitelib.MustRegisterScalarFunction("array_to_json", 1, func(_ *sqlitelib.FunctionContext, args []driver.Value) (driver.Value, error) {
		if len(args) == 0 {
			return nil, nil
		}
		return args[0], nil
	})

	// Postgres inet/CIDR helpers used by company/task scope resolution. The shim
	// rewrites `net >>= addr` → inet_contains(net, addr); try_inet/masklen back the
	// other scope queries.
	sqlitelib.MustRegisterScalarFunction("try_inet", 1, func(_ *sqlitelib.FunctionContext, a []driver.Value) (driver.Value, error) {
		if len(a) == 0 {
			return nil, nil
		}
		return a[0], nil // pass-through; inet_contains tolerates invalid input
	})
	sqlitelib.MustRegisterScalarFunction("masklen", 1, func(_ *sqlitelib.FunctionContext, a []driver.Value) (driver.Value, error) {
		s, _ := a[0].(string)
		if i := strings.IndexByte(s, '/'); i >= 0 {
			if n, err := strconv.Atoi(strings.TrimSpace(s[i+1:])); err == nil {
				return int64(n), nil
			}
		}
		if strings.Contains(s, ":") {
			return int64(128), nil
		}
		return int64(32), nil
	})
	sqlitelib.MustRegisterScalarFunction("inet_contains", 2, func(_ *sqlitelib.FunctionContext, a []driver.Value) (driver.Value, error) {
		netStr, _ := a[0].(string)
		addrStr, _ := a[1].(string)
		ip := net.ParseIP(strings.TrimSpace(addrStr))
		if netStr == "" || ip == nil {
			return int64(0), nil
		}
		if !strings.Contains(netStr, "/") { // bare IP → exact match
			other := net.ParseIP(strings.TrimSpace(netStr))
			return boolToInt(other != nil && other.Equal(ip)), nil
		}
		_, ipnet, err := net.ParseCIDR(strings.TrimSpace(netStr))
		if err != nil || ipnet == nil {
			return int64(0), nil
		}
		return boolToInt(ipnet.Contains(ip)), nil
	})

	// --- Postgres date/format/regex helpers used by stats, charts, notification
	// scheduling and ICP scope matching. Registered so the shared PG SQL runs with
	// minimal rewriting (the shim maps EXTRACT(EPOCH FROM x) → pg_epoch(x), strips
	// AT TIME ZONE, etc.). All operate on SQLite's TEXT timestamps.

	// pg_epoch(ts) → unix seconds (EXTRACT(EPOCH FROM ts)).
	sqlitelib.MustRegisterScalarFunction("pg_epoch", 1, func(_ *sqlitelib.FunctionContext, a []driver.Value) (driver.Value, error) {
		if len(a) == 0 {
			return int64(0), nil
		}
		if t, ok := pgParseTime(a[0]); ok {
			return t.Unix(), nil
		}
		return int64(0), nil
	})

	// to_char(ts, fmt) → formatted date string (YYYY/MM/DD/HH24/MI/SS tokens).
	sqlitelib.MustRegisterScalarFunction("to_char", 2, func(_ *sqlitelib.FunctionContext, a []driver.Value) (driver.Value, error) {
		s, _ := a[0].(string)
		t, ok := pgParseTime(a[0])
		if !ok {
			return s, nil
		}
		f, _ := a[1].(string)
		return t.Format(pgToGoLayout(f)), nil
	})

	// date_trunc(unit, ts) → ts truncated to unit (year/month/day/hour/minute).
	sqlitelib.MustRegisterScalarFunction("date_trunc", 2, func(_ *sqlitelib.FunctionContext, a []driver.Value) (driver.Value, error) {
		s, _ := a[1].(string)
		t, ok := pgParseTime(a[1])
		if !ok {
			return s, nil
		}
		unit, _ := a[0].(string)
		return truncTime(t, strings.ToLower(unit)).Format("2006-01-02 15:04:05"), nil
	})

	// regexp_replace(s, pattern, repl[, flags]) — POSIX classes like [[:space:]]
	// work in Go's regexp; the 'g' flag is implicit (ReplaceAll is global).
	sqlitelib.MustRegisterScalarFunction("regexp_replace", -1, func(_ *sqlitelib.FunctionContext, a []driver.Value) (driver.Value, error) {
		if len(a) < 3 {
			if len(a) > 0 {
				return a[0], nil
			}
			return nil, nil
		}
		s, _ := a[0].(string)
		pat, _ := a[1].(string)
		repl, _ := a[2].(string)
		re := cachedRegexp(pat)
		if re == nil {
			return s, nil
		}
		return re.ReplaceAllString(s, repl), nil
	})
}

// pgParseTime parses a SQLite TEXT timestamp into time.Time (shares the shim's
// layouts; also accepts []byte / time.Time).
func pgParseTime(v driver.Value) (time.Time, bool) {
	switch s := v.(type) {
	case string:
		return parseSQLiteTime(s)
	case []byte:
		return parseSQLiteTime(string(s))
	case time.Time:
		return s, true
	}
	return time.Time{}, false
}

// pgToGoLayout maps the Postgres to_char tokens used in the queries to a Go layout.
func pgToGoLayout(f string) string {
	return strings.NewReplacer(
		"YYYY", "2006",
		"HH24", "15",
		"MM", "01",
		"DD", "02",
		"MI", "04",
		"SS", "05",
	).Replace(f)
}

func truncTime(t time.Time, unit string) time.Time {
	switch unit {
	case "year":
		return time.Date(t.Year(), 1, 1, 0, 0, 0, 0, t.Location())
	case "month":
		return time.Date(t.Year(), t.Month(), 1, 0, 0, 0, 0, t.Location())
	case "day":
		return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
	case "hour":
		return t.Truncate(time.Hour)
	case "minute":
		return t.Truncate(time.Minute)
	}
	return t
}

var (
	reCacheMu sync.Mutex
	reCache   = map[string]*regexp.Regexp{}
)

// cachedRegexp compiles once per pattern (ICP patterns are a tiny fixed set).
func cachedRegexp(pat string) *regexp.Regexp {
	reCacheMu.Lock()
	defer reCacheMu.Unlock()
	if re, ok := reCache[pat]; ok {
		return re
	}
	re, err := regexp.Compile(pat)
	if err != nil {
		re = nil
	}
	reCache[pat] = re
	return re
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

// SQLiteMode reports whether the data layer is routed to SQLite (iOS). Used by a
// few callers outside this package that must swap a structural PG query.
func SQLiteMode() bool { return sqliteMode }

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
	sqlDB, err := sql.Open("sqlite-pgshim", sqliteDSN(dbPath))
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
