package server

// Add-only CVE API over the bundled cve.sqlite knowledge base. Routes are
// registered in Handler(); the store is nil until SetCVEStore succeeds, in which
// case the endpoints answer 503.

import (
	"log"
	"net/http"
	"strconv"
	"sync"

	"github.com/Autumn-27/artex/cve"
)

var (
	cveMu   sync.Mutex
	cveDB   *cve.DB
	cvePath string
)

// SetCVEStore records the CVE database path and tries to open it. It is safe to
// call before the file exists (the Swift shell unpacks cve.sqlite.gz in the
// background): the store opens lazily on the first request once the file appears.
func SetCVEStore(path string) {
	cveMu.Lock()
	cvePath = path
	cveMu.Unlock()
	ensureCVE()
}

// ensureCVE returns the open store, opening it on demand (file may have just
// finished unpacking). nil until the file is present and readable.
func ensureCVE() *cve.DB {
	cveMu.Lock()
	defer cveMu.Unlock()
	if cveDB != nil || cvePath == "" {
		return cveDB
	}
	d, err := cve.Open(cvePath)
	if err != nil {
		return nil // not unpacked yet; retried on the next request
	}
	cveDB = d
	if st, e := d.Stats(); e == nil {
		log.Printf("[cve] 已加载: %v 条", st["total"])
	}
	return cveDB
}

func (s *Server) cveSearch(w http.ResponseWriter, r *http.Request) {
	db := ensureCVE()
	if db == nil {
		writeErr(w, 503, "CVE 库尚未就绪")
		return
	}
	q := r.URL.Query()
	minScore, _ := strconv.ParseFloat(q.Get("min_score"), 64)
	limit, _ := strconv.Atoi(q.Get("limit"))
	offset, _ := strconv.Atoi(q.Get("offset"))
	entries, total, err := db.Search(q.Get("q"), q.Get("severity"), q.Get("vendor"), minScore, limit, offset)
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
	db := ensureCVE()
	if db == nil {
		writeErr(w, 503, "CVE 库尚未就绪")
		return
	}
	e, err := db.Get(r.PathValue("id"))
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
	db := ensureCVE()
	if db == nil {
		writeErr(w, 503, "CVE 库尚未就绪")
		return
	}
	st, err := db.Stats()
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, st)
}
