//go:build ios

package server

import (
	"context"
	"net"
	"net/http"
	"path/filepath"
	"strconv"
	"time"

	pgdb "github.com/Autumn-27/artex/db"
)

// RunEmbedded boots the full ARTEX backend in-process and serves the real API on
// 127.0.0.1:port, reusing the exact mux built by (*Server).Handler — no route is
// re-registered here, so all 253 endpoints behave identically to the desktop
// binary. It returns as soon as the listener is bound (so the iOS caller's
// ArtexStart can return promptly); the serve loop and graceful shutdown run in
// background goroutines keyed off ctx. Cancel ctx (via ArtexStop) to shut the
// server down and close the stores.
//
// dataDir is the writable app-support directory supplied by the iOS shell; every
// store, skill and key resolves under it — never the read-only app bundle.
//
// NOTE: NewManager currently opens the Postgres stores (see cmd/artex). On iOS
// that connection has no server to reach, so RunEmbedded returns that error until
// the SQLite data layer (phase A3) lands. This file is the structural entry; it
// compiles into libartex.a today and starts serving once the store layer is iOS-
// native.
func RunEmbedded(ctx context.Context, port int, dataDir string) error {
	StartLogCapture()

	// Route the data layer to SQLite before opening stores — iOS has no Postgres.
	pgdb.SetSQLiteMode(filepath.Join(dataDir, "artex.sqlite"))

	// proxy "" → the MITM traffic-recording subsystem stays off on iOS (an app
	// cannot rewrite the system proxy anyway). Everything else boots as on desktop.
	mgr, err := NewManager(dataDir, "")
	if err != nil {
		return err
	}

	// On iOS, skills/keys live under the writable data dir, not next to the
	// (read-only) executable the way config.BaseDir() resolves them on desktop.
	skillDir := filepath.Join(dataDir, "skills")
	srv := New(ctx, mgr, skillDir, dataDir, dataDir)

	addr := net.JoinHostPort("127.0.0.1", strconv.Itoa(port))
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		_ = mgr.Close()
		return err
	}

	httpSrv := &http.Server{
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	// Serve in the background so this call returns once bound.
	go func() { _ = httpSrv.Serve(ln) }()

	// Tear down when the host cancels (ArtexStop) — graceful, then close stores.
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = httpSrv.Shutdown(shutdownCtx)
		_ = mgr.Close()
	}()

	return nil
}
