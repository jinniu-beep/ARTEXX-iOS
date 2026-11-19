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

func post(ts *httptest.Server, path, token, body string) {
	req, _ := http.NewRequest(http.MethodPost, ts.URL+path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		fmt.Printf("  [FAIL] POST %-18s %v\n", path, err)
		fails++
		return
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	snip := strings.TrimSpace(string(raw))
	if len(snip) > 220 {
		snip = snip[:220]
	}
	tag := " ok "
	if resp.StatusCode >= 500 {
		tag = "FAIL"
		fails++
	}
	fmt.Printf("  [%s] POST %-18s %d  %s\n", tag, path, resp.StatusCode, snip)
}

func checkSkillCount(ts *httptest.Server, token string) {
	req, _ := http.NewRequest(http.MethodGet, ts.URL+"/api/skills", nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		fmt.Println("  [FAIL] /api/skills:", err)
		fails++
		return
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	var out struct {
		Skills []json.RawMessage `json:"skills"`
	}
	_ = json.Unmarshal(raw, &out)
	tag := " ok "
	if len(out.Skills) < 300 {
		tag = "FAIL"
		fails++
	}
	fmt.Printf("  [%s] /api/skills count = %d (want 319)\n", tag, len(out.Skills))
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

	skillDir := filepath.Join(dir, "skills")
	if s := os.Getenv("SKILLS_DIR"); s != "" {
		skillDir = s // point at the generated SKILL.md tree to verify loading
	}
	srv := server.New(context.Background(), mgr, skillDir, dir, dir)
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
		"/api/tools", // scans tools.schema/exec (jsonb → *json.RawMessage)
		"/api/skills",
		"/api/goals",
	} {
		get(ts, p, token)
	}

	fmt.Println("## authed WRITES (asset-subsystem dialect debt surfaces here)")
	post(ts, "/api/companies", token, `{"name":"probe-co","scope":[]}`)
	post(ts, "/api/assets", token, `{"task_id":0,"assets":[`+
		`{"type":"root_domain","domain":"probe.example"},`+
		`{"type":"subdomain","domain":"www.probe.example","record_type":"A","record_value":["203.0.113.9"]},`+
		`{"type":"ip","ip":"203.0.113.9","bound_domains":["probe.example"]},`+
		`{"type":"service","url":"http://probe.example","technologies":["nginx"],"port":80},`+
		`{"type":"app","app_name":"ProbeApp","bundle_id":"com.probe.app","category":"tool"},`+
		`{"type":"endpoint","url":"http://probe.example/api","method":"GET"}`+
		`]}`)
	// read back: did the writes persist (and does the list query still work)?
	get(ts, "/api/assets", token)

	fmt.Println("## writes that RETURN a time.Time created_at (the pg→sqlite *time.Time scan bug)")
	// task_categories.created_at is scanned into a Go time.Time — on SQLite the
	// column is TEXT, so without the shim's read-side coercion this 500s with
	// "unsupported Scan ... string into *time.Time".
	post(ts, "/api/task-categories", token, `{"name":"probe-cat"}`)
	get(ts, "/api/task-categories", token)
	// companies.created_at is `::text` into a Go string — exercises the
	// time.Time→string fallback on read now that the shim coerces *_at columns.
	get(ts, "/api/companies", token)

	fmt.Println("## skills library (expect the 319 converted SKILL.md to load)")
	checkSkillCount(ts, token)

	if cvePath := os.Getenv("CVE_DB"); cvePath != "" {
		fmt.Println("## CVE knowledge base (FTS5)")
		server.SetCVEStore(cvePath)
		get(ts, "/api/cve/stats", token)
		get(ts, "/api/cve/search?q=apache+tomcat&limit=3", token)
	}

	fmt.Printf("\n=== bootprobe done: %d failure(s) ===\n", fails)
	if fails > 0 {
		os.Exit(1)
	}
}
