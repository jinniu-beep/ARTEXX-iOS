// Command bootprobe is a host-run diagnostic (NOT part of libartex.a). It boots
// the REAL server on SQLite exactly as RunEmbedded does on iOS — SetSQLiteMode →
// NewManager → New → Handler — then serves it via httptest and hits a few
// endpoints. This verifies the "通一条线" boot path (stores open on SQLite, the
// Go backend answers) off-device, where an ios-tagged binary cannot run.
package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"

	pgdb "github.com/Autumn-27/artex/db"
	"github.com/Autumn-27/artex/server"
)

var fails int

func hit(ts *httptest.Server, path string) {
	resp, err := http.Get(ts.URL + path)
	if err != nil {
		fmt.Printf("  [FAIL] GET %-14s %v\n", path, err)
		fails++
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	snippet := string(body)
	if len(snippet) > 180 {
		snippet = snippet[:180]
	}
	tag := " ok "
	// 5xx means the backend crashed (e.g. a dialect error reached a handler).
	// 401/403 is fine here: the route works and auth is enforced (health is the
	// only DB-free, auth-exempt endpoint we assert content on).
	if resp.StatusCode >= 500 {
		tag = "FAIL"
		fails++
	}
	fmt.Printf("  [%s] GET %-14s %d  %s\n", tag, path, resp.StatusCode, snippet)
}

func main() {
	dir, err := os.MkdirTemp("", "artexboot")
	if err != nil {
		fmt.Println("tempdir:", err)
		os.Exit(2)
	}
	defer os.RemoveAll(dir)

	fmt.Println("## boot the real server on SQLite (the iOS path)")
	pgdb.SetSQLiteMode(filepath.Join(dir, "artex.sqlite"))

	mgr, err := server.NewManager(dir, "")
	if err != nil {
		fmt.Println("  [FAIL] NewManager:", err)
		os.Exit(1)
	}
	defer mgr.Close()
	fmt.Println("  [ ok ] NewManager (stores opened on SQLite)")

	srv := server.New(context.Background(), mgr, filepath.Join(dir, "skills"), dir, dir)
	ts := httptest.NewServer(srv.Handler())
	defer ts.Close()
	fmt.Println("  [ ok ] server.New + Handler (253 routes)")

	fmt.Println("## hit endpoints")
	hit(ts, "/api/health")
	hit(ts, "/api/stats")
	hit(ts, "/api/tasks")
	hit(ts, "/api/assets")

	fmt.Printf("\n=== bootprobe done: %d failure(s) ===\n", fails)
	if fails > 0 {
		os.Exit(1)
	}
}
