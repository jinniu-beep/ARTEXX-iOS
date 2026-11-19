package server

// Add-only CVE API over the bundled cve.sqlite knowledge base. Routes are
// registered in Handler(); the store is nil until SetCVEStore succeeds, in which
// case the endpoints answer 503.

import (
	"log"
	"net/http"
	"strconv"

	"github.com/Autumn-27/artex/cve"
)

var cveDB *cve.DB

// SetCVEStore opens the read-only CVE database at path. A missing/unreadable file
// just leaves the CVE routes returning 503; it never blocks startup.
func SetCVEStore(path string) {
	d, err := cve.Open(path)
	if err != nil {
		log.Printf("[cve] 未加载 (%s): %v", path, err)
		return
	}
	cveDB = d
	if st, err := d.Stats(); err == nil {
		log.Printf("[cve] 已加载: %v 条", st["total"])
	}
}

func (s *Server) cveSearch(w http.ResponseWriter, r *http.Request) {
	if cveDB == nil {
		writeErr(w, 503, "CVE 库未加载")
		return
	}
	q := r.URL.Query()
	minScore, _ := strconv.ParseFloat(q.Get("min_score"), 64)
	limit, _ := strconv.Atoi(q.Get("limit"))
	offset, _ := strconv.Atoi(q.Get("offset"))
	entries, total, err := cveDB.Search(q.Get("q"), q.Get("severity"), q.Get("vendor"), minScore, limit, offset)
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	if entries == nil {
		entries = []cve.Entry{}
	}
	writeJSON(w, 200, map[string]any{"results": entries, "total": total})
}

func (s *Server) cveGet(w http.ResponseWriter, r *http.Request) {
	if cveDB == nil {
		writeErr(w, 503, "CVE 库未加载")
		return
	}
	e, err := cveDB.Get(r.PathValue("id"))
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	if e == nil {
		writeErr(w, 404, "CVE not found")
		return
	}
	writeJSON(w, 200, e)
}

func (s *Server) cveStats(w http.ResponseWriter, r *http.Request) {
	if cveDB == nil {
		writeErr(w, 503, "CVE 库未加载")
		return
	}
	st, err := cveDB.Stats()
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, st)
}
