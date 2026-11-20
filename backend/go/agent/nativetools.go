package agent

// Pure-Go network tools for platforms that forbid fork/exec (iOS). The SDK's Bash
// tool — and everything that shells out (nmap/curl/python) — cannot run inside the
// iOS sandbox, so on iOS the Bash tool is dropped and these Go-native replacements
// are offered instead: standard sockets only (no raw/SYN), native speed, no CORS.
//
// NoShell gates the whole thing: it is false everywhere except iOS, so desktop /
// host (and the test/probe) behaviour is byte-for-byte unchanged unless a caller
// explicitly sets it.

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	actool "github.com/Autumn-27/norma/tool"
)

// NoShell reports that this process cannot fork/exec (iOS). Set once at startup by
// the embedded server (and the host probe). Default false keeps desktop unchanged.
var NoShell bool

// SetNoShell toggles the fork/exec-less tool profile. Call before assembling agents.
func SetNoShell(v bool) { NoShell = v }

// platformDefaultTools returns the SDK default tools, dropping Bash when exec is
// unavailable. Read/Write/Edit/LS still work (they touch the sandboxed workDir).
func platformDefaultTools() []actool.CoreTool {
	if NoShell {
		return defaultToolsExcept("Bash")
	}
	return actool.DefaultTools()
}

// nativeNetTools are the pure-Go network tools, offered only where shell exec is
// unavailable (nil otherwise, so desktop agents are untouched).
func nativeNetTools() []actool.CoreTool {
	if !NoShell {
		return nil
	}
	return []actool.CoreTool{httpRequestTool(), portScanTool(), dnsLookupTool()}
}

const httpRespCap = 512 * 1024 // cap a response body so one page can't blow the context

func httpRequestTool() actool.CoreTool {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"url":        map[string]any{"type": "string", "description": "完整 URL，含 http(s)://"},
			"method":     map[string]any{"type": "string", "description": "GET/POST/PUT/… 默认 GET"},
			"headers":    map[string]any{"type": "object", "description": "请求头 {名:值}"},
			"body":       map[string]any{"type": "string", "description": "请求体"},
			"timeout_ms": map[string]any{"type": "integer", "description": "超时毫秒，默认 30000"},
		},
		"required": []any{"url"},
	}
	desc := "发一个 HTTP(S) 请求并返回状态行、响应头、响应体（纯 Go，不 fork；iOS 上替代 curl/浏览器的唯一网络请求方式，无 CORS 限制）。用于指纹识别、目录探测、SQLi/XSS/SSRF 等 HTTP 层 payload，以及读取接口。不自动跟随 3xx（便于观察重定向）。"
	return readTool("http_request", desc, schema, func(ctx context.Context, in json.RawMessage) (actool.Result, error) {
		var p struct {
			URL       string            `json:"url"`
			Method    string            `json:"method"`
			Headers   map[string]string `json:"headers"`
			Body      string            `json:"body"`
			TimeoutMs int               `json:"timeout_ms"`
		}
		_ = json.Unmarshal(in, &p)
		if strings.TrimSpace(p.URL) == "" {
			return actool.Errorf("url 为空"), nil
		}
		method := strings.ToUpper(strings.TrimSpace(p.Method))
		if method == "" {
			method = "GET"
		}
		timeout := 30 * time.Second
		if p.TimeoutMs > 0 {
			timeout = time.Duration(p.TimeoutMs) * time.Millisecond
		}
		rctx, cancel := context.WithTimeout(ctx, timeout)
		defer cancel()
		var body io.Reader
		if p.Body != "" {
			body = strings.NewReader(p.Body)
		}
		req, err := http.NewRequestWithContext(rctx, method, p.URL, body)
		if err != nil {
			return actool.Errorf(err.Error()), nil
		}
		for k, v := range p.Headers {
			req.Header.Set(k, v)
		}
		if req.Header.Get("User-Agent") == "" {
			req.Header.Set("User-Agent", "ARTEXX-iOS")
		}
		client := &http.Client{
			Timeout: timeout,
			// Surface redirects instead of following them.
			CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
		}
		resp, err := client.Do(req)
		if err != nil {
			return actool.Errorf(err.Error()), nil
		}
		defer resp.Body.Close()
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, httpRespCap))
		var sb strings.Builder
		fmt.Fprintf(&sb, "%s %s\n", resp.Proto, resp.Status)
		// Stable header order for readable, diff-friendly output.
		keys := make([]string, 0, len(resp.Header))
		for k := range resp.Header {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			for _, v := range resp.Header[k] {
				fmt.Fprintf(&sb, "%s: %s\n", k, v)
			}
		}
		sb.WriteByte('\n')
		sb.Write(raw)
		if int64(len(raw)) >= httpRespCap {
			sb.WriteString("\n... [响应体已截断] ...")
		}
		return actool.Text(sb.String()), nil
	})
}

