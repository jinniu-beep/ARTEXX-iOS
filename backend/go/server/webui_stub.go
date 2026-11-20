//go:build !embedui

package server

import (
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
)

// webuiDir, when set (iOS), makes webuiHandler serve the statically-exported
// frontend from that directory — the app bundle's webui/ (370 files). Empty →
// the no-embed 404 stub (desktop dev: run `next dev` separately, or build with
// -tags embedui).
var webuiDir string

// SetWebUIDir points the frontend handler at a directory of exported static
// files. Call before Handler() is built.
func SetWebUIDir(dir string) { webuiDir = dir }

// webuiHandler serves the frontend. With no directory set it is the no-embed
// stub; with one set it serves the Next.js static export, mirroring the embedui
// handler's resolution (exact file → <p>/index.html → <p>.html → SPA fallback).
func (s *Server) webuiHandler() http.Handler {
	if webuiDir == "" {
		return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			http.Error(w, "前端未内嵌到此二进制（开发用 next dev；发布用 -tags embedui 构建）", http.StatusNotFound)
		})
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := strings.TrimPrefix(path.Clean("/"+r.URL.Path), "/") // Clean removes .. traversal
		if p == "" {
			p = "index.html"
		}
		for _, cand := range []string{p, p + "/index.html", p + ".html"} {
			full := filepath.Join(webuiDir, filepath.FromSlash(cand))
			if st, err := os.Stat(full); err == nil && !st.IsDir() {
				http.ServeFile(w, r, full)
				return
			}
		}
		// client-side routing fallback
		http.ServeFile(w, r, filepath.Join(webuiDir, "index.html"))
	})
}
