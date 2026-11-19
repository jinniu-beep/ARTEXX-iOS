//go:build ios

// Command artex-ios builds the ARTEX backend as a C archive (libartex.a) that the
// iOS Swift shell links and drives. ArtexStart spins up the real Go HTTP server
// on 127.0.0.1; ArtexStop tears it down. There is deliberately no os.Exit, no
// signal handling and no flag parsing — the process lifecycle belongs to the host
// app, which must not be killed by the backend.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"

	"github.com/Autumn-27/artex/server"
)

// cancel stops the running backend; set by ArtexStart, consumed by ArtexStop.
var cancel context.CancelFunc

// ArtexStart boots the embedded backend on 127.0.0.1:port with the given writable
// data directory. Returns 0 on success (server bound and serving), -1 on failure.
//
//export ArtexStart
func ArtexStart(port C.int, dataDir *C.char, webuiDir *C.char) C.int {
	dir := C.GoString(dataDir)
	web := C.GoString(webuiDir)
	ctx, c := context.WithCancel(context.Background())
	cancel = c
	if err := server.RunEmbedded(ctx, int(port), dir, web); err != nil {
		c()
		cancel = nil
		return -1
	}
	return 0
}

// ArtexStop gracefully shuts the backend down and releases the stores. Safe to
// call when nothing is running.
//
//export ArtexStop
func ArtexStop() {
	if cancel != nil {
		cancel()
		cancel = nil
	}
}

func main() {}
