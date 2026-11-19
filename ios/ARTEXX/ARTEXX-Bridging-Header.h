#ifndef ARTEXX_Bridging_Header_h
#define ARTEXX_Bridging_Header_h

// Exposes the Go c-archive entry points (ArtexStart / ArtexStop) to Swift.
// libartex.h is generated next to libartex.a by backend/go/build-go.sh; the
// target's HEADER_SEARCH_PATHS includes ARTEXX/Go.
#include "libartex.h"

#endif /* ARTEXX_Bridging_Header_h */
