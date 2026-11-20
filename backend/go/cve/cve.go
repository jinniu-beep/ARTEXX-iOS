// Package cve is a read-only query layer over the bundled cve.sqlite knowledge
// base (~201k CVEs, FTS5). It is add-only: a separate database from the main
// ARTEX store, opened immutable, and nil when the file is not present.
package cve

import (
	"database/sql"
	"fmt"
	"strings"
	"unicode"

	_ "modernc.org/sqlite"
)

// DB wraps the read-only cve.sqlite connection.
type DB struct{ db *sql.DB }

// Entry is one CVE row (the `search`/`hl` helper columns are omitted).
type Entry struct {
	ID        string  `json:"id"`
	Score     float64 `json:"score"`
	Severity  string  `json:"severity"`
	CWE       string  `json:"cwe"`
	Published string  `json:"published"`
	Vendor    string  `json:"vendor"`
	Product   string  `json:"product"`
	Title     string  `json:"title"`
	Desc      string  `json:"desc"`
	Refs      int     `json:"refs"`
	Tags      string  `json:"tags"`
}

const cols = `c.id, c.score, c.severity, c.cwe, c.published, c.vendor, c.product, c.title, c."desc", c.refs, c.tags`

// Open opens cve.sqlite read-only (immutable, so no WAL/journal is created next to
// the bundled file). Returns an error if the file is missing or unreadable.
func Open(path string) (*DB, error) {
	d, err := sql.Open("sqlite", "file:"+path+"?mode=ro&immutable=1")
	if err != nil {
		return nil, err
	}
	d.SetMaxOpenConns(4)
	if err := d.Ping(); err != nil {
		d.Close()
		return nil, fmt.Errorf("open cve db (%s): %w", path, err)
	}
	return &DB{db: d}, nil
}

func (d *DB) Close() error { return d.db.Close() }

func scanEntries(rows *sql.Rows) ([]Entry, error) {
	defer rows.Close()
	var out []Entry
	for rows.Next() {
		var e Entry
		if err := rows.Scan(&e.ID, &e.Score, &e.Severity, &e.CWE, &e.Published, &e.Vendor, &e.Product, &e.Title, &e.Desc, &e.Refs, &e.Tags); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// ftsMatch turns free text into a safe FTS5 prefix query: alphanumerics only, each
// token a prefix term. Empty input yields "" (no FTS constraint handled by caller).
func ftsMatch(q string) string {
	var terms []string
	for _, f := range strings.Fields(q) {
		t := strings.Map(func(r rune) rune {
			if unicode.IsLetter(r) || unicode.IsDigit(r) || r == '-' || r == '.' {
				return unicode.ToLower(r)
			}
			return -1
		}, f)
		if t != "" {
			terms = append(terms, t+"*")
		}
	}
	return strings.Join(terms, " ")
}

// Search runs a filtered, paged query. q is FTS5 full-text over the search column;
// severity/vendor/minScore are exact/range filters. Returns the page and the total.
func (d *DB) Search(q, severity, vendor string, minScore float64, limit, offset int) ([]Entry, int, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	base := "FROM cve c"
	var where []string
	var args []any
	if m := ftsMatch(q); m != "" {
		base = "FROM cve_fts f JOIN cve c ON c.rowid = f.rowid"
		where = append(where, "cve_fts MATCH ?")
		args = append(args, m)
	}
	if severity != "" {
		where = append(where, "c.severity = ?")
		args = append(args, severity)
	}
	if vendor != "" {
		where = append(where, "c.vendor = ?")
		args = append(args, vendor)
	}
	if minScore > 0 {
		where = append(where, "c.score >= ?")
		args = append(args, minScore)
	}
	w := ""
	if len(where) > 0 {
		w = " WHERE " + strings.Join(where, " AND ")
	}

	var total int
	if err := d.db.QueryRow("SELECT count(*) "+base+w, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := d.db.Query("SELECT "+cols+" "+base+w+" ORDER BY c.score DESC, c.published DESC LIMIT ? OFFSET ?",
		append(append([]any{}, args...), limit, offset)...)
	if err != nil {
		return nil, 0, err
	}
	entries, err := scanEntries(rows)
	return entries, total, err
}

// Get returns one CVE by id, or (nil, nil) if not found.
func (d *DB) Get(id string) (*Entry, error) {
	rows, err := d.db.Query("SELECT "+cols+" FROM cve c WHERE c.id = ?", id)
	if err != nil {
		return nil, err
	}
	entries, err := scanEntries(rows)
	if err != nil || len(entries) == 0 {
		return nil, err
	}
	return &entries[0], nil
}

// BySkill returns CVEs whose tags (comma-separated skill ids) include skillID.
func (d *DB) BySkill(skillID string, limit int) ([]Entry, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	rows, err := d.db.Query("SELECT "+cols+" FROM cve c WHERE (','||c.tags||',') LIKE ? ORDER BY c.score DESC LIMIT ?",
		"%,"+skillID+",%", limit)
	if err != nil {
		return nil, err
	}
	return scanEntries(rows)
}

// Stats returns the total and per-severity counts.
func (d *DB) Stats() (map[string]any, error) {
	var total int
	if err := d.db.QueryRow("SELECT count(*) FROM cve").Scan(&total); err != nil {
		return nil, err
	}
	rows, err := d.db.Query("SELECT COALESCE(NULLIF(severity,''),'unknown'), count(*) FROM cve GROUP BY severity")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	bySev := map[string]int{}
	for rows.Next() {
		var sev string
		var n int
		if err := rows.Scan(&sev, &n); err != nil {
			return nil, err
		}
		bySev[sev] = n
	}
	return map[string]any{"total": total, "by_severity": bySev}, rows.Err()
}
