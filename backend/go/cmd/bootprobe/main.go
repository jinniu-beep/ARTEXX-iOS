// Command bootprobe is a host-run diagnostic (NOT part of libartex.a). It boots
// the REAL server on SQLite exactly as RunEmbedded does on iOS — SetSQLiteMode →
// NewManager → New → Handler — logs in, and hits the authed data routes. Each 5xx
// surfaces a Postgres-only-dialect query that still needs porting (A3-b); the
// server's SQL error is printed to stderr (captured in the CI log).
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"

	pgdb "github.com/Autumn-27/artex/db"
	"github.com/Autumn-27/artex/server"
)

var fails int

func get(ts *httptest.Server, path, token string) {
	req, _ := http.NewRequest(http.MethodGet, ts.URL+path, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		fmt.Printf("  [FAIL] GET %-18s %v\n", path, err)
		fails++
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	snip := strings.TrimSpace(string(body))
	if len(snip) > 220 {
		snip = snip[:220]
	}
	tag := " ok "
	if resp.StatusCode >= 500 { // 5xx = a handler crashed (dialect error reached it)
		tag = "FAIL"
		fails++
	}
	fmt.Printf("  [%s] GET %-18s %d  %s\n", tag, path, resp.StatusCode, snip)
}

func initAdmin(ts *httptest.Server) string {
	payload, _ := json.Marshal(map[string]string{"password": "ArtexTest123!"})
	resp, err := http.Post(ts.URL+"/api/auth/init", "application/json", bytes.NewReader(payload))
	if err != nil {
		fmt.Println("  [FAIL] auth/init:", err)
		fails++
		return ""
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	var out struct {
		Token string `json:"token"`
	}
	_ = json.Unmarshal(raw, &out)
	if out.Token == "" {
		fmt.Printf("  [FAIL] auth/init %d  %s\n", resp.StatusCode, strings.TrimSpace(string(raw)))
		fails++
	} else {
		fmt.Printf("  [ ok ] auth/init -> token (%d chars)\n", len(out.Token))
	}
	return out.Token
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

	fmt.Println("## unauthed")
	get(ts, "/api/health", "")

	fmt.Println("## authenticate")
	token := initAdmin(ts)

	fmt.Println("## authed data routes (Postgres-only dialect debt surfaces here as 5xx)")
	for _, p := range []string{
		"/api/stats",
		"/api/tasks",
		"/api/assets",
		"/api/findings",
		"/api/companies",
		"/api/conversations",
		"/api/agents",
		"/api/skills",
		"/api/goals",
	} {
		get(ts, p, token)
	}

	fmt.Printf("\n=== bootprobe done: %d failure(s) ===\n", fails)
	if fails > 0 {
		os.Exit(1)
	}
}
