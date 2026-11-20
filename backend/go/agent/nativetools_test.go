package agent

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	actool "github.com/Autumn-27/norma/tool"
)

func TestParsePortSpec(t *testing.T) {
	got := parsePortSpec("80,443,8000-8002")
	want := []int{80, 443, 8000, 8001, 8002}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d: %v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %v want %v", got, want)
		}
	}
	if len(parsePortSpec("")) == 0 {
		t.Fatal("empty spec should yield the common-ports default")
	}
	// dedup + out-of-range drop: 80 twice, 70000/0/-5 invalid.
	if g := parsePortSpec("80,80,70000,0,-5"); len(g) != 1 || g[0] != 80 {
		t.Fatalf("dedup/bounds failed: %v", g)
	}
}

func callTool(t *testing.T, tool actool.CoreTool, in map[string]any) string {
	t.Helper()
	raw, _ := json.Marshal(in)
	res, err := tool.Call(context.Background(), raw, nil)
	if err != nil {
		t.Fatalf("Call error: %v", err)
	}
	return res.Flatten()
}

func TestHTTPRequestTool(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Probe", "yes")
		w.WriteHeader(201)
		_, _ = io.WriteString(w, "hello-body")
	}))
	defer srv.Close()

	out := callTool(t, httpRequestTool(), map[string]any{"url": srv.URL})
	for _, want := range []string{"201", "X-Probe: yes", "hello-body"} {
		if !strings.Contains(out, want) {
			t.Fatalf("http_request output missing %q:\n%s", want, out)
		}
	}
	// Empty url is a graceful error, not a crash.
	if out := callTool(t, httpRequestTool(), map[string]any{"url": ""}); !strings.Contains(out, "url 为空") {
		t.Fatalf("empty url should error: %s", out)
	}
}

func TestPortScanTool(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer ln.Close()
	_, portStr, _ := net.SplitHostPort(ln.Addr().String())

	// Scan the open listener port plus one almost-certainly-closed port.
	out := callTool(t, portScanTool(), map[string]any{
		"host": "127.0.0.1", "ports": portStr + ",1", "timeout_ms": 500,
	})
	if !strings.Contains(out, portStr) {
		t.Fatalf("open port %s not reported: %s", portStr, out)
	}
}

func TestDNSLookupTool(t *testing.T) {
	// localhost usually resolves via hosts file without network; tolerate CI envs
	// where it doesn't by skipping rather than failing.
	out := callTool(t, dnsLookupTool(), map[string]any{"domain": "localhost", "type": "A"})
	if !strings.Contains(out, "127.0.0.1") && !strings.Contains(out, "::1") {
		t.Skipf("localhost A lookup inconclusive in this env: %s", out)
	}
}

func TestNativeNetToolsGatedByNoShell(t *testing.T) {
	saved := NoShell
	defer func() { NoShell = saved }()

	NoShell = false
	if n := nativeNetTools(); n != nil {
		t.Fatalf("native tools must be nil off-iOS, got %d", len(n))
	}
	NoShell = true
	if n := nativeNetTools(); len(n) != 3 {
		t.Fatalf("expected 3 native tools on iOS, got %d", len(n))
	}
}
