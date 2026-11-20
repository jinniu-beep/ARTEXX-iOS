#!/usr/bin/env bash
# Cross-compile the ARTEX Go backend into a static C archive (libartex.a + .h)
# for iOS arm64. Must run on macOS with Xcode (needs the iPhoneOS SDK + clang).
#
# Usage: backend/go/build-go.sh [OUT_DIR]
#   OUT_DIR defaults to ios/ARTEXX/Go (relative to the repo root).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"          # backend/go
OUT="${1:-$HERE/../../ios/ARTEXX/Go}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun not found — this script must run on macOS with Xcode." >&2
  exit 1
fi

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"

export GOOS=ios
export GOARCH=arm64
export CGO_ENABLED=1
export CC="$CLANG"
export CGO_CFLAGS="-arch arm64 -miphoneos-version-min=15.0 -isysroot $SDK"
export CGO_LDFLAGS="-arch arm64 -miphoneos-version-min=15.0 -isysroot $SDK"

echo "== building libartex.a =="
echo "  go:   $(go version)"
echo "  SDK:  $SDK"
echo "  out:  $OUT/libartex.a"

cd "$HERE"
go build -buildmode=c-archive -trimpath -ldflags="-s -w" \
  -tags ios -o "$OUT/libartex.a" ./cmd/artex-ios

echo "== done =="
ls -lh "$OUT/libartex.a" "$OUT/libartex.h"
file "$OUT/libartex.a"