func portScanTool() actool.CoreTool {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"host":       map[string]any{"type": "string", "description": "目标主机名或 IP"},
			"ports":      map[string]any{"type": "string", "description": "端口，逗号/区间，如 '80,443,8000-8100'；留空=常见端口"},
			"timeout_ms": map[string]any{"type": "integer", "description": "每端口超时毫秒，默认 1500"},
		},
		"required": []any{"host"},
	}
	desc := "对目标做 TCP connect 端口扫描（纯 Go，iOS 可用）。仅 TCP connect——iOS 沙箱不给原始套接字，故不支持 SYN/UDP/隐蔽扫描。返回开放端口列表。"
	return readTool("port_scan", desc, schema, func(ctx context.Context, in json.RawMessage) (actool.Result, error) {
		var p struct {
			Host      string `json:"host"`
			Ports     string `json:"ports"`
			TimeoutMs int    `json:"timeout_ms"`
		}
		_ = json.Unmarshal(in, &p)
		host := strings.TrimSpace(p.Host)
		if host == "" {
			return actool.Errorf("host 为空"), nil
		}
		ports := parsePortSpec(p.Ports)
		if len(ports) == 0 {
			return actool.Errorf("无有效端口"), nil
		}
		per := 1500 * time.Millisecond
		if p.TimeoutMs > 0 {
			per = time.Duration(p.TimeoutMs) * time.Millisecond
		}
		type res struct {
			port int
			open bool
		}
		results := make([]res, len(ports))
		sem := make(chan struct{}, 100) // bound concurrency
		var wg sync.WaitGroup
		for i, port := range ports {
			wg.Add(1)
			sem <- struct{}{}
			go func(i, port int) {
				defer wg.Done()
				defer func() { <-sem }()
				d := net.Dialer{Timeout: per}
				conn, err := d.DialContext(ctx, "tcp", net.JoinHostPort(host, strconv.Itoa(port)))
				if err == nil {
					_ = conn.Close()
					results[i] = res{port, true}
				} else {
					results[i] = res{port, false}
				}
			}(i, port)
		}
		wg.Wait()
		var open []int
		for _, r := range results {
			if r.open {
				open = append(open, r.port)
			}
		}
		sort.Ints(open)
		if len(open) == 0 {
			return actool.Text(fmt.Sprintf("%s: 扫描 %d 个端口，无开放。", host, len(ports))), nil
		}
		parts := make([]string, len(open))
		for i, p := range open {
			parts[i] = strconv.Itoa(p)
		}
		return actool.Text(fmt.Sprintf("%s 开放端口 (%d/%d): %s", host, len(open), len(ports), strings.Join(parts, ", "))), nil
	})
}

// parsePortSpec parses "80,443,8000-8100" into a de-duplicated port list (1..65535).
// Empty → a common-ports default.
func parsePortSpec(spec string) []int {
	spec = strings.TrimSpace(spec)
	if spec == "" {
		return []int{21, 22, 23, 25, 53, 80, 110, 111, 135, 139, 143, 443, 445, 993, 995,
			1433, 1521, 1723, 2049, 3306, 3389, 5432, 5900, 6379, 8000, 8080, 8443, 8888, 9200, 27017}
	}
	seen := map[int]bool{}
	var out []int
	add := func(p int) {
		if p >= 1 && p <= 65535 && !seen[p] {
			seen[p] = true
			out = append(out, p)
		}
	}
	for _, tok := range strings.Split(spec, ",") {
		tok = strings.TrimSpace(tok)
		if tok == "" {
			continue
		}
		if i := strings.IndexByte(tok, '-'); i >= 0 {
			lo, err1 := strconv.Atoi(strings.TrimSpace(tok[:i]))
			hi, err2 := strconv.Atoi(strings.TrimSpace(tok[i+1:]))
			if err1 != nil || err2 != nil {
				continue
			}
			if lo > hi {
				lo, hi = hi, lo
			}
			if hi-lo > 65535 {
				hi = lo + 65535
			}
			for p := lo; p <= hi; p++ {
				add(p)
			}
		} else if p, err := strconv.Atoi(tok); err == nil {
			add(p)
		}
	}
	return out
}

func dnsLookupTool() actool.CoreTool {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"domain": map[string]any{"type": "string", "description": "域名"},
			"type":   map[string]any{"type": "string", "description": "A/AAAA/CNAME/MX/NS/TXT，默认 A"},
		},
		"required": []any{"domain"},
	}
	desc := "DNS 解析（纯 Go net.Resolver，iOS 可用）。支持 A/AAAA/CNAME/MX/NS/TXT。"
	return readTool("dns_lookup", desc, schema, func(ctx context.Context, in json.RawMessage) (actool.Result, error) {
		var p struct {
			Domain string `json:"domain"`
			Type   string `json:"type"`
		}
		_ = json.Unmarshal(in, &p)
		domain := strings.TrimSpace(p.Domain)
		if domain == "" {
			return actool.Errorf("domain 为空"), nil
		}
		rctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()
		r := net.Resolver{}
		typ := strings.ToUpper(strings.TrimSpace(p.Type))
		if typ == "" {
			typ = "A"
		}
		var sb strings.Builder
		switch typ {
		case "A", "AAAA":
			ips, err := r.LookupIP(rctx, map[string]string{"A": "ip4", "AAAA": "ip6"}[typ], domain)
			if err != nil {
				return actool.Errorf(err.Error()), nil
			}
			for _, ip := range ips {
				sb.WriteString(ip.String() + "\n")
			}
		case "CNAME":
			c, err := r.LookupCNAME(rctx, domain)
			if err != nil {
				return actool.Errorf(err.Error()), nil
			}
			sb.WriteString(c + "\n")
		case "MX":
			mx, err := r.LookupMX(rctx, domain)
			if err != nil {
				return actool.Errorf(err.Error()), nil
			}
			for _, m := range mx {
				fmt.Fprintf(&sb, "%d %s\n", m.Pref, m.Host)
			}
		case "NS":
			ns, err := r.LookupNS(rctx, domain)
			if err != nil {
				return actool.Errorf(err.Error()), nil
			}
			for _, n := range ns {
				sb.WriteString(n.Host + "\n")
			}
		case "TXT":
			txt, err := r.LookupTXT(rctx, domain)
			if err != nil {
				return actool.Errorf(err.Error()), nil
			}
			for _, t := range txt {
				sb.WriteString(t + "\n")
			}
		default:
			return actool.Errorf("不支持的记录类型: " + typ), nil
		}
		out := strings.TrimSpace(sb.String())
		if out == "" {
			return actool.Text("(无记录)"), nil
		}
		return actool.Text(out), nil
	})
}
